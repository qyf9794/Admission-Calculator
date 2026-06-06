import Foundation

struct ChanceEngine {
    private static let exactRecommendationRequestedLimit = 8
    private static let exactRecommendationCombinationLimit = 5_000
    private static let recommendationGreedyCandidateLimit = 64
    private static let recommendationRankPriorityCandidateLimit = 24
    private static let recommendationProbabilityCandidateLimit = 16
    private static let recommendationReplacementPassLimit = 4
    private static let recommendationReplacementCandidateLimit = 64
    private static let recommendationReplacementRemovalLimit = 40
    private static let conservativeHighSchoolFallback = HighSchoolContext(
        id: "unknown",
        name: "其他/手动评估学校",
        city: "中国",
        admitRankingBand: 3,
        resources: 3,
        counseling: 3,
        top30TrackRecord: 2,
        transparency: 2
    )

    let colleges: [College]
    let gateRules: [CollegeGateRule]
    let highSchools: [HighSchoolContext]
    let internationalSignals: [InternationalSignal]
    let chinaAdmissionSignals: [ChinaUndergradAdmissionSignal]
    let academicBenchmarks: [AcademicBenchmark]

    init(
        colleges: [College] = AdmissionsSeedData.colleges,
        gateRules: [CollegeGateRule] = AdmissionsSeedData.gateRules,
        highSchools: [HighSchoolContext] = AdmissionsSeedData.highSchools,
        internationalSignals: [InternationalSignal] = AdmissionsSeedData.internationalSignals,
        chinaAdmissionSignals: [ChinaUndergradAdmissionSignal] = AdmissionsSeedData.chinaAdmissionSignals,
        academicBenchmarks: [AcademicBenchmark] = AdmissionsSeedData.academicBenchmarks
    ) {
        self.colleges = colleges
        self.gateRules = gateRules
        self.highSchools = highSchools
        self.internationalSignals = internationalSignals
        self.chinaAdmissionSignals = chinaAdmissionSignals
        self.academicBenchmarks = academicBenchmarks
    }

    func evaluate(
        profile: StudentProfile,
        selectedCollegeIDs: Set<String>,
        selectionSource: PortfolioSelectionSource = .manual,
        automaticRecommendationSteps: [RecommendationStep]? = nil
    ) -> PortfolioResult {
        evaluate(
            profile: profile,
            selectedCollegeIDs: selectedCollegeIDs,
            selectionSource: selectionSource,
            automaticRecommendationSteps: automaticRecommendationSteps,
            automaticRecommendationStepsWereJustGenerated: false
        )
    }

    func evaluateAutomaticRecommendation(profile: StudentProfile) -> PortfolioResult {
        let recommendationSteps = recommendationSteps(for: profile, count: effectiveRequestedSchoolCount(for: profile))
        return evaluate(
            profile: profile,
            selectedCollegeIDs: Set(recommendationSteps.map(\.result.college.id)),
            selectionSource: .automatic,
            automaticRecommendationSteps: recommendationSteps,
            automaticRecommendationStepsWereJustGenerated: true
        )
    }

