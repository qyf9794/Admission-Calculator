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
    }

    func testEmptySelectionDoesNotImplicitlyAutoRecommendSchools() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: [])

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertEqual(result.selectedAtLeastOne, 0)
        XCTAssertEqual(result.selectionSource, .none)
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
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
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

    func testNeedBlindAidDoesNotChangeStrategyDelta() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var noAid = strongChineseInternationalProfile
        noAid.needsAid = false

        var needsAid = noAid
        needsAid.needsAid = true

        let noAidStrategy = engine.chance(for: yale, profile: noAid).factors.first { $0.label == "申请策略" }?.value
        let needsAidStrategy = engine.chance(for: yale, profile: needsAid).factors.first { $0.label == "申请策略" }?.value

        XCTAssertEqual(noAidStrategy, needsAidStrategy)
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

    func testUCCampusesBlockEarlyRounds() {
        let ucla = AdmissionsSeedData.colleges.first { $0.id == "ucla" }!
        var profile = strongChineseInternationalProfile
        profile.round = .earlyDecision

        let result = engine.chance(for: ucla, profile: profile)

        XCTAssertEqual(result.adjustedProbability, 0)
        XCTAssertTrue(result.gateResult.failedRules.contains { $0.type == .round && $0.isOfficial })
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
