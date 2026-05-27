import Foundation

struct ChanceEngine {
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

    func evaluate(profile: StudentProfile, selectedCollegeIDs: Set<String>) -> PortfolioResult {
        let profileScore = studentScore(profile)
        let selected = selectedCollegeIDs.isEmpty
            ? recommendedColleges(for: profile, count: profile.requestedSchoolCount)
            : colleges.filter { selectedCollegeIDs.contains($0.id) }

        let schoolResults = selected.map { chance(for: $0, profile: profile, profileScore: profileScore) }
            .sorted { $0.adjustedProbability > $1.adjustedProbability }
        let allResults = colleges.map { chance(for: $0, profile: profile, profileScore: profileScore) }

        return PortfolioResult(
            schoolResults: schoolResults,
            recommendedSchools: selectedCollegeIDs.isEmpty ? selected : recommendedColleges(for: profile, count: min(6, profile.requestedSchoolCount)),
            t10AtLeastOne: atLeastOneProbability(allResults.filter { $0.college.rank <= 10 }),
            t30AtLeastOne: atLeastOneProbability(allResults.filter { $0.college.rank <= 30 }),
            t50AtLeastOne: atLeastOneProbability(allResults.filter { $0.college.rank <= 50 }),
            selectedAtLeastOne: atLeastOneProbability(schoolResults),
            profileScore: profileScore,
            generatedAt: Date()
        )
    }

