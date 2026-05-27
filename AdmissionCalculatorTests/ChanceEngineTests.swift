import XCTest
@testable import AdmissionCalculator

final class ChanceEngineTests: XCTestCase {
    private let engine = ChanceEngine()

    func testOfficialGateFailureReturnsZeroProbability() {
        var profile = StudentProfile.sample
        profile.testOptional = true
        profile.sat = nil
        profile.act = nil
        profile.toefl = 110

        let mit = AdmissionsSeedData.colleges.first { $0.id == "mit" }!
        let result = engine.chance(for: mit, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertEqual(result.bucket, .blocked)
        XCTAssertTrue(result.gateResult.failedRules.contains { $0.isOfficial && $0.type == .standardizedTest })
        XCTAssertTrue(result.warnings.contains { $0.contains("MIT requires SAT/ACT") })
    }

    func testWeakButEligibleProfileReceivesNonZeroProbability() {
        var profile = StudentProfile.sample
        profile.gpaPercent = 82
        profile.classRankPercentile = 45
        profile.sat = 1320
        profile.toefl = 98
        profile.activities = 2
        profile.research = 1
        profile.honors = 1
        profile.essay = 2
        profile.recommendations = 2
        profile.major = .humanities

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertGreaterThan(result.adjustedProbability, 0)
        XCTAssertLessThan(result.adjustedProbability, 0.35)
    }

    func testProfileCompletionPromptsIdentifyDecisionCriticalMissingDetails() {
        var profile = StudentProfile.sample
        profile.toefl = nil
        profile.ielts = nil
        profile.sat = nil
        profile.act = nil
        profile.apCourseCount = 0

        let prompts = profile.completionPrompts(selectedCollegeIDs: [])
        let ids = Set(prompts.map(\.id))

        XCTAssertTrue(ids.contains("selected-schools"))
        XCTAssertTrue(ids.contains("english-proof"))
        XCTAssertTrue(ids.contains("standardized-test"))
        XCTAssertTrue(ids.contains("high-school-context"))
        XCTAssertTrue(ids.contains("ap-evidence"))
    }

    func testProfileCompletionPromptsClearWhenCoreInputsArePresent() {
        var profile = StudentProfile.sample
        profile.highSchoolID = "rdfz_icc"

        let prompts = profile.completionPrompts(selectedCollegeIDs: Set(["bu"]))

        XCTAssertTrue(prompts.isEmpty)
    }

    func testReportListsDecisionCriticalMissingInputs() {
        var profile = StudentProfile.sample
        profile.toefl = nil
        profile.ielts = nil
        profile.sat = nil
        profile.act = nil
        profile.apCourseCount = 0

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: [])
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("待补资料"))
        XCTAssertTrue(report.contains("选择学校组合"))
        XCTAssertTrue(report.contains("补充 TOEFL 或 IELTS"))
        XCTAssertTrue(report.contains("补充 SAT/ACT 或选择不提交"))
        XCTAssertTrue(report.contains("补充 AP 课程证据"))
    }

    func testInferredGateIsDisclosedAndCanBlock() {
        var profile = StudentProfile.sample
        profile.major = .arts
        profile.hasPortfolio = false

        let brown = AdmissionsSeedData.colleges.first { $0.id == "brown" }!
        let result = engine.chance(for: brown, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertTrue(result.gateResult.failedRules.contains { !$0.isOfficial && $0.type == .portfolio })
        XCTAssertEqual(result.confidence, .low)
    }

    func testArtsProfileUsesLowerAcademicEmphasisWhenPortfolioReady() {
        var academicHeavy = StudentProfile.sample
        academicHeavy.major = .arts
        academicHeavy.hasPortfolio = true
        academicHeavy.gpaPercent = 98
        academicHeavy.classRankPercentile = 2
        academicHeavy.sat = 1560
        academicHeavy.activities = 2
        academicHeavy.honors = 2
        academicHeavy.essay = 2
        academicHeavy.recommendations = 2

        var portfolioHeavy = academicHeavy
        portfolioHeavy.gpaPercent = 88
        portfolioHeavy.classRankPercentile = 25
        portfolioHeavy.sat = 1320
        portfolioHeavy.activities = 5
        portfolioHeavy.honors = 5
        portfolioHeavy.essay = 5
        portfolioHeavy.recommendations = 5

        let academicHeavyScore = engine.studentScore(academicHeavy)
        let portfolioHeavyScore = engine.studentScore(portfolioHeavy)

        XCTAssertGreaterThan(portfolioHeavyScore, academicHeavyScore)
    }

    func testArtsWithoutPortfolioStillBlocksDespiteAdjustedWeights() {
        var profile = StudentProfile.sample
        profile.major = .arts
        profile.hasPortfolio = false
        profile.gpaPercent = 99
        profile.sat = 1580
        profile.activities = 5
        profile.honors = 5
        profile.essay = 5

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertEqual(result.bucket, .blocked)
    }

    func testDomesticApplicantDoesNotFailInternationalEnglishGate() {
        var profile = StudentProfile.sample
        profile.applicantStatus = .usCitizenDomestic
        profile.toefl = nil
        profile.ielts = nil
        profile.major = .humanities

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertFalse(result.gateResult.failedRules.contains { $0.type == .english })
        XCTAssertGreaterThan(result.adjustedProbability, 0)
    }

    func testIrrelevantInferredGatesAreNotDisclosedOrPenalized() {
        var profile = StudentProfile.sample
        profile.applicantStatus = .usCitizenDomestic
        profile.major = .humanities
        profile.rigor = 1
        profile.hasPortfolio = false
        profile.toefl = nil
        profile.ielts = nil

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertTrue(result.gateResult.inferredRules.isEmpty)
        XCTAssertEqual(result.gateResult.confidenceImpact, -0.05, accuracy: 0.0001)
        XCTAssertFalse(result.warnings.contains { $0.contains("推断硬门槛") })
    }

    func testStemInferredCurriculumGateStillAppliesToComputerScience() {
        var profile = StudentProfile.sample
        profile.major = .computerScience
        profile.rigor = 2

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertTrue(result.gateResult.failedRules.contains { $0.type == .curriculum })
        XCTAssertTrue(result.gateResult.inferredRules.contains { $0.type == .curriculum })
    }

    func testInferredEnglishGateAcceptsIeltsSixPointFive() {
        var profile = StudentProfile.sample
        profile.applicantStatus = .chineseInternational
        profile.toefl = nil
        profile.ielts = 6.5
        profile.major = .humanities

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: profile)

        XCTAssertFalse(result.gateResult.failedRules.contains { $0.type == .english })
        XCTAssertGreaterThan(result.adjustedProbability, 0)
    }

    func testChineseInternationalApplicantGetsProxyDisclosure() {
        var profile = StudentProfile.sample
        profile.applicantStatus = .chineseInternational

        let nyu = AdmissionsSeedData.colleges.first { $0.id == "nyu" }!
        let result = engine.chance(for: nyu, profile: profile)

        XCTAssertTrue(result.factors.contains { $0.label == "申请身份" })
        XCTAssertTrue(result.factors.contains { $0.label == "中国录取信号" })
        XCTAssertTrue(result.factors.contains { $0.label == "普通申请池先验" })
        XCTAssertTrue(result.warnings.contains { $0.contains("中国学生录取数据缺少申请人数分母") })
    }

    func testAcademicBenchmarkFitMovesProbabilityDirectionally() {
        var belowBenchmark = StudentProfile.sample
        belowBenchmark.major = .humanities
        belowBenchmark.gpaPercent = 86
        belowBenchmark.classRankPercentile = 35
        belowBenchmark.rigor = 2
        belowBenchmark.sat = 1320
        belowBenchmark.toefl = 102

        var aboveBenchmark = belowBenchmark
        aboveBenchmark.gpaPercent = 98
        aboveBenchmark.classRankPercentile = 2
        aboveBenchmark.rigor = 5
        aboveBenchmark.sat = 1560

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let below = engine.chance(for: bu, profile: belowBenchmark)
        let above = engine.chance(for: bu, profile: aboveBenchmark)

        XCTAssertTrue(below.gateResult.passed)
        XCTAssertTrue(above.gateResult.passed)
        XCTAssertGreaterThan(above.adjustedProbability, below.adjustedProbability)
        XCTAssertTrue(above.factors.contains { $0.label == "目标校学术匹配" && $0.value > 0 })
        XCTAssertTrue(below.factors.contains { $0.label == "目标校学术匹配" && $0.value < 0 })
    }

    func testCurriculumPerformanceAffectsProfileScoreAndProbability() {
        var weakAP = StudentProfile.sample
        weakAP.major = .humanities
        weakAP.curriculum = .ap
        weakAP.apCourseCount = 2
        weakAP.apAverageScore = 3.0

        var strongAP = weakAP
        strongAP.apCourseCount = 8
        strongAP.apAverageScore = 5.0

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let weak = engine.chance(for: bu, profile: weakAP)
        let strong = engine.chance(for: bu, profile: strongAP)

        XCTAssertGreaterThan(engine.studentScore(strongAP), engine.studentScore(weakAP))
        XCTAssertGreaterThan(strong.adjustedProbability, weak.adjustedProbability)
        XCTAssertTrue(strong.factors.contains { $0.label == "目标校学术匹配" && $0.detail.contains("AP 体系内成绩指数") })
    }

    func testZeroAPCoursesDoNotReceiveAverageScoreCredit() {
        var noAP = StudentProfile.sample
        noAP.major = .humanities
        noAP.curriculum = .ap
        noAP.apCourseCount = 0
        noAP.apAverageScore = 5.0

        var someAP = noAP
        someAP.apCourseCount = 2
        someAP.apAverageScore = 3.0

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let noAPResult = engine.chance(for: bu, profile: noAP)
        let someAPResult = engine.chance(for: bu, profile: someAP)

        XCTAssertGreaterThan(engine.studentScore(someAP), engine.studentScore(noAP))
        XCTAssertGreaterThan(someAPResult.adjustedProbability, noAPResult.adjustedProbability)
        XCTAssertTrue(noAPResult.warnings.contains { $0.contains("AP 体系课程门数为 0") })
        XCTAssertTrue(noAPResult.factors.contains { $0.label == "目标校学术匹配" && $0.value < 0 })
    }

    func testIBCurriculumScoreChangesAcademicReadiness() {
        var lowerIB = StudentProfile.sample
        lowerIB.major = .humanities
        lowerIB.curriculum = .ib
        lowerIB.ibPredictedScore = 32

        var higherIB = lowerIB
        higherIB.ibPredictedScore = 43

        XCTAssertGreaterThan(engine.studentScore(higherIB), engine.studentScore(lowerIB))
    }

    func testGpaScaleAffectsAcademicReadiness() {
        var lowerGPA = StudentProfile.sample
        lowerGPA.major = .humanities
        lowerGPA.gradeScale = .fourPoint
        lowerGPA.gpaFourPoint = 3.0

        var higherGPA = lowerGPA
        higherGPA.gpaFourPoint = 3.9

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let lower = engine.chance(for: bu, profile: lowerGPA)
        let higher = engine.chance(for: bu, profile: higherGPA)

        XCTAssertGreaterThan(engine.studentScore(higherGPA), engine.studentScore(lowerGPA))
        XCTAssertGreaterThan(higher.adjustedProbability, lower.adjustedProbability)
        XCTAssertTrue(higher.warnings.contains { $0.contains("内部学术指数") })
    }

    func testChineseCurriculumSupportsGpaScale() {
        var lowerCore = StudentProfile.sample
        lowerCore.major = .humanities
        lowerCore.curriculum = .chinese
        lowerCore.curriculumGradeScale = .fourPoint
        lowerCore.chineseCurriculumGPAFourPoint = 3.0

        var higherCore = lowerCore
        higherCore.chineseCurriculumGPAFourPoint = 3.9

        XCTAssertGreaterThan(engine.studentScore(higherCore), engine.studentScore(lowerCore))
    }

    func testALevelBGradesAreWeakerThanAGrades() {
        var bGrades = StudentProfile.sample
        bGrades.major = .humanities
        bGrades.curriculum = .alevel
        bGrades.aLevelAStarCount = 0
        bGrades.aLevelACount = 0
        bGrades.aLevelBCount = 3

        var aGrades = bGrades
        aGrades.aLevelACount = 3
        aGrades.aLevelBCount = 0

        XCTAssertGreaterThan(engine.studentScore(aGrades), engine.studentScore(bGrades))
    }

    func testSampleProfileUsesConservativeUnknownHighSchoolDefault() {
        XCTAssertEqual(StudentProfile.sample.highSchoolID, "unknown")

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: .sample)

        XCTAssertTrue(result.factors.contains { factor in
            factor.label == "高中背景" && factor.detail.contains("保守代理校准")
        })
        XCTAssertTrue(result.warnings.contains { $0.contains("高中背景为其他/手动评估学校") })
    }

    func testKnownHighSchoolContextCanImproveReadinessButIsOnlyProxy() {
        var unknown = StudentProfile.sample
        unknown.highSchoolID = "unknown"

        var known = unknown
        known.highSchoolID = "shsid"

        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let unknownResult = engine.chance(for: bu, profile: unknown)
        let knownResult = engine.chance(for: bu, profile: known)

        XCTAssertGreaterThan(engine.studentScore(known), engine.studentScore(unknown))
        XCTAssertGreaterThan(knownResult.factors.first { $0.label == "高中背景" }?.value ?? 0, unknownResult.factors.first { $0.label == "高中背景" }?.value ?? 0)
        XCTAssertTrue(knownResult.factors.contains { factor in
            factor.label == "高中背景" && factor.detail.contains("代理")
        })
    }

    func testLowChinaCapacityIvyPlusSchoolIsConservativelyCapped() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        let result = engine.chance(for: yale, profile: strongChineseInternationalProfile)

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertLessThan(result.adjustedProbability, 0.05)
        XCTAssertTrue(result.factors.contains { $0.label == "普通申请池先验" })
        XCTAssertTrue(result.warnings.contains { $0.contains("录取容量很小") })
    }

    func testChinaCapacitySeparatesYaleFromUCLAForSameProfile() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        let ucla = AdmissionsSeedData.colleges.first { $0.id == "ucla" }!

        let yaleResult = engine.chance(for: yale, profile: strongChineseInternationalProfile)
        let uclaResult = engine.chance(for: ucla, profile: strongChineseInternationalProfile)

        XCTAssertGreaterThan(uclaResult.adjustedProbability, yaleResult.adjustedProbability)
        XCTAssertGreaterThan(uclaResult.adjustedProbability, 0.05)
    }

    func testInferredAcademicBenchmarkIsDisclosed() {
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        let result = engine.chance(for: bu, profile: .sample)

        XCTAssertTrue(result.factors.contains { $0.label == "目标校学术匹配" })
        XCTAssertTrue(result.warnings.contains { $0.contains("目标校学术基准为推断值") })
    }

    func testPortfolioProbabilityBounds() {
        let selected = Set(["bu", "tufts", "uc_davis", "northeastern"])
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: selected)
        let probabilities = result.schoolResults.map(\.adjustedProbability)

        XCTAssertGreaterThanOrEqual(result.selectedAtLeastOne, probabilities.max() ?? 0)
        XCTAssertLessThanOrEqual(result.selectedAtLeastOne, min(1, probabilities.reduce(0, +)) + 0.0001)
    }

    func testTierProbabilitiesAreScopedToSelectedSchools() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]))

        XCTAssertEqual(result.t10AtLeastOne, 0)
        XCTAssertEqual(result.t30AtLeastOne, 0)
        XCTAssertEqual(result.schoolResults.map(\.college.id), ["bu"])
        XCTAssertEqual(result.selectedBucketCounts.total, 1)
        XCTAssertEqual(result.profileSnapshot, .sample)
        XCTAssertEqual(result.selectedCollegeIDs, Set(["bu"]))
        XCTAssertTrue(result.selectionWarnings.isEmpty)
    }

    func testUnknownSelectedCollegeIDsAreDisclosedAndExcluded() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "outside_dataset"]))

        XCTAssertEqual(result.schoolResults.map(\.college.id), ["bu"])
        XCTAssertEqual(result.selectedBucketCounts.total, 1)
        XCTAssertEqual(result.selectedCollegeIDs, Set(["bu", "outside_dataset"]))
        XCTAssertTrue(result.selectionWarnings.contains { $0.contains("不在 AdmissionSight v1 数据集内") })
    }

    func testPortfolioKeepsSubmittedProfileSnapshotForReports() {
        var submitted = StudentProfile.sample
        submitted.major = .humanities
        let result = engine.evaluate(profile: submitted, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)

        submitted.major = .computerScience
        let report = ReportService.makeReport(result: result)

        XCTAssertEqual(result.profileSnapshot.major, .humanities)
        XCTAssertTrue(report.contains("目标专业 Humanities"))
        XCTAssertFalse(report.contains("目标专业 Computer Science"))
        XCTAssertTrue(report.contains("高中背景"))
    }

    func testLegacyRecommendationCountDoesNotSilentlyBackfillBuckets() {
        XCTAssertTrue(engine.recommendedColleges(for: .sample, count: 0).isEmpty)
        XCTAssertLessThanOrEqual(engine.recommendedColleges(for: .sample, count: 1).count, 1)

        let count = 40
        let recommended = engine.recommendedColleges(for: .sample, count: count)
        let results = recommended.map { engine.chance(for: $0, profile: .sample) }
        let targetCount = max(1, Int(Double(count) * 0.45))
        let likelyCount = max(1, Int(Double(count) * 0.30))
        let reachCount = max(0, count - targetCount - likelyCount)

        XCTAssertLessThanOrEqual(recommended.count, count)
        XCTAssertLessThanOrEqual(results.filter { $0.bucket == .likely }.count, likelyCount)
        XCTAssertLessThanOrEqual(results.filter { $0.bucket == .target }.count, targetCount)
        XCTAssertLessThanOrEqual(results.filter { $0.bucket == .reach }.count, reachCount)
    }

    func testACTUsesConcordanceForProfileScoring() {
        var satProfile = StudentProfile.sample
        satProfile.major = .humanities
        satProfile.sat = 1460
        satProfile.act = nil
        satProfile.testOptional = false

        var actProfile = satProfile
        actProfile.sat = nil
        actProfile.act = 33

        XCTAssertEqual(engine.studentScore(actProfile), engine.studentScore(satProfile), accuracy: 0.0001)
    }

    func testEmptySelectionDoesNotImplicitlyAutoRecommendSchools() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: [])

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertEqual(result.selectedAtLeastOne, 0)
        XCTAssertEqual(result.selectionSource, .none)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
    }

    func testExplicitAutomaticEmptySelectionReportsRecommendationShortages() {
        var profile = StudentProfile.sample
        profile.requestedLikelyCount = 2
        profile.requestedTargetCount = 3
        profile.requestedReachCount = 4

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: [], selectionSource: .automatic)

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(result.selectedAtLeastOne, 0)
        XCTAssertTrue(result.recommendationWarnings.contains("保底档可推荐学校不足：请求 2 所，当前找到 0 所。"))
        XCTAssertTrue(result.recommendationWarnings.contains("目标档可推荐学校不足：请求 3 所，当前找到 0 所。"))
        XCTAssertTrue(result.recommendationWarnings.contains("争取档可推荐学校不足：请求 4 所，当前找到 0 所。"))
    }

    func testAutoRecommendationHonorsReachTargetLikelyCountsWhenAvailable() {
        let profile = StudentProfile.sample
        let recommended = engine.recommendedColleges(for: profile, reachCount: 2, targetCount: 2, likelyCount: 1)
        let results = recommended.map { engine.chance(for: $0, profile: profile) }
        let allResults = AdmissionsSeedData.colleges.map { engine.chance(for: $0, profile: profile) }.filter(\.gateResult.passed)

        XCTAssertEqual(Set(recommended.map(\.id)).count, recommended.count)
        XCTAssertLessThanOrEqual(recommended.count, 5)

        if allResults.filter({ $0.bucket == .likely }).count >= 1 {
            XCTAssertEqual(results.filter { $0.bucket == .likely }.count, 1)
        }
        if allResults.filter({ $0.bucket == .target }).count >= 2 {
            XCTAssertEqual(results.filter { $0.bucket == .target }.count, 2)
        }
        if allResults.filter({ $0.bucket == .reach }).count >= 2 {
            XCTAssertEqual(results.filter { $0.bucket == .reach }.count, 2)
        }
    }

    func testRecommendationBucketsUseConservativePlanningThresholds() {
        let results = AdmissionsSeedData.colleges.map { engine.chance(for: $0, profile: .sample) }

        XCTAssertTrue(results.allSatisfy { result in
            switch result.bucket {
            case .blocked:
                result.adjustedProbability == 0
            case .reach:
                result.adjustedProbability > 0 && result.adjustedProbability < 0.20
            case .target:
                result.adjustedProbability >= 0.20 && result.adjustedProbability < 0.60
            case .likely:
                result.adjustedProbability >= 0.60
            }
        })
    }

    func testPortfolioDisclosesRecommendationBucketShortages() {
        var profile = StudentProfile.sample
        profile.requestedLikelyCount = 10
        profile.requestedTargetCount = 12
        profile.requestedReachCount = 12

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: Set(engine.recommendedColleges(for: profile, reachCount: 12, targetCount: 12, likelyCount: 10).map(\.id)),
            selectionSource: .automatic
        )
        let recommendedResults = result.recommendedSchools.map { engine.chance(for: $0, profile: profile) }

        XCTAssertFalse(result.recommendationWarnings.isEmpty)
        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(result.recommendedSchools.count, Set(result.recommendedSchools.map(\.id)).count)
        XCTAssertLessThanOrEqual(recommendedResults.filter { $0.bucket == .likely }.count, profile.requestedLikelyCount)
        XCTAssertLessThanOrEqual(recommendedResults.filter { $0.bucket == .target }.count, profile.requestedTargetCount)
        XCTAssertLessThanOrEqual(recommendedResults.filter { $0.bucket == .reach }.count, profile.requestedReachCount)
    }

    func testManualSelectionDoesNotShowAutoRecommendationWarnings() {
        var profile = StudentProfile.sample
        profile.requestedLikelyCount = 10
        profile.requestedTargetCount = 12
        profile.requestedReachCount = 12

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)

        XCTAssertEqual(result.selectionSource, .manual)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
        XCTAssertTrue(ReportService.makeReport(result: result).contains("当前为手动选校，未触发自动推荐缺口判断"))
        XCTAssertFalse(ReportService.makeReport(result: result).contains("自动推荐三档数量可满足当前请求"))
    }

    func testAutomaticSelectionIsOnlySourceThatCarriesRecommendedSchools() {
        let manual = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let none = engine.evaluate(profile: .sample, selectedCollegeIDs: [], selectionSource: .none)
        let automaticIDs = Set(engine.recommendedColleges(for: .sample, reachCount: 1, targetCount: 1, likelyCount: 0).map(\.id))
        var profile = StudentProfile.sample
        profile.requestedReachCount = 1
        profile.requestedTargetCount = 1
        profile.requestedLikelyCount = 0
        let automatic = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)

        XCTAssertTrue(manual.recommendedSchools.isEmpty)
        XCTAssertTrue(none.recommendedSchools.isEmpty)
        XCTAssertFalse(automatic.recommendedSchools.isEmpty)
        XCTAssertEqual(Set(automatic.recommendedSchools.map(\.id)), automaticIDs)
    }

    func testAutomaticSelectionCarriesCurrentPortfolioWithoutRecommendingAgain() {
        var profile = StudentProfile.sample
        profile.requestedLikelyCount = 3
        profile.requestedTargetCount = 5
        profile.requestedReachCount = 4

        let selectedIDs: Set<String> = ["bu"]
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selectedIDs, selectionSource: .automatic)

        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(Set(result.schoolResults.map(\.college.id)), selectedIDs)
        XCTAssertEqual(Set(result.recommendedSchools.map(\.id)), selectedIDs)
    }

    func testChinaCapacityUsesApplicationRoundSpecificCount() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var rdProfile = strongChineseInternationalProfile
        rdProfile.round = .regularDecision
        rdProfile.testOptional = false
        rdProfile.sat = 1580

        var edProfile = rdProfile
        edProfile.round = .earlyDecision

        let rd = engine.chance(for: yale, profile: rdProfile)
        let ed = engine.chance(for: yale, profile: edProfile)

        XCTAssertLessThanOrEqual(rd.adjustedProbability, 0.025)
        XCTAssertGreaterThan(ed.adjustedProbability, rd.adjustedProbability)
        XCTAssertTrue(rd.warnings.contains { $0.contains("当前申请轮次中国学生录取容量很小") })
    }

    func testNeedBlindAidDoesNotChangeAidDelta() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var noAid = strongChineseInternationalProfile
        noAid.needsAid = false

        var needsAid = noAid
        needsAid.needsAid = true

        let noAidFactor = engine.chance(for: yale, profile: noAid).factors.first { $0.label == "资助需求" }
        let needsAidFactor = engine.chance(for: yale, profile: needsAid).factors.first { $0.label == "资助需求" }

        XCTAssertEqual(noAidFactor?.value, 0)
        XCTAssertEqual(needsAidFactor?.value, 0)
        XCTAssertTrue(needsAidFactor?.detail.contains("need-blind") == true)
    }

    func testNeedAwareInternationalAidIsDisclosedSeparately() {
        let harvard = AdmissionsSeedData.colleges.first { $0.id == "harvard" }!
        var noAid = strongChineseInternationalProfile
        noAid.needsAid = false

        var needsAid = noAid
        needsAid.needsAid = true

        let noAidResult = engine.chance(for: harvard, profile: noAid)
        let needsAidResult = engine.chance(for: harvard, profile: needsAid)
        let aidFactor = needsAidResult.factors.first { $0.label == "资助需求" }

        XCTAssertEqual(noAidResult.factors.first { $0.label == "资助需求" }?.value, 0)
        XCTAssertLessThan(aidFactor?.value ?? 0, 0)
        XCTAssertTrue(aidFactor?.detail.contains("need-aware") == true)
        XCTAssertTrue(needsAidResult.warnings.contains { $0.contains("need-aware") })
    }

    func testDomesticAidDoesNotUseInternationalAidPolicy() {
        let harvard = AdmissionsSeedData.colleges.first { $0.id == "harvard" }!
        var profile = StudentProfile.sample
        profile.applicantStatus = .usCitizenDomestic
        profile.major = .humanities
        profile.needsAid = true

        let result = engine.chance(for: harvard, profile: profile)
        let aidFactor = result.factors.first { $0.label == "资助需求" }

        XCTAssertEqual(aidFactor?.value, 0)
        XCTAssertTrue(aidFactor?.detail.contains("不使用国际生资助政策修正") == true)
        XCTAssertFalse(result.warnings.contains { $0.contains("need-aware") })
    }

    func testSubmittedStrongTestScoreBeatsTestOptionalAtSelectiveSchool() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var optional = strongChineseInternationalProfile
        optional.testOptional = true
        optional.sat = nil
        optional.act = nil

        var submitted = optional
        submitted.testOptional = false
        submitted.sat = 1580

        let optionalFit = engine.chance(for: yale, profile: optional).factors.first { $0.label == "目标校学术匹配" }?.value ?? 0
        let submittedFit = engine.chance(for: yale, profile: submitted).factors.first { $0.label == "目标校学术匹配" }?.value ?? 0

        XCTAssertGreaterThan(submittedFit, optionalFit)
    }

    func testTestOptionalIgnoresResidualSatActScoresForBenchmarkFit() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var cleanOptional = strongChineseInternationalProfile
        cleanOptional.testOptional = true
        cleanOptional.sat = nil
        cleanOptional.act = nil

        var residualScores = cleanOptional
        residualScores.sat = 1580
        residualScores.act = 36

        let clean = engine.chance(for: yale, profile: cleanOptional)
        let residual = engine.chance(for: yale, profile: residualScores)
        let cleanFit = clean.factors.first { $0.label == "目标校学术匹配" }?.value ?? 0
        let residualFit = residual.factors.first { $0.label == "目标校学术匹配" }?.value ?? 0

        XCTAssertEqual(engine.studentScore(cleanOptional, college: yale), engine.studentScore(residualScores, college: yale), accuracy: 0.0001)
        XCTAssertEqual(cleanFit, residualFit, accuracy: 0.0001)
        XCTAssertTrue(residual.warnings.contains { $0.contains("已选择不提交标化") })
    }

    func testUCTestFreePolicyIgnoresSatActForProbability() {
        let ucla = AdmissionsSeedData.colleges.first { $0.id == "ucla" }!
        var noScore = strongChineseInternationalProfile
        noScore.testOptional = true
        noScore.sat = nil
        noScore.act = nil

        var highScore = noScore
        highScore.testOptional = false
        highScore.sat = 1580
        highScore.act = 36

        let noScoreResult = engine.chance(for: ucla, profile: noScore)
        let highScoreResult = engine.chance(for: ucla, profile: highScore)

        XCTAssertTrue(noScoreResult.gateResult.passed)
        XCTAssertTrue(highScoreResult.gateResult.passed)
        XCTAssertEqual(noScoreResult.adjustedProbability, highScoreResult.adjustedProbability, accuracy: 0.0001)
        XCTAssertEqual(engine.studentScore(noScore, college: ucla), engine.studentScore(highScore, college: ucla), accuracy: 0.0001)
        XCTAssertTrue(highScoreResult.factors.contains { $0.label == "学生画像" && $0.detail.contains("test-free") })
        XCTAssertTrue(highScoreResult.factors.contains { $0.label == "目标校学术匹配" && $0.detail.contains("test-free") })
        XCTAssertTrue(highScoreResult.warnings.contains { $0.contains("SAT/ACT 不进入录取概率") })
    }

    func testUCCampusesBlockEarlyRounds() {
        let ucla = AdmissionsSeedData.colleges.first { $0.id == "ucla" }!
        var profile = strongChineseInternationalProfile
        profile.round = .earlyDecision

        let result = engine.chance(for: ucla, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertTrue(result.gateResult.failedRules.contains { $0.type == .round && $0.isOfficial })
    }

    func testEarlyRoundDoesNotReceiveGenericBoostWithoutSchoolPolicyData() {
        let harvard = AdmissionsSeedData.colleges.first { $0.id == "harvard" }!
        var rdProfile = StudentProfile.sample
        rdProfile.applicantStatus = .usCitizenDomestic
        rdProfile.major = .humanities
        rdProfile.round = .regularDecision

        var edProfile = rdProfile
        edProfile.round = .earlyDecision

        let rd = engine.chance(for: harvard, profile: rdProfile)
        let ed = engine.chance(for: harvard, profile: edProfile)
        let rdRound = rd.factors.first { $0.label == "申请轮次" }
        let edRound = ed.factors.first { $0.label == "申请轮次" }

        XCTAssertEqual(rdRound?.value, 0)
        XCTAssertEqual(edRound?.value, 0)
        XCTAssertEqual(rd.adjustedProbability, ed.adjustedProbability, accuracy: 0.0001)
        XCTAssertTrue(edRound?.detail.contains("缺少学校级") == true)
        XCTAssertTrue(ed.warnings.contains { $0.contains("缺少学校级 EA/ED 轮次政策数据") })
    }

    func testMITRoundPolicyAllowsEAAndRDBlocksEDWithoutGenericBoost() {
        let mit = AdmissionsSeedData.colleges.first { $0.id == "mit" }!
        var rdProfile = StudentProfile.sample
        rdProfile.applicantStatus = .usCitizenDomestic
        rdProfile.major = .humanities
        rdProfile.round = .regularDecision

        var eaProfile = rdProfile
        eaProfile.round = .earlyAction

        var edProfile = rdProfile
        edProfile.round = .earlyDecision

        let rd = engine.chance(for: mit, profile: rdProfile)
        let ea = engine.chance(for: mit, profile: eaProfile)
        let ed = engine.chance(for: mit, profile: edProfile)
        let eaRound = ea.factors.first { $0.label == "申请轮次" }

        XCTAssertTrue(rd.gateResult.passed)
        XCTAssertTrue(ea.gateResult.passed)
        XCTAssertEqual(eaRound?.value, 0)
        XCTAssertEqual(rd.adjustedProbability, ea.adjustedProbability, accuracy: 0.0001)
        XCTAssertTrue(eaRound?.detail.contains("没有明确概率加分") == true)
        XCTAssertEqual(ed.adjustedProbability, 0)
        XCTAssertTrue(ed.gateResult.failedRules.contains { $0.type == .round && $0.isOfficial })
    }

    func testCaltechRestrictiveEarlyActionDoesNotCreateBoostAndBlocksED() {
        let caltech = AdmissionsSeedData.colleges.first { $0.id == "caltech" }!
        var rdProfile = StudentProfile.sample
        rdProfile.applicantStatus = .usCitizenDomestic
        rdProfile.major = .humanities
        rdProfile.sat = 1560
        rdProfile.round = .regularDecision

        var eaProfile = rdProfile
        eaProfile.round = .earlyAction

        var edProfile = rdProfile
        edProfile.round = .earlyDecision

        let rd = engine.chance(for: caltech, profile: rdProfile)
        let ea = engine.chance(for: caltech, profile: eaProfile)
        let ed = engine.chance(for: caltech, profile: edProfile)
        let eaRound = ea.factors.first { $0.label == "申请轮次" }

        XCTAssertTrue(rd.gateResult.passed)
        XCTAssertTrue(ea.gateResult.passed)
        XCTAssertEqual(eaRound?.value, 0)
        XCTAssertEqual(rd.adjustedProbability, ea.adjustedProbability, accuracy: 0.0001)
        XCTAssertTrue(eaRound?.detail.contains("没有明确概率加分") == true)
        XCTAssertEqual(ed.adjustedProbability, 0)
        XCTAssertTrue(ed.gateResult.failedRules.contains { $0.type == .round && $0.isOfficial })
    }

    func testACTConcordanceUsesOfficialMidpointsForGateChecks() {
        let georgetown = AdmissionsSeedData.colleges.first { $0.id == "georgetown" }!
        var act32 = StudentProfile.sample
        act32.major = .humanities
        act32.sat = nil
        act32.act = 32
        act32.testOptional = false
        act32.toefl = 110

        var act33 = act32
        act33.act = 33

        let lower = engine.chance(for: georgetown, profile: act32)
        let higher = engine.chance(for: georgetown, profile: act33)

        XCTAssertEqual(lower.adjustedProbability, 0)
        XCTAssertTrue(lower.gateResult.failedRules.contains { $0.type == .standardizedTest })
        XCTAssertTrue(higher.gateResult.passed)
    }

    func testBestSubmittedTestingEquivalentSatisfiesGateAndBenchmark() {
        let georgetown = AdmissionsSeedData.colleges.first { $0.id == "georgetown" }!
        var profile = StudentProfile.sample
        profile.major = .humanities
        profile.sat = 1400
        profile.act = 35
        profile.testOptional = false
        profile.toefl = 110

        let result = engine.chance(for: georgetown, profile: profile)
        let fit = result.factors.first { $0.label == "目标校学术匹配" }

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertFalse(result.gateResult.failedRules.contains { $0.type == .standardizedTest })
        XCTAssertTrue(fit?.detail.contains("SAT等效 1540") == true)
    }

    func testDatasetIsAdmissionSightScoped() {
        let source = AdmissionsSeedData.admissionsSightURL.absoluteString
        XCTAssertFalse(AdmissionsSeedData.colleges.isEmpty)
        XCTAssertTrue(AdmissionsSeedData.colleges.allSatisfy { $0.sourceURL.absoluteString == source })
    }

    private var strongChineseInternationalProfile: StudentProfile {
        var profile = StudentProfile.sample
        profile.applicantStatus = .chineseInternational
        profile.gpaPercent = 96
        profile.classRankPercentile = 5
        profile.curriculum = .ap
        profile.rigor = 5
        profile.apCourseCount = 8
        profile.apAverageScore = 5.0
        profile.sat = nil
        profile.act = nil
        profile.testOptional = true
        profile.toefl = 110
        profile.ielts = nil
        profile.activities = 4
        profile.research = 3
        profile.honors = 4
        profile.essay = 4
        profile.recommendations = 4
        profile.highSchoolID = "shsid"
        profile.major = .socialScience
        profile.round = .regularDecision
        profile.needsAid = false
        profile.hasPortfolio = false
        return profile
    }
}