    private func evaluate(
        profile: StudentProfile,
        selectedCollegeIDs: Set<String>,
        selectionSource: PortfolioSelectionSource,
        automaticRecommendationSteps: [RecommendationStep]?,
        automaticRecommendationStepsWereJustGenerated: Bool
    ) -> PortfolioResult {
        let profileScore = studentScore(profile)
        let selectable = selectableColleges(for: profile)
        let selected = selectable.filter { selectedCollegeIDs.contains($0.id) }
        let resolvedSource: PortfolioSelectionSource = selectedCollegeIDs.isEmpty && selectionSource != .automatic ? .none : selectionSource
        let schoolResults = selected.map { chance(for: $0, profile: profile) }
            .sorted { $0.adjustedProbability > $1.adjustedProbability }
        let currentIDs = Set(schoolResults.map(\.college.id))
        let selectedIDsFullyResolved = selectedCollegeIDs == currentIDs
        let suppliedRecommendationSteps = automaticRecommendationSteps ?? []
        let suppliedStepsAreCurrent = recommendationSteps(suppliedRecommendationSteps, match: schoolResults)
        let suppliedStepsAreTrustedGeneratedSteps = resolvedSource == .automatic &&
            automaticRecommendationStepsWereJustGenerated &&
            suppliedStepsAreCurrent
        let regeneratedRecommendationSteps = resolvedSource == .automatic && !suppliedStepsAreTrustedGeneratedSteps
            ? recommendationSteps(for: profile, count: effectiveRequestedSchoolCount(for: profile))
            : []
        let suppliedStepsMatchRegenerated = suppliedStepsAreTrustedGeneratedSteps || (suppliedStepsAreCurrent &&
            recommendationSteps(suppliedRecommendationSteps, matchRegenerated: regeneratedRecommendationSteps)
        )
        let candidateRecommendationSteps = suppliedStepsMatchRegenerated
            ? suppliedRecommendationSteps
            : regeneratedRecommendationSteps
        let matchingRecommendationSteps = resolvedSource == .automatic &&
            selectedIDsFullyResolved &&
            Set(candidateRecommendationSteps.map(\.result.college.id)) == currentIDs
            ? candidateRecommendationSteps
            : []
        let automaticPortfolioWasGenerated = resolvedSource == .automatic &&
            (!matchingRecommendationSteps.isEmpty || (selectedCollegeIDs.isEmpty && currentIDs.isEmpty))
        let recommended = resolvedSource == .automatic
            ? matchingRecommendationSteps.map(\.result.college)
            : []
        return PortfolioResult(
            profileSnapshot: profile,
            selectedCollegeIDs: selectedCollegeIDs,
            schoolResults: schoolResults,
            recommendedSchools: recommended,
            recommendationSteps: matchingRecommendationSteps,
            selectionSource: resolvedSource,
            selectedBucketCounts: bucketCounts(for: schoolResults),
            selectionWarnings: selectionWarnings(profile: profile, requestedIDs: selectedCollegeIDs),
            recommendationWarnings: automaticPortfolioWasGenerated ? recommendationWarnings(profile: profile, recommendedResults: schoolResults) : [],
            t10AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank <= 10 }),
            t11T30AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank > 10 && $0.college.rank <= 30 }),
            t30AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank <= 30 }),
            t50AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank <= 50 }),
            liberalArtsT10AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .liberalArtsCollege && $0.college.rank <= 10 }),
            liberalArtsT30AtLeastOne: atLeastOneProbability(schoolResults.filter { $0.college.category == .liberalArtsCollege && $0.college.rank <= 30 }),
            selectedAtLeastOne: atLeastOneProbability(schoolResults),
            profileScore: profileScore,
            recommendationExpectedValueTotal: recommendationBestOfferExpectedValue(for: matchingRecommendationSteps),
            generatedAt: Date()
        )
    }

    func effectiveRequestedSchoolCount(for profile: StudentProfile, requested count: Int? = nil) -> Int {
        let requested = max(0, count ?? profile.requestedSchoolCount)
        guard profile.round == .earlyDecision else {
            return requested
        }
        return min(requested, 1)
    }

    private func recommendationSteps(_ steps: [RecommendationStep], match currentResults: [ChanceResult]) -> Bool {
        let stepIDs = steps.map(\.result.college.id)
        guard stepIDs.count == currentResults.count, Set(stepIDs).count == stepIDs.count else {
            return false
        }
        let expectedOrders = steps.isEmpty ? [] : Array(1...steps.count)
        guard steps.map(\.order) == expectedOrders else {
            return false
        }

        let currentByID = Dictionary(uniqueKeysWithValues: currentResults.map { ($0.college.id, $0) })
        guard Set(stepIDs) == Set(currentByID.keys) else {
            return false
        }

        var validatedSteps: [RecommendationStep] = []
        var tierCounts: [String: Int] = [:]

        for step in steps {
            guard let current = currentByID[step.result.college.id] else {
                return false
            }

            guard approximatelyEqual(current.baseRate, step.result.baseRate),
                  approximatelyEqual(current.adjustedProbability, step.result.adjustedProbability),
                  current.confidence == step.result.confidence,
                  current.bucket == step.result.bucket,
                  current.gateResult.passed == step.result.gateResult.passed else {
                return false
            }

            let expectedRankScore = recommendationRankScore(for: current.college)
            let expectedConfidenceMultiplier = recommendationConfidenceMultiplier(for: current)
            let expectedBaseExpectedValue = recommendationExpectedValue(for: current)
            let tierName = correlationTierName(for: current.college)
            let tierCount = tierCounts[tierName, default: 0]
            let expectedSameTierDiscount = sameTierCorrelationDiscount(
                for: tierName,
                previousSelectionsInTier: tierCount
            )

            let stepWithoutMarginal = RecommendationStep(
                order: step.order,
                result: current,
                rankScore: expectedRankScore,
                confidenceMultiplier: expectedConfidenceMultiplier,
                baseExpectedValue: expectedBaseExpectedValue,
                sameTierDiscount: expectedSameTierDiscount,
                marginalExpectedValue: 0
            )
            let expectedMarginalExpectedValue = recommendationBestOfferExpectedValue(for: validatedSteps + [stepWithoutMarginal]) -
                recommendationBestOfferExpectedValue(for: validatedSteps)

            guard approximatelyEqual(step.rankScore, expectedRankScore),
                  approximatelyEqual(step.confidenceMultiplier, expectedConfidenceMultiplier),
                  approximatelyEqual(step.baseExpectedValue, expectedBaseExpectedValue),
                  approximatelyEqual(step.sameTierDiscount, expectedSameTierDiscount),
                  approximatelyEqual(step.marginalExpectedValue, expectedMarginalExpectedValue) else {
                return false
            }

            validatedSteps.append(RecommendationStep(
                order: step.order,
                result: current,
                rankScore: expectedRankScore,
                confidenceMultiplier: expectedConfidenceMultiplier,
                baseExpectedValue: expectedBaseExpectedValue,
                sameTierDiscount: expectedSameTierDiscount,
                marginalExpectedValue: expectedMarginalExpectedValue
            ))
            tierCounts[tierName, default: 0] = tierCount + 1
        }

        return true
    }

    private func recommendationSteps(_ supplied: [RecommendationStep], matchRegenerated regenerated: [RecommendationStep]) -> Bool {
        guard supplied.count == regenerated.count else {
            return false
        }

        for (lhs, rhs) in zip(supplied, regenerated) {
            guard lhs.order == rhs.order,
                  lhs.result.college.id == rhs.result.college.id,
                  approximatelyEqual(lhs.result.baseRate, rhs.result.baseRate),
                  approximatelyEqual(lhs.result.adjustedProbability, rhs.result.adjustedProbability),
                  lhs.result.confidence == rhs.result.confidence,
                  lhs.result.bucket == rhs.result.bucket,
                  lhs.result.gateResult.passed == rhs.result.gateResult.passed,
                  approximatelyEqual(lhs.rankScore, rhs.rankScore),
                  approximatelyEqual(lhs.confidenceMultiplier, rhs.confidenceMultiplier),
                  approximatelyEqual(lhs.baseExpectedValue, rhs.baseExpectedValue),
                  approximatelyEqual(lhs.sameTierDiscount, rhs.sameTierDiscount),
                  approximatelyEqual(lhs.marginalExpectedValue, rhs.marginalExpectedValue) else {
                return false
            }
        }
        return true
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0000001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    func chance(for college: College, profile: StudentProfile, profileScore: Double? = nil) -> ChanceResult {
        let score = profileScore ?? studentScore(profile, college: college)
        let gate = gateResult(for: college, profile: profile)
        let baseRate = college.latestAvailableRate
        let baseFactor = ChanceFactor(
            label: "学校基础率",
            value: baseRate,
            detail: "\(college.category.rawValue) 最新可用基础录取率；数据槽 \(college.latestAvailableClassYear)，来源备注：\(college.sourceNote)。"
        )

        guard gate.passed else {
            let warnings = gate.failedRules.map { "未满足\($0.isOfficial ? "官方" : "推断")硬门槛：\($0.title)（\($0.detail)）" }
            return ChanceResult(
                college: college,
                baseRate: baseRate,
                adjustedProbability: 0,
                confidence: .low,
                bucket: .blocked,
                factors: [baseFactor],
                warnings: warnings,
                gateResult: gate
            )
        }

        let schoolContext = highSchoolContext(for: profile)
        let internationalSignal = internationalSignal(for: college)
        let chinaSignal = chinaAdmissionSignal(for: college)
        let benchmark = academicBenchmark(for: college)
        let ordinaryPrior = ordinaryApplicantPrior(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)
        let readinessDelta = (score - 72) * 0.047
        let academicBenchmarkDelta = academicBenchmarkAdjustment(profile: profile, college: college, benchmark: benchmark)
        let highSchoolDelta = schoolContext.calibration
        let topCohortDelta = topCohortAdjustment(profile: profile, schoolContext: schoolContext, college: college)
        let majorDelta = majorAdjustment(profile.major)
        let roundDelta = roundAdjustment(profile.round, college: college)
        let aidDelta = aidAdjustment(profile: profile, signal: internationalSignal)
        let internationalDelta = internationalAdjustment(profile: profile, signal: internationalSignal)
        let chinaAdmissionDelta = chinaAdmissionAdjustment(profile: profile, signal: chinaSignal)
        let logitPrior = logit(clamp(ordinaryPrior, min: 0.001, max: 0.72))
        let adjustedLogit = logitPrior + readinessDelta + academicBenchmarkDelta + highSchoolDelta + topCohortDelta + majorDelta + roundDelta + aidDelta + internationalDelta + chinaAdmissionDelta
        let probability = clamp(logistic(adjustedLogit), min: 0.001, max: probabilityCap(for: college, profile: profile, chinaSignal: chinaSignal))

        let factors = [
            baseFactor,
            ChanceFactor(label: "普通申请池先验", value: ordinaryPrior, detail: ordinaryPriorDetail(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)),
            ChanceFactor(label: "学生画像", value: readinessDelta, detail: readinessDetail(score: score, college: college)),
            ChanceFactor(label: "目标校学术匹配", value: academicBenchmarkDelta, detail: academicBenchmarkDetail(profile: profile, college: college, benchmark: benchmark)),
            ChanceFactor(label: "高中背景", value: highSchoolDelta, detail: highSchoolDetail(schoolContext)),
            ChanceFactor(label: "顶尖高中强队列", value: topCohortDelta, detail: topCohortDetail(profile: profile, schoolContext: schoolContext, college: college)),
            ChanceFactor(label: "专业竞争", value: majorDelta, detail: "\(profile.major.rawValue) 的竞争强度修正。"),
            ChanceFactor(label: "申请身份", value: internationalDelta, detail: internationalDetail(profile: profile, signal: internationalSignal)),
            ChanceFactor(label: "中国录取信号", value: chinaAdmissionDelta, detail: chinaAdmissionDetail(profile: profile, signal: chinaSignal)),
            ChanceFactor(label: "申请轮次", value: roundDelta, detail: roundDetail(profile.round, college: college)),
            ChanceFactor(label: "资助需求", value: aidDelta, detail: aidDetail(profile: profile, signal: internationalSignal))
        ]

        let warnings = warnings(for: college, profile: profile, gate: gate, internationalSignal: internationalSignal, chinaSignal: chinaSignal, benchmark: benchmark)
        return ChanceResult(
            college: college,
            baseRate: baseRate,
            adjustedProbability: probability,
            confidence: confidence(college: college, profile: profile, gate: gate, internationalSignal: internationalSignal, chinaSignal: chinaSignal, benchmark: benchmark),
            bucket: bucket(probability),
            factors: factors,
            warnings: warnings,
            gateResult: gate
        )
    }

    func gateResult(for college: College, profile: StudentProfile) -> GateResult {
        let applicable = gateRules.filter { $0.collegeID == college.id || $0.collegeID == "*" }
        var failed: [CollegeGateRule] = []
        var inferred: [CollegeGateRule] = []

        for rule in applicable {
            guard ruleApplies(rule, to: profile) else {
                continue
            }

            if !rule.isOfficial {
                inferred.append(rule)
            }

            switch rule.type {
            case .standardizedTest:
                if let minimumSAT = rule.minimumSAT {
                    let satEquivalent = bestSATEquivalent(profile)
                    if profile.testOptional || (satEquivalent ?? 0) < minimumSAT {
                        failed.append(rule)
                    }
                }
            case .english:
                if profile.applicantStatus.requiresEnglishProof, let minimumTOEFL = rule.minimumTOEFL, !meetsEnglishRequirement(profile, minimumTOEFL: minimumTOEFL) {
                    failed.append(rule)
                }
            case .curriculum:
                if let minimum = rule.minimumStrengthBand, profile.rigor < minimum {
                    failed.append(rule)
                }
            case .portfolio:
                if !profile.hasPortfolio {
                    failed.append(rule)
                }
            case .round:
                if let required = rule.requiredRound, required != profile.round {
                    failed.append(rule)
                }
                if !rule.allowedRounds.isEmpty, !rule.allowedRounds.contains(profile.round) {
                    failed.append(rule)
                }
            }
        }

        if isUCCampus(college),
           profile.round != .regularDecision,
           !failed.contains(where: { $0.type == .round && $0.collegeID == college.id }) {
            failed.append(Self.ucSingleFilingPeriodRule(collegeID: college.id))
        }

        let inferredPenalty = Double(inferred.count) * -0.025
        let missingOfficialPenalty = applicable.contains(where: { $0.isOfficial }) ? 0 : -0.05
        return GateResult(
            passed: failed.isEmpty,
            failedRules: failed,
            inferredRules: inferred,
            confidenceImpact: inferredPenalty + missingOfficialPenalty
        )
    }

    private func ruleApplies(_ rule: CollegeGateRule, to profile: StudentProfile) -> Bool {
        if let affectedMajor = rule.affectedMajor, affectedMajor != profile.major {
            return false
        }

        switch rule.type {
        case .english:
            return profile.applicantStatus.requiresEnglishProof
        case .curriculum:
            return rule.affectedMajor != nil || profile.major.isSTEM
        case .portfolio:
            return rule.affectedMajor != nil || profile.major == .arts
        case .standardizedTest, .round:
            return true
        }
    }

    func studentScore(_ profile: StudentProfile, college: College? = nil) -> Double {
        let gpa = normalizedGPAScore(profile)
        let rank = clamp(100 - profile.classRankPercentile, min: 0, max: 100)
        let rigor = band(profile.rigor)
        let curriculumPerformance = curriculumPerformanceIndex(profile)
        let testing = testingScore(profile, college: college)
        let activities = band(profile.activities)
        let research = band(profile.research)
        let honors = band(profile.honors)
        let essay = band(profile.essay)
        let recs = band(profile.recommendations)
        let school = highSchoolContext(for: profile)
        let schoolScore = Double(school.resources + school.counseling + school.top30TrackRecord + school.transparency) / 20 * 100

        let weights = studentScoreWeights(for: profile.major)
        let portfolioBonus = profile.major == .arts && profile.hasPortfolio ? 4.0 : 0
        let total =
            gpa * weights.gpa +
            rank * weights.rank +
            rigor * weights.rigor +
            curriculumPerformance * weights.curriculumPerformance +
            testing * weights.testing +
            schoolScore * weights.school +
            activities * weights.activities +
            research * weights.research +
            honors * weights.honors +
            essay * weights.essay +
            recs * weights.recommendations +
            portfolioBonus
        return clamp(total, min: 0, max: 100)
    }

    func recommendedColleges(for profile: StudentProfile, count: Int) -> [College] {
        let requested = effectiveRequestedSchoolCount(for: profile, requested: count)
        guard requested > 0 else {
            return []
        }

        return recommendationSteps(for: profile, count: requested).map(\.result.college)
    }

    func recommendationSteps(for profile: StudentProfile, count: Int) -> [RecommendationStep] {
        let requested = effectiveRequestedSchoolCount(for: profile, requested: count)
        guard requested > 0 else {
            return []
        }

        let eligible = colleges
            .filter { isSelectable($0, for: profile) }
            .map { chance(for: $0, profile: profile) }
            .filter { $0.gateResult.passed }

        return recommendationSteps(for: eligible, count: requested)
    }

    func recommendationSteps(for eligibleResults: [ChanceResult], count: Int) -> [RecommendationStep] {
        let requested = max(0, count)
        guard requested > 0 else {
            return []
        }

        let eligible = eligibleResults.filter { $0.gateResult.passed }
        if let exact = exactRecommendationSteps(from: eligible, count: requested) {
            return exact
        }
        let initial = greedyRecommendationSteps(from: eligible, count: requested)
        return locallyOptimizedRecommendationSteps(from: eligible, initial: initial)
    }

    private func exactRecommendationSteps(from eligible: [ChanceResult], count: Int) -> [RecommendationStep]? {
        let requested = min(max(0, count), eligible.count)
        guard requested > 0 else {
            return []
        }
        guard requested <= Self.exactRecommendationRequestedLimit else {
            return nil
        }
        guard combinationCount(eligible.count, choose: requested, limit: Self.exactRecommendationCombinationLimit) != nil else {
            return nil
        }

        let sortedEligible = eligible.sorted { lhs, rhs in
            let lhsValue = recommendationExpectedValue(for: lhs)
            let rhsValue = recommendationExpectedValue(for: rhs)
            if lhsValue == rhsValue {
                if lhs.college.rank == rhs.college.rank {
                    return lhs.college.name < rhs.college.name
                }
                return lhs.college.rank < rhs.college.rank
            }
            return lhsValue > rhsValue
        }

        var bestSteps: [RecommendationStep] = []
        var bestValue = -Double.infinity
        var current: [ChanceResult] = []

        func search(startIndex: Int) {
            if current.count == requested {
                let steps = bestOrderingCandidateSteps(
                    from: current,
                    includeMarginalValues: true,
                    includeMarginalOrder: true
                )
                let value = recommendationBestOfferExpectedValue(for: steps)
                if value > bestValue + 0.0001 {
                    bestSteps = steps
                    bestValue = value
                }
                return
            }

            let remainingSlots = requested - current.count
            guard sortedEligible.count - startIndex >= remainingSlots else {
                return
            }

            let lastStart = sortedEligible.count - remainingSlots
            guard startIndex <= lastStart else {
                return
            }

            for index in startIndex...lastStart {
                current.append(sortedEligible[index])
                search(startIndex: index + 1)
                current.removeLast()
            }
        }

        search(startIndex: 0)
        return bestSteps
    }

    private func combinationCount(_ n: Int, choose k: Int, limit: Int) -> Int? {
        guard k >= 0, k <= n else {
            return nil
        }
        let k = min(k, n - k)
        guard k > 0 else {
            return 1
        }

        var result = 1
        for divisor in 1...k {
            let multiplier = n - k + divisor
            result = result * multiplier / divisor
            if result > limit {
                return nil
            }
        }
        return result
    }

    private func greedyRecommendationSteps(from eligible: [ChanceResult], count: Int) -> [RecommendationStep] {
        var steps: [RecommendationStep] = []
        var pickedIDs = Set<String>()

        while steps.count < count {
            let remaining = recommendationCandidateWindow(
                from: eligible,
                excluding: pickedIDs,
                primaryLimit: Self.recommendationGreedyCandidateLimit
            )
            let currentExpectedValue = recommendationBestOfferExpectedValue(for: steps)
            guard let next = remaining.max(by: { lhs, rhs in
                let lhsValue = marginalRecommendationExpectedValue(
                    for: lhs,
                    selectedSteps: steps,
                    currentExpectedValue: currentExpectedValue
                )
                let rhsValue = marginalRecommendationExpectedValue(
                    for: rhs,
                    selectedSteps: steps,
                    currentExpectedValue: currentExpectedValue
                )
                if lhsValue == rhsValue {
                    if lhs.college.rank == rhs.college.rank {
                        return lhs.college.name > rhs.college.name
                    }
                    return lhs.college.rank > rhs.college.rank
                }
                return lhsValue < rhsValue
            }) else {
                break
            }

            let rankScore = recommendationRankScore(for: next.college)
            let baseExpectedValue = recommendationExpectedValue(for: next)
            let confidenceMultiplier = recommendationConfidenceMultiplier(for: next)
            let tierName = correlationTierName(for: next.college)
            let tierCount = steps.filter { correlationTierName(for: $0.result.college) == tierName }.count
            let discount = sameTierCorrelationDiscount(for: tierName, previousSelectionsInTier: tierCount)
            let marginalExpectedValue = marginalRecommendationExpectedValue(
                for: next,
                selectedSteps: steps,
                currentExpectedValue: currentExpectedValue
            )
            steps.append(RecommendationStep(
                order: steps.count + 1,
                result: next,
                rankScore: rankScore,
                confidenceMultiplier: confidenceMultiplier,
                baseExpectedValue: baseExpectedValue,
                sameTierDiscount: discount,
                marginalExpectedValue: marginalExpectedValue
            ))
            pickedIDs.insert(next.college.id)
        }
        return steps
    }

    private func locallyOptimizedRecommendationSteps(from eligible: [ChanceResult], initial: [RecommendationStep]) -> [RecommendationStep] {
        guard initial.count > 1, initial.count < eligible.count else {
            return bestOrderedRecommendationSteps(initial)
        }

        var bestSteps = initial
        var bestValue = recommendationBestOfferExpectedValue(for: bestSteps)

        var replacementPasses = 0
        while replacementPasses < Self.recommendationReplacementPassLimit {
            let selectedResults = bestSteps.map(\.result)
            let selectedIDs = Set(selectedResults.map { $0.college.id })
            let removalIndices = bestSteps
                .enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.marginalExpectedValue == rhs.element.marginalExpectedValue {
                        let lhsValue = recommendationReplacementPrefilterValue(for: lhs.element.result)
                        let rhsValue = recommendationReplacementPrefilterValue(for: rhs.element.result)
                        if lhsValue == rhsValue {
                            return lhs.element.result.college.rank > rhs.element.result.college.rank
                        }
                        return lhsValue < rhsValue
                    }
                    return lhs.element.marginalExpectedValue < rhs.element.marginalExpectedValue
                }
                .prefix(Self.recommendationReplacementRemovalLimit)
                .map(\.offset)
            let candidateResults = recommendationCandidateWindow(
                from: eligible,
                excluding: selectedIDs,
                primaryLimit: Self.recommendationReplacementCandidateLimit
            )

            var nextBestSteps = bestSteps
            var nextBestValue = bestValue
            for removedIndex in removalIndices {
                for candidate in candidateResults {
                    var trialResults = selectedResults
                    trialResults[removedIndex] = candidate
                    let trialSteps = bestOrderingCandidateSteps(
                        from: trialResults,
                        includeMarginalValues: false,
                        includeMarginalOrder: false
                    )
                    let trialValue = recommendationBestOfferExpectedValue(for: trialSteps)
                    if trialValue > nextBestValue + 0.0001 {
                        nextBestSteps = bestOrderingCandidateSteps(
                            from: trialResults,
                            includeMarginalValues: true,
                            includeMarginalOrder: false
                        )
                        nextBestValue = trialValue
                    }
                }
            }

            if nextBestValue > bestValue + 0.0001 {
                bestSteps = nextBestSteps
                bestValue = nextBestValue
                replacementPasses += 1
                continue
            }

            break
        }

        return bestOrderedRecommendationSteps(bestSteps)
    }

    private func recommendationCandidateWindow(
        from eligible: [ChanceResult],
        excluding excludedIDs: Set<String>,
        primaryLimit: Int
    ) -> [ChanceResult] {
        let remaining = eligible.filter { !excludedIDs.contains($0.college.id) }
        guard !remaining.isEmpty else {
            return []
        }

        var seenIDs = Set<String>()
        var candidates: [ChanceResult] = []
        func appendUnique<S: Sequence>(_ sequence: S) where S.Element == ChanceResult {
            for result in sequence where !seenIDs.contains(result.college.id) {
                candidates.append(result)
                seenIDs.insert(result.college.id)
            }
        }

        appendUnique(recommendationPrefilterSorted(remaining).prefix(primaryLimit))
        appendUnique(recommendationRankPrioritySorted(remaining).prefix(Self.recommendationRankPriorityCandidateLimit))
        appendUnique(recommendationProbabilitySorted(remaining).prefix(Self.recommendationProbabilityCandidateLimit))
        return candidates
    }

    private func recommendationPrefilterSorted(_ results: [ChanceResult]) -> [ChanceResult] {
        results.sorted { lhs, rhs in
            let lhsValue = recommendationReplacementPrefilterValue(for: lhs)
            let rhsValue = recommendationReplacementPrefilterValue(for: rhs)
            if approximatelyEqual(lhsValue, rhsValue) {
                if lhs.college.rank == rhs.college.rank {
                    return lhs.college.name < rhs.college.name
                }
                return lhs.college.rank < rhs.college.rank
            }
            return lhsValue > rhsValue
        }
    }

    private func recommendationRankPrioritySorted(_ results: [ChanceResult]) -> [ChanceResult] {
        results.sorted { lhs, rhs in
            let lhsRankScore = recommendationRankScore(for: lhs.college)
            let rhsRankScore = recommendationRankScore(for: rhs.college)
            if approximatelyEqual(lhsRankScore, rhsRankScore) {
                let lhsValue = recommendationReplacementPrefilterValue(for: lhs)
                let rhsValue = recommendationReplacementPrefilterValue(for: rhs)
                if approximatelyEqual(lhsValue, rhsValue) {
                    if lhs.college.rank == rhs.college.rank {
                        return lhs.college.name < rhs.college.name
                    }
                    return lhs.college.rank < rhs.college.rank
                }
                return lhsValue > rhsValue
            }
            return lhsRankScore > rhsRankScore
        }
    }

    private func recommendationProbabilitySorted(_ results: [ChanceResult]) -> [ChanceResult] {
        results.sorted { lhs, rhs in
            if approximatelyEqual(lhs.adjustedProbability, rhs.adjustedProbability) {
                let lhsValue = recommendationReplacementPrefilterValue(for: lhs)
                let rhsValue = recommendationReplacementPrefilterValue(for: rhs)
                if approximatelyEqual(lhsValue, rhsValue) {
                    if lhs.college.rank == rhs.college.rank {
                        return lhs.college.name < rhs.college.name
                    }
                    return lhs.college.rank < rhs.college.rank
                }
                return lhsValue > rhsValue
            }
            return lhs.adjustedProbability > rhs.adjustedProbability
        }
    }

    private func bestOrderedRecommendationSteps(_ steps: [RecommendationStep]) -> [RecommendationStep] {
        guard steps.count > 1 else {
            return steps
        }

        let marginalOrder = greedyRecommendationSteps(from: steps.map(\.result), count: steps.count)
        let rankValueOrder = rankValuePriorityRecommendationSteps(from: steps.map(\.result), includeMarginalValues: true)

        let stepsValue = recommendationBestOfferExpectedValue(for: steps)
        let marginalOrderValue = recommendationBestOfferExpectedValue(for: marginalOrder)
        let currentBest = stepsValue > marginalOrderValue + 0.0001 ? steps : marginalOrder
        let currentBestValue = max(stepsValue, marginalOrderValue)
        let rankValueOrderValue = recommendationBestOfferExpectedValue(for: rankValueOrder)

        return rankValueOrderValue > currentBestValue + 0.0001 ? rankValueOrder : currentBest
    }

    private func bestOrderingCandidateSteps(from results: [ChanceResult], includeMarginalValues: Bool, includeMarginalOrder: Bool) -> [RecommendationStep] {
        let currentOrder = recommendationStepsInCurrentOrder(from: results, includeMarginalValues: false)
        let rankValueOrder = rankValuePriorityRecommendationSteps(from: results, includeMarginalValues: false)
        var chosenOrder = recommendationBestOfferExpectedValue(for: rankValueOrder) > recommendationBestOfferExpectedValue(for: currentOrder) + 0.0001
            ? rankValueOrder
            : currentOrder

        if includeMarginalOrder {
            let marginalOrder = greedyRecommendationSteps(from: results, count: results.count)
            if recommendationBestOfferExpectedValue(for: marginalOrder) > recommendationBestOfferExpectedValue(for: chosenOrder) + 0.0001 {
                chosenOrder = marginalOrder
            }
        }

        let chosenResults = chosenOrder.map(\.result)
        return recommendationStepsInCurrentOrder(from: chosenResults, includeMarginalValues: includeMarginalValues)
    }

    private func rankValuePriorityRecommendationSteps(from results: [ChanceResult], includeMarginalValues: Bool) -> [RecommendationStep] {
        let ordered = results.sorted { lhs, rhs in
            let lhsRankScore = recommendationRankScore(for: lhs.college)
            let rhsRankScore = recommendationRankScore(for: rhs.college)
            if approximatelyEqual(lhsRankScore, rhsRankScore) {
                if approximatelyEqual(lhs.adjustedProbability, rhs.adjustedProbability) {
                    if lhs.college.rank == rhs.college.rank {
                        return lhs.college.name < rhs.college.name
                    }
                    return lhs.college.rank < rhs.college.rank
                }
                return lhs.adjustedProbability > rhs.adjustedProbability
            }
            return lhsRankScore > rhsRankScore
        }
        return recommendationStepsInCurrentOrder(from: ordered, includeMarginalValues: includeMarginalValues)
    }

    private func recommendationStepsInCurrentOrder(from orderedResults: [ChanceResult], includeMarginalValues: Bool) -> [RecommendationStep] {
        var steps: [RecommendationStep] = []
        var tierCounts: [String: Int] = [:]

        for result in orderedResults {
            let tierName = correlationTierName(for: result.college)
            let tierCount = tierCounts[tierName, default: 0]
            let stepWithoutMarginal = RecommendationStep(
                order: steps.count + 1,
                result: result,
                rankScore: recommendationRankScore(for: result.college),
                confidenceMultiplier: recommendationConfidenceMultiplier(for: result),
                baseExpectedValue: recommendationExpectedValue(for: result),
                sameTierDiscount: sameTierCorrelationDiscount(for: tierName, previousSelectionsInTier: tierCount),
                marginalExpectedValue: 0
            )
            let marginalExpectedValue = includeMarginalValues
                ? recommendationBestOfferExpectedValue(for: steps + [stepWithoutMarginal]) - recommendationBestOfferExpectedValue(for: steps)
                : 0
            steps.append(RecommendationStep(
                order: stepWithoutMarginal.order,
                result: result,
                rankScore: stepWithoutMarginal.rankScore,
                confidenceMultiplier: stepWithoutMarginal.confidenceMultiplier,
                baseExpectedValue: stepWithoutMarginal.baseExpectedValue,
                sameTierDiscount: stepWithoutMarginal.sameTierDiscount,
                marginalExpectedValue: marginalExpectedValue
            ))
            tierCounts[tierName, default: 0] = tierCount + 1
        }

        return steps
    }

    func recommendationRankScore(for college: College) -> Double {
        switch college.category {
        case .liberalArtsCollege:
            return liberalArtsRecommendationRankScore(for: college.rank)
        case .nationalUniversity:
            return nationalUniversityRecommendationRankScore(for: college.rank)
        }
    }

    private func nationalUniversityRecommendationRankScore(for rank: Int) -> Double {
        switch rank {
        case ...1:
            return 100
        case 2...10:
            return interpolateRankScore(rank: rank, lowerRank: 1, upperRank: 10, lowerScore: 100, upperScore: 90)
        case 11...20:
            return interpolateRankScore(rank: rank, lowerRank: 10, upperRank: 20, lowerScore: 90, upperScore: 78)
        case 21...30:
            return interpolateRankScore(rank: rank, lowerRank: 20, upperRank: 30, lowerScore: 78, upperScore: 68)
        case 31...50:
            return interpolateRankScore(rank: rank, lowerRank: 30, upperRank: 50, lowerScore: 68, upperScore: 50)
        default:
            return clamp(50 - Double(rank - 50) * 0.45, min: 40, max: 50)
        }
    }

    private func liberalArtsRecommendationRankScore(for rank: Int) -> Double {
        switch rank {
        case ...1:
            return 78
        case 2...10:
            return interpolateRankScore(rank: rank, lowerRank: 1, upperRank: 10, lowerScore: 78, upperScore: 68)
        case 11...20:
            return interpolateRankScore(rank: rank, lowerRank: 10, upperRank: 20, lowerScore: 68, upperScore: 58)
        case 21...30:
            return interpolateRankScore(rank: rank, lowerRank: 20, upperRank: 30, lowerScore: 58, upperScore: 50)
        default:
            return clamp(50 - Double(rank - 30) * 0.35, min: 40, max: 50)
        }
    }

    func recommendationExpectedValue(for result: ChanceResult) -> Double {
        result.adjustedProbability * recommendationRankScore(for: result.college)
    }

    private func recommendationReplacementPrefilterValue(for result: ChanceResult) -> Double {
        recommendationExpectedValue(for: result)
    }

    func recommendationConfidenceMultiplier(for result: ChanceResult) -> Double {
        1.0
    }

    func recommendationBestOfferExpectedValue(for steps: [RecommendationStep]) -> Double {
        var failureOfHigherValueOffers = 1.0
        var expectedValue = 0.0
        let sorted = steps.sorted {
            if $0.rankScore == $1.rankScore {
                if $0.result.adjustedProbability == $1.result.adjustedProbability {
                    return $0.result.college.rank < $1.result.college.rank
                }
                return $0.result.adjustedProbability > $1.result.adjustedProbability
            }
            return $0.rankScore > $1.rankScore
        }

        for step in sorted {
            let effectiveProbability = clamp(
                step.result.adjustedProbability * step.sameTierDiscount * step.confidenceMultiplier,
                min: 0,
                max: 0.98
            )
            expectedValue += failureOfHigherValueOffers * effectiveProbability * step.rankScore
            failureOfHigherValueOffers *= (1 - effectiveProbability)
        }
        return expectedValue
    }

    func atLeastOneProbability(_ results: [ChanceResult]) -> Double {
        let grouped = Dictionary(grouping: results.filter { $0.adjustedProbability > 0 }) { correlationTierName(for: $0.college) }
        var failure = 1.0
        for (tierName, probabilities) in grouped {
            let decay = sameTierCorrelationDecay(for: tierName)
            let sorted = probabilities.map(\.adjustedProbability).sorted(by: >)
            for (index, probability) in sorted.enumerated() {
                let effective = probability * pow(decay, Double(index))
                failure *= (1 - effective)
            }
        }
        return clamp(1 - failure, min: 0, max: 0.98)
    }

    private func bucketCounts(for results: [ChanceResult]) -> PortfolioBucketCounts {
        PortfolioBucketCounts(
            likely: results.filter { $0.bucket == .likely }.count,
            target: results.filter { $0.bucket == .target }.count,
            reach: results.filter { $0.bucket == .reach }.count,
            blocked: results.filter { $0.bucket == .blocked }.count
        )
    }

    private func selectionWarnings(profile: StudentProfile, requestedIDs: Set<String>) -> [String] {
        let requestedKnownColleges = colleges.filter { requestedIDs.contains($0.id) }
        let excludedLiberalArtsCount = requestedKnownColleges.filter { !profile.includeLiberalArtsColleges && $0.category == .liberalArtsCollege }.count
        let excludedRoundCount = requestedKnownColleges.filter { !allowsRound($0, profile.round) }.count
        let selectedEDCount = requestedKnownColleges.filter { isSelectable($0, for: profile) }.count
        let knownIDs = Set(requestedKnownColleges.map(\.id))
        let unknownCount = requestedIDs.subtracting(knownIDs).count
        var items: [String] = []
        if profile.round == .earlyDecision && selectedEDCount > 1 {
            items.append("ED/ED2 为绑定申请，同一轮最多选择 1 所 ED 学校；请保留 1 所 ED 学校，或切换到 EA/RD 后再计算组合概率。")
        }
        if unknownCount > 0 {
            items.append("选校列表包含 \(unknownCount) 个不在已审核 v1 数据集内的学校，已从概率计算中排除。")
        }
        if excludedLiberalArtsCount > 0 {
            items.append("已关闭文理学院选项，\(excludedLiberalArtsCount) 所文理学院已从概率计算和至少一所概率中排除。")
        }
        if excludedRoundCount > 0 {
            items.append("\(excludedRoundCount) 所学校未开放 \(profile.round.rawValue) 轮次，已从本轮概率计算中排除。")
        }
        return items
    }

    private func recommendationWarnings(profile: StudentProfile, recommendedResults: [ChanceResult]) -> [String] {
        var items: [String] = []
        let effectiveRequested = effectiveRequestedSchoolCount(for: profile)
        if profile.round == .earlyDecision && profile.requestedSchoolCount > effectiveRequested {
            items.append("ED/ED2 为绑定申请，同一轮最多选择 1 所 ED 学校；自动推荐已按 1 所生成。")
        }
        if recommendedResults.count < effectiveRequested {
            items.append("自动推荐数量不足：计划 \(effectiveRequested) 所，当前生成 \(recommendedResults.count) 所。")
        }
        return items
    }

    private func marginalRecommendationExpectedValue(for result: ChanceResult, selectedSteps: [RecommendationStep]) -> Double {
        marginalRecommendationExpectedValue(
            for: result,
            selectedSteps: selectedSteps,
            currentExpectedValue: recommendationBestOfferExpectedValue(for: selectedSteps)
        )
    }

    private func marginalRecommendationExpectedValue(
        for result: ChanceResult,
        selectedSteps: [RecommendationStep],
        currentExpectedValue: Double
    ) -> Double {
        let tierName = correlationTierName(for: result.college)
        let tierCount = selectedSteps.filter { correlationTierName(for: $0.result.college) == tierName }.count
        let correlationDiscount = sameTierCorrelationDiscount(for: tierName, previousSelectionsInTier: tierCount)
        let tentativeStep = RecommendationStep(
            order: selectedSteps.count + 1,
            result: result,
            rankScore: recommendationRankScore(for: result.college),
            confidenceMultiplier: recommendationConfidenceMultiplier(for: result),
            baseExpectedValue: recommendationExpectedValue(for: result),
            sameTierDiscount: correlationDiscount,
            marginalExpectedValue: 0
        )
        return recommendationBestOfferExpectedValue(for: selectedSteps + [tentativeStep]) - currentExpectedValue
    }

    private func interpolateRankScore(rank: Int, lowerRank: Int, upperRank: Int, lowerScore: Double, upperScore: Double) -> Double {
        let span = Double(upperRank - lowerRank)
        guard span > 0 else {
            return lowerScore
        }
        let progress = Double(rank - lowerRank) / span
        return clamp(lowerScore + (upperScore - lowerScore) * progress, min: min(lowerScore, upperScore), max: max(lowerScore, upperScore))
    }

    private func sameTierCorrelationDecay(for tierName: String) -> Double {
        if tierName.contains("T10") {
            return 0.78
        }
        if tierName.contains("T30") {
            return tierName.contains(CollegeCategory.liberalArtsCollege.rawValue) ? 0.90 : 0.93
        }
        if tierName.contains("T50") {
            return 0.90
        }
        return 0.94
    }

    private func correlationTierName(for college: College) -> String {
        if college.rank <= 10 {
            return "T10"
        }
        return college.tierName
    }

    private func sameTierCorrelationDiscount(for tierName: String, previousSelectionsInTier: Int) -> Double {
        pow(sameTierCorrelationDecay(for: tierName), Double(previousSelectionsInTier))
    }

    private func selectableColleges(for profile: StudentProfile) -> [College] {
        colleges.filter { isSelectable($0, for: profile) }
    }

    private func isSelectable(_ college: College, for profile: StudentProfile) -> Bool {
        (profile.includeLiberalArtsColleges || college.category != .liberalArtsCollege) &&
            allowsRound(college, profile.round)
    }

    private func allowsRound(_ college: College, _ round: ApplicationRound) -> Bool {
        let rules = roundPolicyRules(for: college)
        guard !rules.isEmpty else {
            return round == .regularDecision
        }
        return rules.contains { rule in
            if !rule.allowedRounds.isEmpty {
                return rule.allowedRounds.contains(round)
            }
            if let requiredRound = rule.requiredRound {
                return requiredRound == round
            }
            return round == .regularDecision
        }
    }

    private func highSchoolContext(for profile: StudentProfile) -> HighSchoolContext {
        highSchools.first { $0.id == profile.highSchoolID } ??
            highSchools.first { $0.id == "unknown" } ??
            highSchools.last ??
            Self.conservativeHighSchoolFallback
    }

    private func warnings(for college: College, profile: StudentProfile, gate: GateResult, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal, benchmark: AcademicBenchmark) -> [String] {
        var items: [String] = []
        if college.acceptanceRates.contains(where: { $0.rate == nil }) {
            items.append("该校最新年份存在 N/A，已使用最近非空录取率。")
        }
        if benchmarkHasOfficialFields(benchmark), benchmark.isInferred {
            items.append("目标校学术基准含部分官方字段，其余缺失字段仍为推断值；不得视作完整官方录取均值。")
        } else if benchmark.isInferred {
            items.append("目标校学术基准为推断值，用于相对比较 GPA、排名、标化和课程难度；不是官方录取均值。")
        }
        if profile.gradeScale != .percent || (profile.curriculum == .chinese && profile.curriculumGradeScale != .percent) {
            items.append("绩点或等级制成绩已转换为内部学术指数；该指数用于相对比较，不等同于真实百分制成绩。")
        }
        if profile.testOptional && (profile.sat != nil || profile.act != nil), !isTestFreeForAdmissions(college) {
            items.append("已选择不提交标化，表单中的 SAT/ACT 分数未参与画像分或目标校学术匹配。")
        }
        if profile.highSchoolID == "unknown" {
            items.append("高中背景为其他/手动评估学校，当前使用保守代理校准；如有真实学校资源和升学记录，应单独复核。")
        }
        if profile.needsAid && profile.applicantStatus.isInternational {
            switch internationalSignal.internationalAidPolicy {
            case .needAware:
                items.append("该校国际生资助政策按 need-aware 处理，申请资助已作为负向策略修正。")
            case .limited:
                items.append("该校国际生资助资源有限，申请资助已作为较强负向策略修正。")
            case .unknown:
                items.append("该校国际生资助政策缺少明确口径，申请资助按保守负向策略修正。")
            case .needBlind:
                break
            }
        }
        if profile.round != .regularDecision && !isUCCampus(college) && !hasSchoolSpecificRoundPolicy(college) {
            items.append("该校缺少学校级 EA/ED 轮次政策数据，当前未给早申轮次加分；请以官方招生轮次为准。")
        }
        items.append(contentsOf: curriculumEvidenceWarnings(profile))
        if isTestFreeForAdmissions(college), profile.sat != nil || profile.act != nil || profile.testOptional {
            items.append("该 UC 校区为 test-free：SAT/ACT 不进入录取概率或奖学金判断；语言成绩、AP/IB/A-Level 等仍可作为门槛或课程表现信号。")
        }
        if profile.applicantStatus.isInternational {
            items.append("国际生数据仅使用本科口径；录取系数只有在本科国际生 admitted 数和总 admitted 数同时可用时才参与计算。")
            if internationalSignal.internationalAdmitCoefficient == nil {
                items.append("该校缺少本科国际生录取系数，当前使用本科 nonresident 占比作为弱代理。")
            }
        }
        if profile.applicantStatus.usesChinaProxy {
            items.append("中国籍国际生先验已从整体录取率下调到普通申请池估计，并扣除顶尖校 legacy、运动员、发展名单等特殊通道容量影响。")
            if chinaSignal.chinaShareOfAllAdmits == nil {
                items.append("中国学生录取数据缺少申请人数分母，当前作为容量约束和趋势信号，不作为精确中国录取率。")
            }
            if chinaSignal.total2030 == nil {
                items.append("该校缺少中国学生本科录取人数，未使用中国录取修正。")
            }
            if let roundCapacity = chinaCapacityCount(for: chinaSignal, college: college, round: profile.round), roundCapacity < 50 {
                items.append("该校当前申请轮次中国学生录取容量很小，最终概率已按小容量学校保守封顶。")
            }
        }
        return items
    }

    private func curriculumEvidenceWarnings(_ profile: StudentProfile) -> [String] {
        switch profile.curriculum {
        case .ap where profile.apCourseCount == 0:
            return ["AP 体系课程门数为 0，AP 平均分未作为课程体系成绩证据使用。"]
        case .alevel where profile.aLevelAStarCount + profile.aLevelACount + profile.aLevelBCount == 0:
            return ["A-Level 科目数为 0，课程体系成绩按缺少科目证据保守处理。"]
        case .alevel where profile.aLevelSubjectCount > StudentProfile.maximumALevelSubjectCount:
            return ["A-Level A*/A/B 科目合计超过 \(StudentProfile.maximumALevelSubjectCount) 门，课程体系成绩已按 A*、A、B 顺序截断至最多 \(StudentProfile.maximumALevelSubjectCount) 门。"]
        default:
            return []
        }
    }

    private func confidence(college: College, profile: StudentProfile, gate: GateResult, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal, benchmark: AcademicBenchmark) -> ConfidenceLabel {
        var score = 100.0
        score -= (1 - college.dataQuality) * 35
        score -= (1 - benchmark.dataQuality) * 14
        if profile.applicantStatus.isInternational {
            score -= (1 - internationalSignal.dataQuality) * 20
        }
        if profile.applicantStatus.usesChinaProxy {
            score -= (1 - chinaSignal.dataQuality) * 12
        }
        score += gate.confidenceImpact * 100
        if profile.testOptional && !isTestFreeForAdmissions(college) { score -= 10 }
        if profile.applicantStatus.requiresEnglishProof && profile.toefl == nil && profile.ielts == nil { score -= 8 }
        if profile.highSchoolID == "unknown" { score -= 10 }
        if score >= 78 { return .high }
        if score >= 58 { return .medium }
        return .low
    }

    private func readinessDetail(score: Double, college: College) -> String {
        if isTestFreeForAdmissions(college) {
            return "学术、课程、活动、奖项、文书与推荐信合成分：\(Int(score))/100；SAT/ACT 已按该校 test-free 政策从录取画像中排除。"
        }
        return "学术、课程、标化、活动、奖项、文书与推荐信合成分：\(Int(score))/100。"
    }

    private func highSchoolDetail(_ school: HighSchoolContext) -> String {
        if school.id == "unknown" {
            return "其他/手动评估学校使用保守代理校准；不会按顶尖国际化高中默认加分。"
        }
        return "\(school.name) 的资源、升学记录与透明度校准；这是 AdmitRanking 风格代理，不是个人录取证明。"
    }

    private func roundDetail(_ round: ApplicationRound, college: College) -> String {
        if isUCCampus(college) {
            return "UC 校区使用统一 first-year filing period；EA/ED 不作为有效轮次优势。"
        }
        if round != .regularDecision && !hasSchoolSpecificRoundPolicy(college) {
            return "该校缺少学校级 \(round.rawValue) 政策数据，当前不泛化早申加分；请以官方招生轮次为准。"
        }
        if round != .regularDecision, roundAdjustment(round, college: college) == 0 {
            return "该校有学校级 \(round.rawValue) 政策数据，但没有明确概率加分；学校官方轮次限制仍由硬门槛先检查。"
        }
        return "\(round.rawValue) 轮次策略修正；仅使用学校级明确轮次优势数据，学校官方轮次限制仍由硬门槛先检查。"
    }

    private func aidDetail(profile: StudentProfile, signal: InternationalSignal) -> String {
        guard profile.needsAid else {
            return "未申请资助，不进行资助需求修正。"
        }
        guard profile.applicantStatus.isInternational else {
            return "\(profile.applicantStatus.rawValue) 不使用国际生资助政策修正。"
        }

        switch signal.internationalAidPolicy {
        case .needBlind:
            return "该校国际生资助政策按 need-blind 处理，申请资助不降低概率。"
        case .needAware:
            return "该校国际生资助政策按 need-aware 处理，申请资助会降低录取机会估计。"
        case .limited:
            return "该校国际生资助资源有限，申请资助会较强降低录取机会估计。"
        case .unknown:
            return "该校国际生资助政策缺少明确口径，申请资助按保守负向修正。"
        }
    }

    private func testingScore(_ profile: StudentProfile, college: College? = nil) -> Double {
        if let college, isTestFreeForAdmissions(college) {
            return profile.applicantStatus.requiresEnglishProof ? englishScore(profile) : 72
        }
        if profile.testOptional {
            return 54
        }
        let satEquivalent = submittedSATEquivalent(profile) ?? 0
        let testScore = satEquivalent > 0 ? clamp((Double(satEquivalent) - 1050) / 550 * 100, min: 0, max: 100) : 0
        let english = englishScore(profile)
        return testScore * 0.72 + english * 0.28
    }

    private func englishScore(_ profile: StudentProfile) -> Double {
        if !profile.applicantStatus.requiresEnglishProof, profile.toefl == nil && profile.ielts == nil {
            return 72
        }
        if let toefl = profile.toefl {
            return clamp((Double(toefl) - 80) / 40 * 100, min: 0, max: 100)
        }
        if let ielts = profile.ielts {
            return clamp((ielts - 6.0) / 3.0 * 100, min: 0, max: 100)
        }
        return 52
    }

    private func meetsEnglishRequirement(_ profile: StudentProfile, minimumTOEFL: Int) -> Bool {
        guard profile.applicantStatus.requiresEnglishProof else {
            return true
        }
        if let toefl = profile.toefl {
            return toefl >= minimumTOEFL
        }
        if let ielts = profile.ielts {
            return ielts >= 6.5
        }
        return false
    }

    private func bestSATEquivalent(_ profile: StudentProfile) -> Int? {
        let submittedScores = [profile.sat, actToSat(profile.act)].compactMap { $0 }
        return submittedScores.max()
    }

    private func submittedSATEquivalent(_ profile: StudentProfile) -> Int? {
        profile.testOptional ? nil : bestSATEquivalent(profile)
    }

    private func actToSat(_ act: Int?) -> Int? {
        guard let act else { return nil }
        let concordance = [
            36: 1590, 35: 1540, 34: 1500, 33: 1460, 32: 1430, 31: 1400,
            30: 1370, 29: 1340, 28: 1310, 27: 1280, 26: 1240, 25: 1210,
            24: 1180, 23: 1140, 22: 1110, 21: 1080, 20: 1040, 19: 1010,
            18: 970, 17: 930, 16: 890, 15: 850, 14: 800, 13: 760,
            12: 710, 11: 670, 10: 630, 9: 590
        ]
        return concordance[act] ?? concordance[min(36, max(9, act))]
    }

    private static func ucSingleFilingPeriodRule(collegeID: String) -> CollegeGateRule {
        CollegeGateRule(
            id: "\(collegeID)_uc_regular_round",
            collegeID: collegeID,
            type: .round,
            title: "UC single filing period",
            detail: "University of California campuses use one first-year application filing period rather than EA or ED.",
            isOfficial: true,
            sourceURL: URL(string: "https://admission.universityofcalifornia.edu/how-to-apply/applying-as-a-freshman/dates-and-deadlines.html"),
            minimumSAT: nil,
            minimumTOEFL: nil,
            requiredRound: .regularDecision,
            allowedRounds: [.regularDecision],
            earlyActionAdjustment: nil,
            earlyDecisionAdjustment: nil,
            affectedMajor: nil,
            minimumStrengthBand: nil
        )
    }

    private func band(_ value: Int) -> Double {
        clamp(Double(value), min: 1, max: 5) * 20
    }

    private func majorAdjustment(_ major: MajorCategory) -> Double {
        switch major {
        case .undecided: return 0
        case .computerScience: return -0.26
        case .engineering: return -0.18
        case .business: return -0.12
        case .economics: return -0.08
        case .naturalScience: return -0.06
        case .socialScience: return 0
        case .humanities: return 0.05
        case .arts: return 0
        }
    }

    private func topCohortAdjustment(profile: StudentProfile, schoolContext: HighSchoolContext, college: College) -> Double {
        guard college.category == .nationalUniversity else {
            return 0
        }
        guard profile.applicantStatus.usesChinaProxy else {
            return 0
        }
        let scale = eliteHighSchoolCohortScale(profile: profile, schoolContext: schoolContext)
        guard scale > 0 else {
            return 0
        }

        let base: Double
        switch college.rank {
        case ...10:
            base = 0.05
        case 11...20:
            base = 1.00
        case 21...30:
            base = 1.08
        case 31...50:
            base = 0.72
        default:
            base = 0.24
        }
        return base * scale
    }

    private func topCohortDetail(profile: StudentProfile, schoolContext: HighSchoolContext, college: College) -> String {
        let scale = eliteHighSchoolCohortScale(profile: profile, schoolContext: schoolContext)
        guard college.category == .nationalUniversity, profile.applicantStatus.usesChinaProxy, scale > 0 else {
            return "未触发：只对中国籍国际生的一流高中强队列做保守校准。"
        }

        return "\(schoolContext.name) 属于一流国际学校代理样本，申请者校内排名前\(String(format: "%.0f", profile.classRankPercentile))%；对 \(college.tierDisplayName) 使用强队列校准，但仍受硬门槛、专业和资助约束。"
    }

    private func eliteHighSchoolCohortScale(profile: StudentProfile, schoolContext: HighSchoolContext) -> Double {
        guard schoolContext.admitRankingBand == 1 else {
            return 0
        }

        switch profile.classRankPercentile {
        case ...5:
            return 1.0
        case ...10:
            return 0.9
        case ...15:
            return 0.55
        case ...20:
            return 0.3
        default:
            return 0
        }
    }

    private func studentScoreWeights(for major: MajorCategory) -> StudentScoreWeights {
        if major == .arts {
            return StudentScoreWeights(
                gpa: 0.14,
                rank: 0.06,
                rigor: 0.06,
                curriculumPerformance: 0.08,
                testing: 0.06,
                school: 0.08,
                activities: 0.18,
                research: 0.05,
                honors: 0.13,
                essay: 0.10,
                recommendations: 0.08
            )
        }

        return StudentScoreWeights(
            gpa: 0.18,
            rank: 0.10,
            rigor: 0.10,
            curriculumPerformance: 0.08,
            testing: 0.11,
            school: 0.08,
            activities: 0.12,
            research: 0.07,
            honors: 0.08,
            essay: 0.04,
            recommendations: 0.04
        )
    }

    private func academicBenchmark(for college: College) -> AcademicBenchmark {
        academicBenchmarks.first(where: { $0.collegeID == college.id }) ?? AcademicBenchmark(
            collegeID: college.id,
            gpaPercentBenchmark: nil,
            classRankPercentileBenchmark: nil,
            satBenchmark: nil,
            actBenchmark: nil,
            rigorBenchmark: nil,
            isInferred: true,
            sourceFields: [],
            sourceURL: nil,
            sourceNote: "Missing academic benchmark row.",
            dataQuality: 0.25
        )
    }

    private func academicBenchmarkAdjustment(profile: StudentProfile, college: College, benchmark: AcademicBenchmark) -> Double {
        let gpaDelta = benchmark.gpaPercentBenchmark.map { target in
            clamp((normalizedGPAScore(profile) - target) / 10 * 0.16, min: -0.12, max: 0.12)
        } ?? 0

        let rankDelta = benchmark.classRankPercentileBenchmark.map { target in
            clamp((target - profile.classRankPercentile) / 20 * 0.12, min: -0.10, max: 0.10)
        } ?? 0

        let satEquivalent = submittedSATEquivalent(profile)
        let testDelta: Double
        if isTestFreeForAdmissions(college) {
            testDelta = 0
        } else if let satBenchmark = benchmark.satBenchmark, let satEquivalent {
            testDelta = clamp((Double(satEquivalent - satBenchmark)) / 200 * 0.14, min: -0.12, max: 0.12)
        } else if benchmark.satBenchmark != nil && profile.testOptional {
            switch college.rank {
            case ...20:
                testDelta = -0.12
            case 21...50:
                testDelta = -0.08
            default:
                testDelta = -0.05
            }
        } else {
            testDelta = 0
        }

        let rigorDelta = benchmark.rigorBenchmark.map { target in
            clamp(Double(profile.rigor - target) * 0.04, min: -0.08, max: 0.08)
        } ?? 0

        let curriculumDelta = benchmark.rigorBenchmark.map { target in
            clamp((curriculumPerformanceIndex(profile) - Double(target * 20)) / 50 * 0.10, min: -0.08, max: 0.08)
        } ?? 0

        let raw = gpaDelta + rankDelta + testDelta + rigorDelta + curriculumDelta
        let majorScale = profile.major == .arts ? 0.55 : 1
        return clamp(raw * majorScale, min: -0.25, max: 0.25)
    }

    private func academicBenchmarkDetail(profile: StudentProfile, college: College, benchmark: AcademicBenchmark) -> String {
        let gpa = benchmark.gpaPercentBenchmark.map { String(format: "%.0f", $0) } ?? "缺失"
        let rank = benchmark.classRankPercentileBenchmark.map { "前\(String(format: "%.0f", $0))%" } ?? "缺失"
        let sat = isTestFreeForAdmissions(college) ? "不使用（test-free）" : (benchmark.satBenchmark.map(String.init) ?? "不使用")
        let act = isTestFreeForAdmissions(college) ? "不使用（test-free）" : (benchmark.actBenchmark.map(String.init) ?? "不使用")
        let rigor = benchmark.rigorBenchmark.map(String.init) ?? "缺失"
        let applicantSAT = isTestFreeForAdmissions(college) ? "不使用（test-free）" : (submittedSATEquivalent(profile).map(String.init) ?? (profile.testOptional ? "Test optional" : "缺失"))
        let gpaScore = normalizedGPAScore(profile)
        let curriculumScore = curriculumPerformanceIndex(profile)
        let inferred: String
        if benchmarkHasOfficialFields(benchmark), benchmark.isInferred {
            inferred = "部分官方/部分推断基准"
        } else {
            inferred = benchmark.isInferred ? "推断基准" : "官方/核验基准"
        }
        return "\(inferred)：GPA \(gpa)，排名 \(rank)，SAT \(sat)，ACT \(act)，课程难度 \(rigor)/5；申请者 \(profile.gradeScale.rawValue) 学术指数 \(String(format: "%.0f", gpaScore))/100，排名前\(String(format: "%.0f", profile.classRankPercentile))%，SAT等效 \(applicantSAT)，课程难度 \(profile.rigor)/5，\(profile.curriculum.rawValue) 体系内成绩指数 \(String(format: "%.0f", curriculumScore))/100。"
    }

    private func benchmarkHasOfficialFields(_ benchmark: AcademicBenchmark) -> Bool {
        benchmark.sourceFields.contains { $0.localizedCaseInsensitiveContains("official") }
    }

    private func curriculumPerformanceIndex(_ profile: StudentProfile) -> Double {
        switch profile.curriculum {
        case .chinese:
            return gradeScaleScore(
                scale: profile.curriculumGradeScale,
                percent: profile.chineseCurriculumScore,
                fourPoint: profile.chineseCurriculumGPAFourPoint,
                fivePoint: profile.chineseCurriculumGPAFivePoint,
                letterGrade: profile.chineseCurriculumLetterGrade
            )
        case .ap:
            guard profile.apCourseCount > 0 else {
                return 0
            }
            let scoreComponent = piecewiseScore(
                Double(profile.apAverageScore),
                points: [(1.0, 12), (2.0, 24), (3.0, 40), (4.0, 58), (4.5, 68), (5.0, 76)]
            )
            let firstFive = min(profile.apCourseCount, 5) * 4
            let nextThree = max(0, min(profile.apCourseCount - 5, 3)) * 2
            let finalTwo = max(0, min(profile.apCourseCount - 8, 2))
            let courseBonus = Double(firstFive + nextThree + finalTwo)
            return clamp(scoreComponent + courseBonus, min: 0, max: 100)
        case .ib:
            return piecewiseScore(
                Double(profile.ibPredictedScore),
                points: [(24, 36), (28, 46), (30, 55), (34, 68), (38, 82), (42, 94), (45, 100)]
            )
        case .alevel:
            let capped = profile.cappedALevelGradeCounts
            let courseCount = capped.aStar + capped.a + capped.b
            let raw = Double(capped.aStar) * 32 + Double(capped.a) * 24 + Double(capped.b) * 14
            let coursePenalty = max(0, 3 - courseCount) * 12
            return clamp(raw - Double(coursePenalty), min: 0, max: 100)
        }
    }

    private func normalizedGPAScore(_ profile: StudentProfile) -> Double {
        gradeScaleScore(
            scale: profile.gradeScale,
            percent: profile.gpaPercent,
            fourPoint: profile.gpaFourPoint,
            fivePoint: profile.gpaFivePoint,
            letterGrade: profile.letterGrade
        )
    }

    private func gradeScaleScore(scale: GradeScale, percent: Double, fourPoint: Double, fivePoint: Double, letterGrade: LetterGradeBand) -> Double {
        switch scale {
        case .percent:
            return clamp(percent, min: 0, max: 100)
        case .fourPoint:
            return piecewiseScore(
                fourPoint,
                points: [(0, 0), (1.0, 45), (2.0, 70), (2.7, 78), (3.0, 82), (3.3, 87), (3.5, 90), (3.7, 93), (3.9, 97), (4.0, 100)]
            )
        case .fivePoint:
            return piecewiseScore(
                fivePoint,
                points: [(0, 0), (1.0, 40), (2.5, 68), (3.0, 74), (3.5, 80), (3.7, 83), (4.0, 87), (4.2, 90), (4.5, 93), (4.7, 96), (5.0, 100)]
            )
        case .letter:
            switch letterGrade {
            case .aPlus: return 98
            case .a: return 95
            case .aMinus: return 91
            case .bPlus: return 87
            case .b: return 83
            case .bMinus: return 79
            case .cPlus: return 74
            case .c: return 70
            case .d: return 55
            case .f: return 25
            case .cOrBelow: return 60
            }
        }
    }

    private func piecewiseScore(_ value: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first else {
            return 0
        }
        if value <= first.0 {
            return first.1
        }

        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            if value <= upper.0 {
                let progress = (value - lower.0) / (upper.0 - lower.0)
                return lower.1 + progress * (upper.1 - lower.1)
            }
        }

        return points.last?.1 ?? first.1
    }

    private func internationalSignal(for college: College) -> InternationalSignal {
        internationalSignals.first(where: { $0.collegeID == college.id }) ?? InternationalSignal(
            collegeID: college.id,
            undergradNonresidentShare: nil,
            internationalAdmittedCount: nil,
            totalAdmittedCount: nil,
            internationalAdmitCoefficient: nil,
            internationalAidPolicy: .unknown,
            isUndergradOnly: true,
            dataScope: "missing_undergraduate_international_data",
            sourceFields: [],
            sourceURL: nil,
            sourceNote: "Missing international proxy row.",
            dataQuality: 0.3
        )
    }

    private func chinaAdmissionSignal(for college: College) -> ChinaUndergradAdmissionSignal {
        chinaAdmissionSignals.first(where: { $0.collegeID == college.id }) ?? ChinaUndergradAdmissionSignal(
            collegeID: college.id,
            early2028: nil,
            rd2028: nil,
            total2028: nil,
            early2029: nil,
            rd2029: nil,
            total2029: nil,
            early2030: nil,
            rd2030: nil,
            total2030: nil,
            chinaShareOfAllAdmits: nil,
            dataScope: "missing_china_undergraduate_admits",
            sourceNote: "No China undergraduate admission count row.",
            dataQuality: 0.3
        )
    }

    private func aidAdjustment(profile: StudentProfile, signal: InternationalSignal) -> Double {
        guard profile.needsAid else {
            return 0
        }
        guard profile.applicantStatus.isInternational else {
            return 0
        }
        switch signal.internationalAidPolicy {
        case .needBlind:
            return 0
        case .needAware:
            return -0.24
        case .limited:
            return -0.32
        case .unknown:
            return -0.18
        }
    }

    private func internationalAdjustment(profile: StudentProfile, signal: InternationalSignal) -> Double {
        guard profile.applicantStatus.isInternational else {
            return 0
        }

        if let coefficient = signal.internationalAdmitCoefficient {
            return clamp((coefficient - 0.12) * 0.9, min: -0.10, max: 0.12)
        }

        let shareDelta = signal.undergradNonresidentShare.map { share in
            clamp((share - 0.10) * 1.15, min: -0.08, max: 0.10)
        } ?? 0
        return shareDelta
    }

    private func internationalDetail(profile: StudentProfile, signal: InternationalSignal) -> String {
        guard profile.applicantStatus.isInternational else {
            return "\(profile.applicantStatus.rawValue)：不使用国际生代理修正。"
        }

        let coefficient = signal.internationalAdmitCoefficient.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "缺失"
        let share = signal.undergradNonresidentShare.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "缺失"
        return "\(profile.applicantStatus.rawValue)：本科国际生录取系数 \(coefficient)，本科 nonresident 占比 \(share)，资助政策 \(signal.internationalAidPolicy.rawValue)。"
    }

    private func ordinaryApplicantPrior(for college: College, profile: StudentProfile, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal) -> Double {
        var prior = college.latestAvailableRate

        if profile.applicantStatus.isInternational {
            prior *= internationalPoolMultiplier(for: internationalSignal)
        }

        if profile.applicantStatus.usesChinaProxy {
            prior *= unhookedSeatMultiplier(for: college)
            prior *= chinaCapacityMultiplier(for: chinaSignal, college: college, round: profile.round)
        }

        return clamp(prior, min: 0.001, max: college.latestAvailableRate)
    }

    private func ordinaryPriorDetail(for college: College, profile: StudentProfile, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal) -> String {
        let prior = ordinaryApplicantPrior(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)
        guard profile.applicantStatus.usesChinaProxy else {
            return "使用学校整体录取率并按国际生数据可得性做保守校准：\(prior.formatted(.percent.precision(.fractionLength(1))))。"
        }

        let roundCapacity = chinaCapacityCount(for: chinaSignal, college: college, round: profile.round).map(String.init) ?? "缺失"
        let total = chinaSignal.total2030.map(String.init) ?? "缺失"
        return "从整体录取率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1)))) 下调为普通中国籍国际生先验 \(prior.formatted(.percent.precision(.fractionLength(1))))；2030 届中国总录取 \(total) 人，当前轮次容量 \(roundCapacity)，并扣除顶尖校特殊通道容量影响。"
    }

    private func internationalPoolMultiplier(for signal: InternationalSignal) -> Double {
        if let coefficient = signal.internationalAdmitCoefficient {
            return clamp(coefficient / 0.12, min: 0.60, max: 1.05)
        }

        guard let share = signal.undergradNonresidentShare else {
            return 0.78
        }
        return clamp(0.80 + (share - 0.10) * 1.5, min: 0.68, max: 1.02)
    }

    private func unhookedSeatMultiplier(for college: College) -> Double {
        switch college.rank {
        case ...10:
            return 0.70
        case 11...20:
            return 0.78
        case 21...30:
            return 0.84
        case 31...50:
            return 0.90
        default:
            return 0.94
        }
    }

    private func chinaCapacityMultiplier(for signal: ChinaUndergradAdmissionSignal, college: College, round: ApplicationRound) -> Double {
        guard let capacity = chinaCapacityCount(for: signal, college: college, round: round) else {
            return 0.72
        }

        switch capacity {
        case 0..<12:
            return 0.34
        case 12..<25:
            return 0.45
        case 25..<50:
            return 0.58
        case 50..<100:
            return 0.72
        case 100..<250:
            return 0.88
        default:
            return 1.00
        }
    }

    private func probabilityCap(for college: College, profile: StudentProfile, chinaSignal: ChinaUndergradAdmissionSignal) -> Double {
        guard profile.applicantStatus.usesChinaProxy else {
            return 0.82
        }

        let capacityCap: Double
        switch chinaCapacityCount(for: chinaSignal, college: college, round: profile.round) {
        case .some(0..<12):
            capacityCap = 0.025
        case .some(12..<25):
            capacityCap = 0.040
        case .some(25..<50):
            capacityCap = 0.070
        case .some(50..<100):
            capacityCap = 0.110
        case .some(100..<250):
            capacityCap = 0.180
        case .some:
            capacityCap = college.rank <= 20 ? 0.240 : 0.420
        case .none:
            capacityCap = missingChinaCapacityCap(for: college)
        }

        return min(0.82, capacityCap + eliteHighSchoolCapacityLift(profile: profile, college: college))
    }

    private func missingChinaCapacityCap(for college: College) -> Double {
        guard college.category == .nationalUniversity else {
            return 0.180
        }
        switch college.rank {
        case ...20:
            return 0.080
        case 21...30 where college.latestAvailableRate >= 0.20:
            return 0.240
        case 31...50 where college.latestAvailableRate >= 0.30:
            return 0.300
        default:
            return 0.180
        }
    }

    private func eliteHighSchoolCapacityLift(profile: StudentProfile, college: College) -> Double {
        guard college.category == .nationalUniversity else {
            return 0
        }
        let schoolContext = highSchoolContext(for: profile)
        let scale = eliteHighSchoolCohortScale(profile: profile, schoolContext: schoolContext)
        guard scale > 0 else {
            return 0
        }

        let lift: Double
        switch college.rank {
        case ...10:
            lift = 0
        case 11...20:
            lift = 0.34
        case 21...30:
            lift = 0.38
        case 31...50:
            lift = 0.32
        default:
            lift = 0.16
        }
        return lift * scale
    }

    private func chinaCapacityCount(for signal: ChinaUndergradAdmissionSignal, college: College, round: ApplicationRound) -> Int? {
        if isUCCampus(college) {
            return signal.total2030
        }

        switch round {
        case .earlyAction, .earlyDecision:
            return signal.early2030 ?? signal.total2030
        case .regularDecision:
            return signal.rd2030 ?? signal.total2030
        }
    }

    private func chinaAdmissionAdjustment(profile: StudentProfile, signal: ChinaUndergradAdmissionSignal) -> Double {
        guard profile.applicantStatus.usesChinaProxy else {
            return 0
        }

        if let share = signal.chinaShareOfAllAdmits {
            return clamp((share - 0.04) * 1.1, min: -0.08, max: 0.12)
        }

        let trendDelta: Double
        if let total2030 = signal.total2030, let total2029 = signal.total2029, total2029 > 0 {
            let growth = Double(total2030 - total2029) / Double(total2029)
            trendDelta = clamp(growth * 0.035, min: -0.04, max: 0.035)
        } else {
            trendDelta = 0
        }

        return trendDelta
    }

    private func chinaAdmissionDetail(profile: StudentProfile, signal: ChinaUndergradAdmissionSignal) -> String {
        guard profile.applicantStatus.usesChinaProxy else {
            return "\(profile.applicantStatus.rawValue)：不使用中国学生录取人数修正。"
        }

        let total = signal.total2030.map(String.init) ?? "缺失"
        let early = signal.early2030.map(String.init) ?? "缺失"
        let rd = signal.rd2030.map(String.init) ?? "缺失"
        if let share = signal.chinaShareOfAllAdmits {
            return "2030 届中国学生本科录取 \(total) 人，早申 \(early)，RD \(rd)，占全部录取 \(share.formatted(.percent.precision(.fractionLength(1))))。"
        }
        return "2030 届中国学生本科录取 \(total) 人，早申 \(early)，RD \(rd)。缺少中国申请人数分母，当前作为容量约束和趋势信号。"
    }

    private func roundAdjustment(_ round: ApplicationRound, college: College) -> Double {
        if isUCCampus(college) {
            return 0
        }

        switch round {
        case .earlyDecision:
            return roundPolicyRules(for: college).compactMap(\.earlyDecisionAdjustment).first ?? 0
        case .earlyAction:
            return roundPolicyRules(for: college).compactMap(\.earlyActionAdjustment).first ?? 0
        case .regularDecision: return 0
        }
    }

    private func hasSchoolSpecificRoundPolicy(_ college: College) -> Bool {
        !roundPolicyRules(for: college).isEmpty
    }

    private func roundPolicyRules(for college: College) -> [CollegeGateRule] {
        gateRules.filter { $0.collegeID == college.id && $0.type == .round }
    }

    private func bucket(_ probability: Double) -> RecommendationBucket {
        if probability == 0 { return .blocked }
        if probability < 0.20 { return .reach }
        if probability < 0.60 { return .target }
        return .likely
    }

    private func logistic(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }

    private func logit(_ probability: Double) -> Double {
        log(probability / (1 - probability))
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value))
    }

    private func isUCCampus(_ college: College) -> Bool {
        ["uc_berkeley", "ucla", "ucsd", "uc_davis", "uc_irvine"].contains(college.id)
    }

    private func isTestFreeForAdmissions(_ college: College) -> Bool {
        isUCCampus(college)
    }
}

private struct StudentScoreWeights {
    let gpa: Double
    let rank: Double
    let rigor: Double
    let curriculumPerformance: Double
    let testing: Double
    let school: Double
    let activities: Double
    let research: Double
    let honors: Double
    let essay: Double
    let recommendations: Double
}