    func chance(for college: College, profile: StudentProfile, profileScore: Double? = nil) -> ChanceResult {
        let score = profileScore ?? studentScore(profile)
        let gate = gateResult(for: college, profile: profile)
        let baseRate = college.latestAvailableRate
        let baseFactor = ChanceFactor(
            label: "学校基础率",
            value: baseRate,
            detail: "AdmissionSight \(college.latestAvailableClassYear) 届最新可用录取率。"
        )

        guard gate.passed else {
            let warnings = gate.failedRules.map { "未满足\($0.isOfficial ? "官方" : "推断")硬门槛：\($0.title)" }
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

        let schoolContext = highSchools.first(where: { $0.id == profile.highSchoolID }) ?? highSchools.last!
        let internationalSignal = internationalSignal(for: college)
        let chinaSignal = chinaAdmissionSignal(for: college)
        let benchmark = academicBenchmark(for: college)
        let ordinaryPrior = ordinaryApplicantPrior(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)
        let readinessDelta = (score - 72) * 0.047
        let academicBenchmarkDelta = academicBenchmarkAdjustment(profile: profile, college: college, benchmark: benchmark)
        let highSchoolDelta = schoolContext.calibration
        let majorDelta = majorAdjustment(profile.major)
        let roundDelta = roundAdjustment(profile.round, college: college)
        let aidDelta = aidAdjustment(profile: profile, signal: internationalSignal)
        let internationalDelta = internationalAdjustment(profile: profile, signal: internationalSignal)
        let chinaAdmissionDelta = chinaAdmissionAdjustment(profile: profile, signal: chinaSignal)
        let internationalDataPenalty = profile.applicantStatus.isInternational ? (1 - internationalSignal.dataQuality) * -0.08 : 0
        let chinaDataPenalty = profile.applicantStatus.usesChinaProxy ? (1 - chinaSignal.dataQuality) * -0.05 : 0
        let benchmarkDataPenalty = (1 - benchmark.dataQuality) * -0.04
        let uncertaintyPenalty = (1 - college.dataQuality) * -0.12 + internationalDataPenalty + chinaDataPenalty + benchmarkDataPenalty + gate.confidenceImpact

        let logitPrior = logit(clamp(ordinaryPrior, min: 0.001, max: 0.72))
        let adjustedLogit = logitPrior + readinessDelta + academicBenchmarkDelta + highSchoolDelta + majorDelta + roundDelta + aidDelta + internationalDelta + chinaAdmissionDelta + uncertaintyPenalty
        let probability = clamp(logistic(adjustedLogit), min: 0.001, max: probabilityCap(for: college, profile: profile, chinaSignal: chinaSignal))

        let factors = [
            baseFactor,
            ChanceFactor(label: "普通申请池先验", value: ordinaryPrior, detail: ordinaryPriorDetail(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)),
            ChanceFactor(label: "学生画像", value: readinessDelta, detail: "学术、课程、标化、活动、奖项、文书与推荐信合成分：\(Int(score))/100。"),
            ChanceFactor(label: "目标校学术匹配", value: academicBenchmarkDelta, detail: academicBenchmarkDetail(profile: profile, benchmark: benchmark)),
            ChanceFactor(label: "高中背景", value: highSchoolDelta, detail: "\(schoolContext.name) 的资源、升学记录与透明度校准。"),
            ChanceFactor(label: "专业竞争", value: majorDelta, detail: "\(profile.major.rawValue) 的竞争强度修正。"),
            ChanceFactor(label: "申请身份", value: internationalDelta, detail: internationalDetail(profile: profile, signal: internationalSignal)),
            ChanceFactor(label: "中国录取信号", value: chinaAdmissionDelta, detail: chinaAdmissionDetail(profile: profile, signal: chinaSignal)),
            ChanceFactor(label: "申请策略", value: roundDelta + aidDelta, detail: "\(profile.round.rawValue) 轮次与资助需求修正。")
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
            if !rule.isOfficial {
                inferred.append(rule)
            }

            switch rule.type {
            case .standardizedTest:
                if let minimumSAT = rule.minimumSAT {
                    let satEquivalent = profile.sat ?? actToSat(profile.act)
                    if profile.testOptional || (satEquivalent ?? 0) < minimumSAT {
                        failed.append(rule)
                    }
                }
            case .english:
                if profile.applicantStatus.requiresEnglishProof, let minimumTOEFL = rule.minimumTOEFL, !meetsEnglishRequirement(profile, minimumTOEFL: minimumTOEFL) {
                    failed.append(rule)
                }
            case .curriculum:
                if profile.major.isSTEM, let minimum = rule.minimumStrengthBand, profile.rigor < minimum {
                    failed.append(rule)
                }
            case .portfolio:
                if profile.major == .arts && !profile.hasPortfolio {
                    failed.append(rule)
                }
            case .round:
                if let required = rule.requiredRound, required != profile.round {
                    failed.append(rule)
                }
            }
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

    func studentScore(_ profile: StudentProfile) -> Double {
        let gpa = clamp(profile.gpaPercent, min: 0, max: 100)
        let rank = clamp(100 - profile.classRankPercentile, min: 30, max: 100)
        let rigor = band(profile.rigor)
        let curriculumPerformance = curriculumPerformanceScore(profile)
        let testing = testingScore(profile)
        let activities = band(profile.activities)
        let research = band(profile.research)
        let honors = band(profile.honors)
        let essay = band(profile.essay)
        let recs = band(profile.recommendations)
        let school = highSchools.first(where: { $0.id == profile.highSchoolID }) ?? highSchools.last!
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
        let score = studentScore(profile)
        let eligible = colleges
            .map { chance(for: $0, profile: profile, profileScore: score) }
            .filter { $0.gateResult.passed }
            .sorted { lhs, rhs in
                let lhsBalance = abs(lhs.adjustedProbability - 0.22)
                let rhsBalance = abs(rhs.adjustedProbability - 0.22)
                return lhsBalance == rhsBalance ? lhs.college.rank < rhs.college.rank : lhsBalance < rhsBalance
            }

        let reach = eligible.filter { $0.adjustedProbability < 0.15 }
        let target = eligible.filter { $0.adjustedProbability >= 0.15 && $0.adjustedProbability < 0.35 }
        let likely = eligible.filter { $0.adjustedProbability >= 0.35 }
        let targetCount = max(1, Int(Double(count) * 0.45))
        let likelyCount = max(1, Int(Double(count) * 0.30))
        let reachCount = max(0, count - targetCount - likelyCount)

        var picked = Array(target.prefix(targetCount)).map(\.college)
        picked.append(contentsOf: likely.prefix(likelyCount).map(\.college))
        picked.append(contentsOf: reach.prefix(reachCount).map(\.college))

        if picked.count < count {
            let existing = Set(picked.map(\.id))
            picked.append(contentsOf: eligible.map(\.college).filter { !existing.contains($0.id) }.prefix(count - picked.count))
        }
        return Array(picked.prefix(max(1, count)))
    }

    func atLeastOneProbability(_ results: [ChanceResult]) -> Double {
        let grouped = Dictionary(grouping: results.filter { $0.adjustedProbability > 0 }) { $0.college.tierName }
        var failure = 1.0
        for probabilities in grouped.values {
            let sorted = probabilities.map(\.adjustedProbability).sorted(by: >)
            for (index, probability) in sorted.enumerated() {
                let effective = probability * pow(0.72, Double(index))
                failure *= (1 - effective)
            }
        }
        return clamp(1 - failure, min: 0, max: 0.98)
    }

    private func warnings(for college: College, profile: StudentProfile, gate: GateResult, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal, benchmark: AcademicBenchmark) -> [String] {
        var items: [String] = []
        if college.acceptanceRates.contains(where: { $0.rate == nil }) {
            items.append("该校最新年份存在 N/A，已使用最近非空录取率。")
        }
        if !gate.inferredRules.isEmpty {
            items.append("包含 \(gate.inferredRules.count) 条推断硬门槛，结果置信度已下调。")
        }
        if college.dataQuality < 0.8 {
            items.append("学校统计数据存在缺口，建议后续补官方 CDS/招生页面。")
        }
        if benchmark.isInferred {
            items.append("目标校学术基准为推断值，用于相对比较 GPA、排名、标化和课程难度；不是官方录取均值。")
        }
        if benchmark.dataQuality < 0.5 {
            items.append("目标校学术基准置信度较低，建议后续补官方 CDS 或 class profile。")
        }
        if profile.applicantStatus.isInternational {
            items.append("国际生数据仅使用本科口径；录取系数只有在本科国际生 admitted 数和总 admitted 数同时可用时才参与计算。")
            if internationalSignal.internationalAdmitCoefficient == nil {
                items.append("该校缺少本科国际生录取系数，当前使用本科 nonresident 占比作为弱代理。")
            }
            if internationalSignal.dataQuality < 0.5 || internationalSignal.undergradNonresidentShare == nil {
                items.append("该校国际生代理数据缺失或置信度低，当前主要依赖整体录取率。")
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
            if let total2030 = chinaSignal.total2030, total2030 < 50 {
                items.append("该校中国学生录取容量很小，最终概率已按小容量学校保守封顶。")
            }
        }
        return items
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
        if profile.testOptional { score -= 10 }
        if profile.applicantStatus.requiresEnglishProof && profile.toefl == nil && profile.ielts == nil { score -= 8 }
        if profile.highSchoolID == "unknown" { score -= 10 }
        if score >= 78 { return .high }
        if score >= 58 { return .medium }
        return .low
    }

    private func testingScore(_ profile: StudentProfile) -> Double {
        if profile.testOptional {
            return 54
        }
        let satScore = profile.sat.map { clamp((Double($0) - 1050) / 550 * 100, min: 0, max: 100) } ?? 0
        let actScore = profile.act.map { clamp((Double($0) - 21) / 15 * 100, min: 0, max: 100) } ?? 0
        let english = englishScore(profile)
        return max(satScore, actScore) * 0.72 + english * 0.28
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

    private func actToSat(_ act: Int?) -> Int? {
        guard let act else { return nil }
        return Int(Double(act - 21) / 15.0 * 550.0 + 1050.0)
    }

    private func band(_ value: Int) -> Double {
        clamp(Double(value), min: 1, max: 5) * 20
    }

    private func majorAdjustment(_ major: MajorCategory) -> Double {
        switch major {
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
            clamp((profile.gpaPercent - target) / 10 * 0.16, min: -0.12, max: 0.12)
        } ?? 0

        let rankDelta = benchmark.classRankPercentileBenchmark.map { target in
            clamp((target - profile.classRankPercentile) / 20 * 0.12, min: -0.10, max: 0.10)
        } ?? 0

        let satEquivalent = profile.sat ?? actToSat(profile.act)
        let testDelta: Double
        if let satBenchmark = benchmark.satBenchmark, let satEquivalent {
            testDelta = clamp((Double(satEquivalent - satBenchmark)) / 200 * 0.14, min: -0.12, max: 0.12)
        } else if benchmark.satBenchmark != nil && profile.testOptional {
            testDelta = college.rank <= 20 ? -0.08 : -0.05
        } else {
            testDelta = 0
        }

        let rigorDelta = benchmark.rigorBenchmark.map { target in
            clamp(Double(profile.rigor - target) * 0.04, min: -0.08, max: 0.08)
        } ?? 0

        let curriculumDelta = benchmark.rigorBenchmark.map { target in
            clamp((curriculumPerformanceScore(profile) - Double(target * 20)) / 50 * 0.10, min: -0.08, max: 0.08)
        } ?? 0

        let raw = gpaDelta + rankDelta + testDelta + rigorDelta + curriculumDelta
        let majorScale = profile.major == .arts ? 0.55 : 1
        return clamp(raw * majorScale, min: -0.25, max: 0.25)
    }

    private func academicBenchmarkDetail(profile: StudentProfile, benchmark: AcademicBenchmark) -> String {
        let gpa = benchmark.gpaPercentBenchmark.map { String(format: "%.0f", $0) } ?? "缺失"
        let rank = benchmark.classRankPercentileBenchmark.map { "前\(String(format: "%.0f", $0))%" } ?? "缺失"
        let sat = benchmark.satBenchmark.map(String.init) ?? "不使用"
        let act = benchmark.actBenchmark.map(String.init) ?? "不使用"
        let rigor = benchmark.rigorBenchmark.map(String.init) ?? "缺失"
        let applicantSAT = (profile.sat ?? actToSat(profile.act)).map(String.init) ?? (profile.testOptional ? "Test optional" : "缺失")
        let curriculumScore = curriculumPerformanceScore(profile)
        let inferred = benchmark.isInferred ? "推断基准" : "官方/核验基准"
        return "\(inferred)：GPA \(gpa)，排名 \(rank)，SAT \(sat)，ACT \(act)，课程难度 \(rigor)/5；申请者 GPA \(String(format: "%.0f", profile.gpaPercent))，排名前\(String(format: "%.0f", profile.classRankPercentile))%，SAT等效 \(applicantSAT)，课程难度 \(profile.rigor)/5，\(profile.curriculum.rawValue) 成绩分 \(String(format: "%.0f", curriculumScore))/100。"
    }

    private func curriculumPerformanceScore(_ profile: StudentProfile) -> Double {
        switch profile.curriculum {
        case .chinese:
            return clamp(profile.chineseCurriculumScore, min: 0, max: 100)
        case .ap:
            let scoreComponent = clamp((profile.apAverageScore - 3.0) / 2.0 * 70 + 30, min: 0, max: 100)
            let courseBonus = Double(min(profile.apCourseCount, 8)) * 3
            return clamp(scoreComponent + courseBonus, min: 0, max: 100)
        case .ib:
            return clamp((Double(profile.ibPredictedScore) - 28) / 17 * 100, min: 0, max: 100)
        case .alevel:
            return clamp(Double(profile.aLevelAStarCount) * 25 + Double(profile.aLevelACount) * 16, min: 0, max: 100)
        }
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
            return 0.02
        }
        guard profile.applicantStatus.isInternational else {
            return -0.04
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
            prior *= chinaCapacityMultiplier(for: chinaSignal)
        }

        return clamp(prior, min: 0.001, max: college.latestAvailableRate)
    }

    private func ordinaryPriorDetail(for college: College, profile: StudentProfile, internationalSignal: InternationalSignal, chinaSignal: ChinaUndergradAdmissionSignal) -> String {
        let prior = ordinaryApplicantPrior(for: college, profile: profile, internationalSignal: internationalSignal, chinaSignal: chinaSignal)
        guard profile.applicantStatus.usesChinaProxy else {
            return "使用学校整体录取率并按国际生数据可得性做保守校准：\(prior.formatted(.percent.precision(.fractionLength(1))))。"
        }

        let chinaTotal = chinaSignal.total2030.map(String.init) ?? "缺失"
        return "从整体录取率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1)))) 下调为普通中国籍国际生先验 \(prior.formatted(.percent.precision(.fractionLength(1))))；2030 届中国录取人数 \(chinaTotal)，并扣除顶尖校特殊通道容量影响。"
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

    private func chinaCapacityMultiplier(for signal: ChinaUndergradAdmissionSignal) -> Double {
        guard let total2030 = signal.total2030 else {
            return 0.72
        }

        switch total2030 {
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
        switch chinaSignal.total2030 {
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
            capacityCap = college.rank <= 20 ? 0.080 : 0.180
        }

        return min(0.82, capacityCap)
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
        if college.id.hasPrefix("uc_") {
            return 0
        }

        switch round {
        case .earlyDecision:
            return college.rank <= 20 ? 0.12 : 0.14
        case .earlyAction:
            return college.rank <= 20 ? 0.03 : 0.05
        case .regularDecision: return 0
        }
    }

    private func bucket(_ probability: Double) -> RecommendationBucket {
        if probability == 0 { return .blocked }
        if probability < 0.15 { return .reach }
        if probability < 0.35 { return .target }
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
