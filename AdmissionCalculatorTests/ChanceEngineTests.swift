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

    func testEngineUsesConservativeHighSchoolFallbackWhenContextSeedIsMissing() {
        let engineWithoutHighSchools = ChanceEngine(highSchools: [])
        var profile = StudentProfile.sample
        profile.highSchoolID = "missing-school-context"
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!

        let result = engineWithoutHighSchools.chance(for: bu, profile: profile)
        let portfolio = engineWithoutHighSchools.evaluate(profile: profile, selectedCollegeIDs: Set([bu.id]))

        XCTAssertTrue(result.gateResult.passed)
        XCTAssertGreaterThan(result.adjustedProbability, 0)
        XCTAssertEqual(portfolio.schoolResults.count, 1)
        XCTAssertTrue(result.factors.contains { factor in
            factor.label == "顶尖高中强队列" &&
                factor.detail.contains("未触发")
        })
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
        XCTAssertEqual(prompts.first { $0.id == "english-proof" }?.impact, .gate)
        XCTAssertEqual(prompts.first { $0.id == "standardized-test" }?.impact, .gate)
        XCTAssertEqual(prompts.first { $0.id == "high-school-context" }?.impact, .confidence)
        XCTAssertEqual(prompts.first { $0.id == "ap-evidence" }?.impact, .probability)
        XCTAssertEqual(prompts.first { $0.id == "selected-schools" }?.impact, .portfolio)
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
        XCTAssertTrue(report.contains("选择学校组合（选校策略）"))
        XCTAssertTrue(report.contains("补充 TOEFL 或 IELTS（硬门槛）"))
        XCTAssertTrue(report.contains("补充 SAT/ACT 或选择不提交（硬门槛）"))
        XCTAssertTrue(report.contains("补充 AP 课程证据（概率计算）"))
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

    func testZeroGpaDoesNotReceiveArtificialReadinessFloor() {
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        var zeroGPA = StudentProfile.sample
        zeroGPA.major = .humanities
        zeroGPA.gradeScale = .fourPoint
        zeroGPA.gpaFourPoint = 0

        var twoPointGPA = zeroGPA
        twoPointGPA.gpaFourPoint = 2.0

        XCTAssertLessThan(engine.studentScore(zeroGPA, college: bu), engine.studentScore(twoPointGPA, college: bu) - 5)
        XCTAssertLessThan(
            engine.chance(for: bu, profile: zeroGPA).adjustedProbability,
            engine.chance(for: bu, profile: twoPointGPA).adjustedProbability
        )
    }

    func testLetterGradesDistinguishCDBands() {
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        var cGrade = StudentProfile.sample
        cGrade.major = .humanities
        cGrade.gradeScale = .letter
        cGrade.letterGrade = .c

        var dGrade = cGrade
        dGrade.letterGrade = .d

        var fGrade = cGrade
        fGrade.letterGrade = .f

        XCTAssertFalse(LetterGradeBand.allCases.contains(.cOrBelow))
        XCTAssertGreaterThan(engine.studentScore(cGrade, college: bu), engine.studentScore(dGrade, college: bu))
        XCTAssertGreaterThan(engine.studentScore(dGrade, college: bu), engine.studentScore(fGrade, college: bu))
        XCTAssertGreaterThan(
            engine.chance(for: bu, profile: cGrade).adjustedProbability,
            engine.chance(for: bu, profile: dGrade).adjustedProbability
        )
        XCTAssertGreaterThan(
            engine.chance(for: bu, profile: dGrade).adjustedProbability,
            engine.chance(for: bu, profile: fGrade).adjustedProbability
        )
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

    func testALevelSubjectCountsAreCappedAtFive() {
        var fiveBSubjects = StudentProfile.sample
        fiveBSubjects.major = .humanities
        fiveBSubjects.curriculum = .alevel
        fiveBSubjects.aLevelAStarCount = 0
        fiveBSubjects.aLevelACount = 0
        fiveBSubjects.aLevelBCount = 5

        var overflowBSubjects = fiveBSubjects
        overflowBSubjects.aLevelBCount = 10

        XCTAssertEqual(engine.studentScore(overflowBSubjects), engine.studentScore(fiveBSubjects), accuracy: 0.0001)
        XCTAssertEqual(overflowBSubjects.cappedALevelGradeCounts.b, 5)
    }

    func testALevelOverflowIsDisclosedInWarnings() {
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        var profile = StudentProfile.sample
        profile.curriculum = .alevel
        profile.aLevelAStarCount = 3
        profile.aLevelACount = 3
        profile.aLevelBCount = 3

        let result = engine.chance(for: bu, profile: profile)

        XCTAssertTrue(result.warnings.contains { $0.contains("A-Level A*/A/B 科目合计超过") })
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

    func testManualSelectionHasNoArtificialCollegeCountCap() {
        let selected = Set(AdmissionsSeedData.colleges.map(\.id))
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: selected, selectionSource: .manual)

        XCTAssertEqual(result.selectionSource, .manual)
        XCTAssertEqual(result.schoolResults.count, selected.count)
        XCTAssertEqual(result.calculatedCollegeIDs, selected)
    }

    func testTierProbabilitiesAreScopedToSelectedSchools() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]))

        XCTAssertEqual(result.t10AtLeastOne, 0)
        XCTAssertEqual(result.t30AtLeastOne, 0)
        XCTAssertEqual(result.liberalArtsT10AtLeastOne, 0)
        XCTAssertEqual(result.liberalArtsT30AtLeastOne, 0)
        XCTAssertEqual(result.schoolResults.map(\.college.id), ["bu"])
        XCTAssertEqual(result.selectedBucketCounts.total, 1)
        XCTAssertEqual(result.profileSnapshot, .sample)
        XCTAssertEqual(result.selectedCollegeIDs, Set(["bu"]))
        XCTAssertTrue(result.selectionWarnings.isEmpty)
    }

    func testLiberalArtsTierProbabilitiesContributeToOverallPortfolio() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["williams", "barnard", "bu"]))
        let williams = result.schoolResults.first { $0.college.id == "williams" }!
        let barnard = result.schoolResults.first { $0.college.id == "barnard" }!

        XCTAssertEqual(williams.college.category, .liberalArtsCollege)
        XCTAssertEqual(barnard.college.category, .liberalArtsCollege)
        XCTAssertGreaterThan(result.liberalArtsT10AtLeastOne, 0)
        XCTAssertGreaterThanOrEqual(result.liberalArtsT30AtLeastOne, result.liberalArtsT10AtLeastOne)
        XCTAssertGreaterThanOrEqual(result.selectedAtLeastOne, result.liberalArtsT30AtLeastOne)
        XCTAssertEqual(result.t10AtLeastOne, 0)
    }

    func testEliteInternationalSchoolTopDecilePortfolioApproachesNinetyForFifteenNonT10T30Schools() {
        var profile = StudentProfile.sample
        profile.applicantStatus = .chineseInternational
        profile.highSchoolID = "shsid"
        profile.classRankPercentile = 10
        profile.gpaPercent = 96
        profile.curriculum = .ap
        profile.apCourseCount = 8
        profile.apAverageScore = 5
        profile.rigor = 5
        profile.sat = 1550
        profile.act = nil
        profile.testOptional = false
        profile.toefl = 112
        profile.major = .socialScience
        profile.needsAid = false
        profile.activities = 4
        profile.research = 4
        profile.honors = 4
        profile.essay = 4
        profile.recommendations = 4

        let selected = Set(AdmissionsSeedData.colleges
            .filter { $0.category == .nationalUniversity && $0.rank > 10 && $0.rank <= 30 }
            .prefix(15)
            .map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selected)

        XCTAssertEqual(result.schoolResults.count, 15)
        XCTAssertEqual(result.t10AtLeastOne, 0)
        XCTAssertEqual(result.t11T30AtLeastOne, result.t30AtLeastOne, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(result.t11T30AtLeastOne, 0.90)
        XCTAssertGreaterThanOrEqual(result.t30AtLeastOne, 0.90)
        XCTAssertGreaterThanOrEqual(result.selectedAtLeastOne, result.t30AtLeastOne)
    }

    func testEliteTopCohortDoesNotLiftT10CapacityCap() {
        let yale = AdmissionsSeedData.colleges.first { $0.id == "yale" }!
        var profile = strongChineseInternationalProfile
        profile.highSchoolID = "shsid"
        profile.classRankPercentile = 5
        profile.sat = 1580
        profile.testOptional = false
        profile.major = .socialScience
        profile.needsAid = false

        let result = engine.chance(for: yale, profile: profile)

        XCTAssertLessThanOrEqual(result.adjustedProbability, 0.025)
        XCTAssertTrue(result.factors.contains { $0.label == "顶尖高中强队列" })
    }

    func testEliteTopCohortCalibrationDoesNotLiftLiberalArtsColleges() {
        let barnard = AdmissionsSeedData.colleges.first { $0.id == "barnard" }!
        var profile = strongChineseInternationalProfile
        profile.highSchoolID = "shsid"
        profile.classRankPercentile = 5
        profile.sat = 1580
        profile.testOptional = false
        profile.major = .socialScience
        profile.needsAid = false
        profile.includeLiberalArtsColleges = true

        let result = engine.chance(for: barnard, profile: profile)
        let factor = result.factors.first { $0.label == "顶尖高中强队列" }

        XCTAssertEqual(factor?.value, 0)
        XCTAssertTrue(factor?.detail.contains("未触发") == true)
    }

    func testCombinedAtLeastOneCorrelatesCrossCategoryT10Schools() {
        let nationalUniversityT10 = syntheticChanceResult(id: "nu_t10", name: "NU T10", rank: 1, probability: 0.50)
        let liberalArtsT10 = syntheticChanceResult(
            id: "lac_t10",
            name: "LAC T10",
            category: .liberalArtsCollege,
            rank: 2,
            probability: 0.50
        )
        let independent = 1 - (1 - nationalUniversityT10.adjustedProbability) * (1 - liberalArtsT10.adjustedProbability)
        let correlated = engine.atLeastOneProbability([nationalUniversityT10, liberalArtsT10])

        XCTAssertEqual(correlated, 1 - (1 - 0.50) * (1 - 0.50 * 0.78), accuracy: 0.0001)
        XCTAssertLessThan(correlated, independent)
    }

    func testRecommendationDiscountsCrossCategoryT10SchoolsAsSameCorrelationTier() {
        let nationalUniversityT10 = syntheticChanceResult(id: "recommend_nu_t10", name: "Recommend NU T10", rank: 1, probability: 0.40)
        let liberalArtsT10 = syntheticChanceResult(
            id: "recommend_lac_t10",
            name: "Recommend LAC T10",
            category: .liberalArtsCollege,
            rank: 2,
            probability: 0.40
        )

        let steps = engine.recommendationSteps(for: [nationalUniversityT10, liberalArtsT10], count: 2)

        XCTAssertEqual(steps.map { $0.result.college.id }, [nationalUniversityT10.college.id, liberalArtsT10.college.id])
        XCTAssertEqual(steps[0].sameTierDiscount, 1, accuracy: 0.0001)
        XCTAssertEqual(steps[1].sameTierDiscount, 0.78, accuracy: 0.0001)
        XCTAssertLessThan(steps[1].marginalExpectedValue, steps[1].baseExpectedValue)
    }

    func testLiberalArtsToggleExcludesLACsFromManualPortfolioProbability() {
        var profile = StudentProfile.sample
        profile.includeLiberalArtsColleges = false

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: Set(["williams", "barnard", "bu"]))

        XCTAssertEqual(result.schoolResults.map(\.college.id), ["bu"])
        XCTAssertEqual(result.liberalArtsT10AtLeastOne, 0)
        XCTAssertEqual(result.liberalArtsT30AtLeastOne, 0)
        XCTAssertEqual(result.calculatedCollegeIDs, Set(["bu"]))
        XCTAssertTrue(result.selectionWarnings.contains { $0.contains("已关闭文理学院选项") })
    }

    func testUnknownSelectedCollegeIDsAreDisclosedAndExcluded() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "outside_dataset"]))

        XCTAssertEqual(result.schoolResults.map(\.college.id), ["bu"])
        XCTAssertEqual(result.selectedBucketCounts.total, 1)
        XCTAssertEqual(result.selectedCollegeIDs, Set(["bu", "outside_dataset"]))
        XCTAssertEqual(result.calculatedCollegeIDs, Set(["bu"]))
        XCTAssertTrue(result.selectionWarnings.contains { $0.contains("不在已审核 v1 数据集内") })
    }

    func testOnlyUnknownSelectedCollegeIDsStillPromptForValidSelection() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["outside_dataset"]), selectionSource: .manual)
        let prompts = result.profileSnapshot.completionPrompts(selectedCollegeIDs: result.calculatedCollegeIDs)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertTrue(result.calculatedCollegeIDs.isEmpty)
        XCTAssertTrue(result.selectionWarnings.contains { $0.contains("不在已审核 v1 数据集内") })
        XCTAssertTrue(prompts.contains { $0.id == "selected-schools" })
        XCTAssertTrue(report.contains("选择学校组合（选校策略）"))
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

    func testVeryLowClassRankContinuesToLowerReadinessAndProbability() {
        let bu = AdmissionsSeedData.colleges.first { $0.id == "bu" }!
        var lowerRank = StudentProfile.sample
        lowerRank.major = .humanities
        lowerRank.classRankPercentile = 80
        lowerRank.sat = 1350

        var lowestRank = lowerRank
        lowestRank.classRankPercentile = 100

        XCTAssertLessThan(engine.studentScore(lowestRank, college: bu), engine.studentScore(lowerRank, college: bu))
        XCTAssertLessThan(
            engine.chance(for: bu, profile: lowestRank).adjustedProbability,
            engine.chance(for: bu, profile: lowerRank).adjustedProbability
        )
    }

    func testEmptySelectionDoesNotImplicitlyAutoRecommendSchools() {
        let result = engine.evaluate(profile: .sample, selectedCollegeIDs: [])

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertEqual(result.selectedAtLeastOne, 0)
        XCTAssertEqual(result.selectionSource, .none)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
    }

    func testAutomaticSelectionDemotesAfterProfileEdit() {
        XCTAssertEqual(PortfolioSelectionSource.automatic.afterProfileEdit(selectedCollegeIDs: Set(["bu"])), .manual)
        XCTAssertEqual(PortfolioSelectionSource.automatic.afterProfileEdit(selectedCollegeIDs: []), .none)
        XCTAssertEqual(PortfolioSelectionSource.manual.afterProfileEdit(selectedCollegeIDs: Set(["bu"])), .manual)
        XCTAssertEqual(PortfolioSelectionSource.none.afterProfileEdit(selectedCollegeIDs: []), .none)
    }

    @MainActor
    func testStaleResultCannotUnlockNewReportPreview() {
        let purchaseState = ReportPurchaseState()

        XCTAssertTrue(purchaseState.canUnlockReport(isStale: false))
        XCTAssertFalse(purchaseState.canUnlockReport(isStale: true))

        purchaseState.unlockForPrototype()

        XCTAssertFalse(purchaseState.canUnlockReport(isStale: false))
    }

    func testExplicitAutomaticEmptySelectionReportsRecommendationShortages() {
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 9

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: [], selectionSource: .automatic)

        XCTAssertTrue(result.schoolResults.isEmpty)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(result.selectedAtLeastOne, 0)
        XCTAssertTrue(result.recommendationWarnings.contains("自动推荐数量不足：计划 9 所，当前生成 0 所。"))
    }

    func testAutoRecommendationHonorsRequestedTotalCountWhenAvailable() {
        let profile = StudentProfile.sample
        let recommended = engine.recommendedColleges(for: profile, count: 5)
        let allResults = AdmissionsSeedData.colleges.map { engine.chance(for: $0, profile: profile) }.filter(\.gateResult.passed)

        XCTAssertEqual(Set(recommended.map(\.id)).count, recommended.count)
        XCTAssertEqual(recommended.count, min(5, allResults.count))
    }

    func testAutoRecommendationHonorsLiberalArtsToggle() {
        var profile = StudentProfile.sample
        profile.includeLiberalArtsColleges = false

        let recommended = engine.recommendedColleges(for: profile, count: 12)

        XCTAssertFalse(recommended.isEmpty)
        XCTAssertTrue(recommended.allSatisfy { $0.category == .nationalUniversity })
    }

    func testAutoRecommendationStartsWithHighestExpectedValueSchool() {
        let profile = StudentProfile.sample
        let recommended = engine.recommendedColleges(for: profile, count: 1)
        let eligible = AdmissionsSeedData.colleges
            .map { engine.chance(for: $0, profile: profile) }
            .filter(\.gateResult.passed)
        let expectedBest = eligible.max { lhs, rhs in
            engine.recommendationExpectedValue(for: lhs) < engine.recommendationExpectedValue(for: rhs)
        }

        XCTAssertEqual(recommended.first?.id, expectedBest?.college.id)
    }

    func testAutoRecommendationCanPreferRankValueOverHigherRawProbability() {
        let highRankLowerRate = syntheticCollege(id: "high_rank_lower_rate", name: "High Rank Lower Rate", rank: 1, rate: 0.16)
        let lowRankHigherRate = syntheticCollege(id: "low_rank_higher_rate", name: "Low Rank Higher Rate", rank: 100, rate: 0.20)
        let syntheticEngine = ChanceEngine(
            colleges: [highRankLowerRate, lowRankHigherRate],
            gateRules: [],
            highSchools: AdmissionsSeedData.highSchools,
            internationalSignals: [],
            chinaAdmissionSignals: [],
            academicBenchmarks: []
        )
        var profile = StudentProfile.sample
        profile.applicantStatus = .usCitizenDomestic
        profile.major = .humanities
        profile.needsAid = false

        let highRankResult = syntheticEngine.chance(for: highRankLowerRate, profile: profile)
        let lowRankResult = syntheticEngine.chance(for: lowRankHigherRate, profile: profile)
        let recommended = syntheticEngine.recommendedColleges(for: profile, count: 1)

        XCTAssertGreaterThan(lowRankResult.adjustedProbability, highRankResult.adjustedProbability)
        XCTAssertGreaterThan(
            syntheticEngine.recommendationExpectedValue(for: highRankResult),
            syntheticEngine.recommendationExpectedValue(for: lowRankResult)
        )
        XCTAssertEqual(recommended.map(\.id), [highRankLowerRate.id])
    }

    func testRecommendationRankScoreRewardsHigherRankedSchools() {
        let williams = AdmissionsSeedData.colleges.first { $0.id == "williams" }!
        let lafayette = AdmissionsSeedData.colleges.first { $0.id == "lafayette" }!
        let princeton = AdmissionsSeedData.colleges.first { $0.id == "princeton" }!
        let caseWestern = AdmissionsSeedData.colleges.first { $0.id == "case" }!

        XCTAssertGreaterThan(engine.recommendationRankScore(for: williams), engine.recommendationRankScore(for: lafayette))
        XCTAssertGreaterThan(engine.recommendationRankScore(for: princeton), engine.recommendationRankScore(for: caseWestern))
    }

    func testRecommendationRankScoreUsesComparableFixedRankCurveAcrossCategories() {
        let nuRank20 = AdmissionsSeedData.colleges.first { $0.category == .nationalUniversity && $0.rank == 20 }!
        let nuRank30 = AdmissionsSeedData.colleges.first { $0.category == .nationalUniversity && $0.rank == 30 }!
        let lacRank30 = AdmissionsSeedData.colleges.first { $0.category == .liberalArtsCollege && $0.rank == 30 }!
        let topLAC = AdmissionsSeedData.colleges.first { $0.id == "williams" }!
        let lacRank10 = AdmissionsSeedData.colleges.first { $0.category == .liberalArtsCollege && $0.rank == 10 }!

        XCTAssertEqual(engine.recommendationRankScore(for: topLAC), engine.recommendationRankScore(for: nuRank20), accuracy: 0.0001)
        XCTAssertEqual(engine.recommendationRankScore(for: lacRank10), engine.recommendationRankScore(for: nuRank30), accuracy: 0.0001)
        XCTAssertGreaterThan(engine.recommendationRankScore(for: lacRank30), 49)
        XCTAssertLessThan(engine.recommendationRankScore(for: lacRank30), engine.recommendationRankScore(for: nuRank30))
        XCTAssertGreaterThan(engine.recommendationRankScore(for: topLAC), engine.recommendationRankScore(for: lacRank30))
    }

    func testAutoRecommendationImprovesOrMatchesGreedyExpectedBestOfferSlots() {
        var profile = strongChineseInternationalProfile
        profile.includeLiberalArtsColleges = true
        profile.requestedSchoolCount = 12

        let recommendedIDs = engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id)
        let eligible = AdmissionsSeedData.colleges
            .map { engine.chance(for: $0, profile: profile) }
            .filter(\.gateResult.passed)
        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: profile.requestedSchoolCount)
        let optimizedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)

        XCTAssertEqual(recommendedIDs.count, min(profile.requestedSchoolCount, eligible.count))
        XCTAssertEqual(recommendedIDs, optimizedSteps.map { $0.result.college.id })
        XCTAssertGreaterThanOrEqual(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps) + 0.0001,
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testAutoRecommendationLargeRequestedCountReturnsEligibleSchoolsWithoutDuplicates() {
        var profile = strongChineseInternationalProfile
        profile.includeLiberalArtsColleges = true
        profile.requestedSchoolCount = 500
        let eligibleCount = AdmissionsSeedData.colleges
            .filter { profile.includeLiberalArtsColleges || $0.category != .liberalArtsCollege }
            .map { engine.chance(for: $0, profile: profile) }
            .filter(\.gateResult.passed)
            .count

        let recommended = engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount)

        XCTAssertEqual(recommended.count, eligibleCount)
        XCTAssertEqual(Set(recommended.map(\.id)).count, eligibleCount)
    }

    func testAutoRecommendationDoesNotReplaceOnEqualExpectedValue() {
        let anchor = syntheticChanceResult(id: "anchor", name: "Anchor", rank: 1, probability: 0.40)
        let choiceA = syntheticChanceResult(id: "choice_a", name: "Choice A", rank: 30, probability: 0.20)
        let choiceB = syntheticChanceResult(id: "choice_b", name: "Choice B", rank: 30, probability: 0.20)
        let steps = engine.recommendationSteps(for: [anchor, choiceA, choiceB], count: 2)
        let greedySteps = greedyExpectedBestOfferSteps(from: [anchor, choiceA, choiceB], count: 2)

        XCTAssertEqual(steps.map { $0.result.college.id }, greedySteps.map { $0.result.college.id })
        XCTAssertEqual(engine.recommendationBestOfferExpectedValue(for: steps), engine.recommendationBestOfferExpectedValue(for: greedySteps), accuracy: 0.0001)
    }

    func testAutoRecommendationReplacesGreedySlotWhenExpectedBestOfferImproves() {
        let lowChanceTopRank = syntheticChanceResult(id: "low_chance_top_rank", name: "Low Chance Top Rank", rank: 1, probability: 0.03)
        let topRank = syntheticChanceResult(id: "top_rank", name: "Top Rank", rank: 1, probability: 0.40)
        let highProbabilityT10 = syntheticChanceResult(id: "high_probability_t10", name: "High Probability T10", rank: 8, probability: 0.45)
        let t30Target = syntheticChanceResult(id: "t30_target", name: "T30 Target", rank: 12, probability: 0.40)
        let eligible = [lowChanceTopRank, topRank, highProbabilityT10, t30Target]

        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: 2)
        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 2)

        XCTAssertEqual(greedySteps.map { $0.result.college.id }, [highProbabilityT10.college.id, t30Target.college.id])
        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, [topRank.college.id, t30Target.college.id])
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testFastAutoRecommendationReplacesGreedySlotAndNormalizesFinalOrder() {
        let lowChanceTopRank = syntheticChanceResult(id: "fast_low_chance_top_rank", name: "Fast Low Chance Top Rank", rank: 1, probability: 0.03)
        let topRank = syntheticChanceResult(id: "fast_top_rank", name: "Fast Top Rank", rank: 1, probability: 0.40)
        let highProbabilityT10 = syntheticChanceResult(id: "fast_high_probability_t10", name: "Fast High Probability T10", rank: 8, probability: 0.45)
        let t30Target = syntheticChanceResult(id: "fast_t30_target", name: "Fast T30 Target", rank: 12, probability: 0.40)
        let fillers = (1...9).map { index in
            syntheticChanceResult(
                id: "fast_filler_\(index)",
                name: "Fast Filler \(index)",
                rank: 60 + index,
                probability: 0.01
            )
        }
        let eligible = [lowChanceTopRank, topRank, highProbabilityT10, t30Target] + fillers

        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: 2)
        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 2)
        let normalizedSteps = greedyExpectedBestOfferSteps(from: optimizedSteps.map(\.result), count: optimizedSteps.count)

        XCTAssertEqual(eligible.count, 13)
        XCTAssertEqual(greedySteps.map { $0.result.college.id }, [highProbabilityT10.college.id, t30Target.college.id])
        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, [topRank.college.id, t30Target.college.id])
        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, normalizedSteps.map { $0.result.college.id })
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testFastAutoRecommendationUsesRankPriorityOrderWhenItImprovesBestOfferValue() {
        let eligible = [
            syntheticChanceResult(id: "rank_priority_0", name: "Rank Priority 0", rank: 4, probability: 0.5948992002010346),
            syntheticChanceResult(id: "rank_priority_1", name: "Rank Priority 1", rank: 15, probability: 0.12249560236930847),
            syntheticChanceResult(id: "rank_priority_2", name: "Rank Priority 2", rank: 68, probability: 0.5110824394226074),
            syntheticChanceResult(id: "rank_priority_3", name: "Rank Priority 3", rank: 1, probability: 0.5941802944242954),
            syntheticChanceResult(id: "rank_priority_4", name: "Rank Priority 4", rank: 31, probability: 0.19314783096313476),
            syntheticChanceResult(id: "rank_priority_5", name: "Rank Priority 5", rank: 61, probability: 0.03204248428344726),
            syntheticChanceResult(id: "rank_priority_6", name: "Rank Priority 6", rank: 73, probability: 0.27295363426208497),
            syntheticChanceResult(id: "rank_priority_7", name: "Rank Priority 7", rank: 59, probability: 0.08189108848571777),
            syntheticChanceResult(id: "rank_priority_8", name: "Rank Priority 8", rank: 57, probability: 0.1529093313217163),
            syntheticChanceResult(id: "rank_priority_9", name: "Rank Priority 9", rank: 9, probability: 0.5861554312705993),
            syntheticChanceResult(id: "rank_priority_10", name: "Rank Priority 10", rank: 53, probability: 0.4318820285797119),
            syntheticChanceResult(id: "rank_priority_11", name: "Rank Priority 11", rank: 4, probability: 0.6248900878429413),
            syntheticChanceResult(id: "rank_priority_12", name: "Rank Priority 12", rank: 5, probability: 0.5774792182445526),
            syntheticChanceResult(id: "rank_priority_13", name: "Rank Priority 13", rank: 34, probability: 0.506153826713562),
            syntheticChanceResult(id: "rank_priority_14", name: "Rank Priority 14", rank: 46, probability: 0.5179235029220581),
            syntheticChanceResult(id: "rank_priority_15", name: "Rank Priority 15", rank: 63, probability: 0.23645434856414793)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 5)
        let marginalOrderForSameSet = greedyExpectedBestOfferSteps(from: optimizedSteps.map(\.result), count: optimizedSteps.count)

        XCTAssertEqual(eligible.count, 16)
        XCTAssertEqual(optimizedSteps.first?.result.college.id, "rank_priority_3")
        XCTAssertEqual(optimizedSteps.map(\.order), Array(1...optimizedSteps.count))
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: marginalOrderForSameSet)
        )
    }

    func testAutoRecommendationContinuesReplacementUntilNoSingleSwapImproves() {
        let initialT30 = syntheticChanceResult(id: "initial_t30", name: "Initial T30", rank: 29, probability: 0.61)
        let topRank = syntheticChanceResult(id: "top_rank", name: "Top Rank", rank: 2, probability: 0.34)
        let lowerT20 = syntheticChanceResult(id: "lower_t20", name: "Lower T20", rank: 18, probability: 0.25)
        let lowValueT50 = syntheticChanceResult(id: "low_value_t50", name: "Low Value T50", rank: 44, probability: 0.15)
        let strongerT30 = syntheticChanceResult(id: "stronger_t30", name: "Stronger T30", rank: 23, probability: 0.55)
        let t50Anchor = syntheticChanceResult(id: "t50_anchor", name: "T50 Anchor", rank: 31, probability: 0.60)
        let highT20 = syntheticChanceResult(id: "high_t20", name: "High T20", rank: 11, probability: 0.39)
        let eligible = [initialT30, topRank, lowerT20, lowValueT50, strongerT30, t50Anchor, highT20]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 3)
        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: 3)
        let onceReplacedSteps = greedyExpectedBestOfferSteps(from: [t50Anchor, topRank, highT20], count: 3)

        XCTAssertEqual(Set(optimizedSteps.map { $0.result.college.id }), Set([strongerT30.college.id, topRank.college.id, t50Anchor.college.id]))
        XCTAssertEqual(optimizedSteps.map(\.order), Array(1...optimizedSteps.count))
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: onceReplacedSteps)
        )
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testAutoRecommendationUsesExactBestOfferSearchWhenCombinationSpaceIsSmall() {
        let eligible = [
            syntheticChanceResult(id: "rank_1", name: "Rank 1", rank: 1, probability: 0.30),
            syntheticChanceResult(id: "rank_7", name: "Rank 7", rank: 7, probability: 0.38),
            syntheticChanceResult(id: "rank_13", name: "Rank 13", rank: 13, probability: 0.48),
            syntheticChanceResult(id: "rank_22", name: "Rank 22", rank: 22, probability: 0.52),
            syntheticChanceResult(id: "rank_34", name: "Rank 34", rank: 34, probability: 0.58),
            syntheticChanceResult(id: "rank_48", name: "Rank 48", rank: 48, probability: 0.62),
            syntheticChanceResult(id: "rank_70", name: "Rank 70", rank: 70, probability: 0.66)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 4)
        let exhaustiveSteps = exhaustiveExpectedBestOfferSteps(from: eligible, count: 4)

        XCTAssertEqual(Set(optimizedSteps.map { $0.result.college.id }), Set(exhaustiveSteps.map { $0.result.college.id }))
        XCTAssertEqual(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: exhaustiveSteps),
            accuracy: 0.0001
        )
    }

    func testExactAutoRecommendationUsesBestOrderingForSmallCombinationSpace() {
        let eligible = [
            syntheticChanceResult(id: "exact_order_0", name: "Exact Order 0", rank: 66, probability: 0.40101287841796873),
            syntheticChanceResult(id: "exact_order_1", name: "Exact Order 1", rank: 57, probability: 0.2170033264160156),
            syntheticChanceResult(id: "exact_order_2", name: "Exact Order 2", rank: 76, probability: 0.6034222412109375),
            syntheticChanceResult(id: "exact_order_3", name: "Exact Order 3", rank: 54, probability: 0.2567051696777344),
            syntheticChanceResult(id: "exact_order_4", name: "Exact Order 4", rank: 35, probability: 0.3775845336914062),
            syntheticChanceResult(id: "exact_order_5", name: "Exact Order 5", rank: 61, probability: 0.5179646301269532),
            syntheticChanceResult(id: "exact_order_6", name: "Exact Order 6", rank: 49, probability: 0.502796630859375)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 4)
        let greedyOrderForSameSet = greedyExpectedBestOfferSteps(from: optimizedSteps.map(\.result), count: optimizedSteps.count)
        let exhaustiveSteps = exhaustiveExpectedBestOfferSteps(from: eligible, count: 4)

        XCTAssertLessThanOrEqual(eligible.count, 12)
        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, exhaustiveSteps.map { $0.result.college.id })
        XCTAssertEqual(optimizedSteps.first?.result.college.id, "exact_order_4")
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedyOrderForSameSet)
        )
    }

    func testExactAutoRecommendationEvaluatesMarginalOrderingWithinCandidateCombination() {
        let eligible = [
            syntheticChanceResult(id: "exact_marginal_rank_11", name: "Exact Marginal Rank 11", rank: 11, probability: 0.24468159961322844),
            syntheticChanceResult(id: "exact_marginal_rank_26", name: "Exact Marginal Rank 26", rank: 26, probability: 0.5230084540195538),
            syntheticChanceResult(id: "exact_marginal_rank_1", name: "Exact Marginal Rank 1", rank: 1, probability: 0.39823673109244334),
            syntheticChanceResult(id: "exact_marginal_rank_23", name: "Exact Marginal Rank 23", rank: 23, probability: 0.29228216848190325)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: eligible.count)
        let currentOrderSteps = recommendationStepsInTestOrder(from: eligible.sorted { lhs, rhs in
            let lhsValue = engine.recommendationExpectedValue(for: lhs)
            let rhsValue = engine.recommendationExpectedValue(for: rhs)
            if lhsValue == rhsValue {
                return lhs.college.rank < rhs.college.rank
            }
            return lhsValue > rhsValue
        })
        let rankPrioritySteps = recommendationStepsInTestOrder(from: eligible.sorted { lhs, rhs in
            let lhsRankScore = engine.recommendationRankScore(for: lhs.college)
            let rhsRankScore = engine.recommendationRankScore(for: rhs.college)
            if lhsRankScore == rhsRankScore {
                return lhs.adjustedProbability > rhs.adjustedProbability
            }
            return lhsRankScore > rhsRankScore
        })
        let marginalSteps = greedyExpectedBestOfferSteps(from: eligible, count: eligible.count)

        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, marginalSteps.map { $0.result.college.id })
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: currentOrderSteps)
        )
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: rankPrioritySteps)
        )
    }

    func testExactAutoRecommendationUsesCombinationLimitBeyondTwelveCandidates() {
        let eligible = [
            syntheticChanceResult(id: "combo_0", name: "Combo 0", rank: 58, probability: 0.152338253012844),
            syntheticChanceResult(id: "combo_1", name: "Combo 1", rank: 51, probability: 0.191589536059766),
            syntheticChanceResult(id: "combo_2", name: "Combo 2", rank: 40, probability: 0.608468719201560),
            syntheticChanceResult(id: "combo_3", name: "Combo 3", rank: 68, probability: 0.079994004013277),
            syntheticChanceResult(id: "combo_4", name: "Combo 4", rank: 34, probability: 0.199842145581964),
            syntheticChanceResult(id: "combo_5", name: "Combo 5", rank: 1, probability: 0.521227494962758),
            syntheticChanceResult(id: "combo_6", name: "Combo 6", rank: 51, probability: 0.190270920582326),
            syntheticChanceResult(id: "combo_7", name: "Combo 7", rank: 60, probability: 0.378592273732154),
            syntheticChanceResult(id: "combo_8", name: "Combo 8", rank: 35, probability: 0.026285304745421),
            syntheticChanceResult(id: "combo_9", name: "Combo 9", rank: 7, probability: 0.594019155645093),
            syntheticChanceResult(id: "combo_10", name: "Combo 10", rank: 73, probability: 0.374633687983590),
            syntheticChanceResult(id: "combo_11", name: "Combo 11", rank: 67, probability: 0.398631218218366),
            syntheticChanceResult(id: "combo_12", name: "Combo 12", rank: 12, probability: 0.102839587533390),
            syntheticChanceResult(id: "combo_13", name: "Combo 13", rank: 25, probability: 0.604337967682684),
            syntheticChanceResult(id: "combo_14", name: "Combo 14", rank: 64, probability: 0.579456678300587),
            syntheticChanceResult(id: "combo_15", name: "Combo 15", rank: 72, probability: 0.156549749920840),
            syntheticChanceResult(id: "combo_16", name: "Combo 16", rank: 20, probability: 0.086815854086661),
            syntheticChanceResult(id: "combo_17", name: "Combo 17", rank: 63, probability: 0.594687555943156),
            syntheticChanceResult(id: "combo_18", name: "Combo 18", rank: 33, probability: 0.423429981597963),
            syntheticChanceResult(id: "combo_19", name: "Combo 19", rank: 13, probability: 0.624422660200888)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 2)
        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: 2)
        let exhaustiveSteps = exhaustiveExpectedBestOfferSteps(from: eligible, count: 2)

        XCTAssertEqual(eligible.count, 20)
        XCTAssertEqual(Set(optimizedSteps.map { $0.result.college.id }), Set(exhaustiveSteps.map { $0.result.college.id }))
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testAutoRecommendationUsesFastApproximationForLargerHighCountRequests() {
        let eligible = (1...30).map { index in
            syntheticChanceResult(
                id: "larger_pool_\(index)",
                name: "Larger Pool \(index)",
                rank: index,
                probability: 0.18 + Double(index % 9) * 0.035
            )
        }

        let steps = engine.recommendationSteps(for: eligible, count: 29)

        XCTAssertEqual(steps.count, 29)
        XCTAssertEqual(Set(steps.map { $0.result.college.id }).count, 29)
        XCTAssertEqual(steps.map(\.order), Array(1...29))
    }

    func testAutoRecommendationStillOptimizesOrderingWhenRequestedCountExceedsEligiblePool() {
        let eligible = [
            syntheticChanceResult(id: "all_pool_0", name: "All Pool 0", rank: 17, probability: 0.2939585752900954),
            syntheticChanceResult(id: "all_pool_1", name: "All Pool 1", rank: 16, probability: 0.36754710613857977),
            syntheticChanceResult(id: "all_pool_2", name: "All Pool 2", rank: 43, probability: 0.4496891122979622),
            syntheticChanceResult(id: "all_pool_3", name: "All Pool 3", rank: 29, probability: 0.29864619347206217),
            syntheticChanceResult(id: "all_pool_4", name: "All Pool 4", rank: 55, probability: 0.5482453415603815),
            syntheticChanceResult(id: "all_pool_5", name: "All Pool 5", rank: 22, probability: 0.4685615720144475),
            syntheticChanceResult(id: "all_pool_6", name: "All Pool 6", rank: 30, probability: 0.6203682561334971),
            syntheticChanceResult(id: "all_pool_7", name: "All Pool 7", rank: 40, probability: 0.1813485326709292),
            syntheticChanceResult(id: "all_pool_8", name: "All Pool 8", rank: 39, probability: 0.6163174159485052)
        ]

        let optimizedSteps = engine.recommendationSteps(for: eligible, count: 20)
        let greedySteps = greedyExpectedBestOfferSteps(from: eligible, count: eligible.count)
        let expectedBestOrder = bestOrderingExpectedBestOfferSteps(from: eligible)

        XCTAssertEqual(optimizedSteps.count, eligible.count)
        XCTAssertEqual(Set(optimizedSteps.map { $0.result.college.id }), Set(eligible.map { $0.college.id }))
        XCTAssertEqual(optimizedSteps.map { $0.result.college.id }, expectedBestOrder.map { $0.result.college.id })
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: optimizedSteps),
            engine.recommendationBestOfferExpectedValue(for: greedySteps)
        )
    }

    func testAutoRecommendationBoundedApproximationKeepsLargePortfoliosComplete() {
        let eligible = (1...260).map { index in
            syntheticChanceResult(
                id: "bounded_pool_\(index)",
                name: "Bounded Pool \(index)",
                rank: index,
                probability: 0.12 + Double((index * 7) % 19) * 0.018
            )
        }

        let requestedCount = 70
        let optimizedSteps = engine.recommendationSteps(for: eligible, count: requestedCount)

        XCTAssertEqual(optimizedSteps.count, requestedCount)
        XCTAssertEqual(Set(optimizedSteps.map { $0.result.college.id }).count, requestedCount)
        XCTAssertEqual(optimizedSteps.map(\.order), Array(1...requestedCount))
        XCTAssertGreaterThan(engine.recommendationBestOfferExpectedValue(for: optimizedSteps), 0)
        XCTAssertTrue(optimizedSteps.allSatisfy { $0.marginalExpectedValue >= -0.0001 })
    }

    func testFastAutoRecommendationKeepsHighRankCandidatesInWindow() {
        let sameTierCrowd = (1...120).map { index in
            syntheticChanceResult(
                id: "crowded_t30_\(index)",
                name: "Crowded T30 \(index)",
                rank: 25,
                probability: 0.36
            )
        }
        let highRankLowerBaseValue = syntheticChanceResult(
            id: "high_rank_guardrail",
            name: "High Rank Guardrail",
            rank: 1,
            probability: 0.25
        )

        let steps = engine.recommendationSteps(for: sameTierCrowd + [highRankLowerBaseValue], count: 35)

        XCTAssertEqual(steps.count, 35)
        XCTAssertTrue(
            steps.contains { $0.result.college.id == highRankLowerBaseValue.college.id },
            "High-rank schools with slightly lower base expected value should still enter the bounded window when same-tier discounting makes them valuable."
        )
    }

    func testFastAutoRecommendationKeepsHighProbabilityCandidatesInWindow() {
        let sameTierCrowd = (1...120).map { index in
            syntheticChanceResult(
                id: "crowded_t10_\(index)",
                name: "Crowded T10 \(index)",
                rank: 5,
                probability: 0.32
            )
        }
        let highProbabilityLowerRank = syntheticChanceResult(
            id: "high_probability_guardrail",
            name: "High Probability Guardrail",
            rank: 180,
            probability: 0.70
        )

        let steps = engine.recommendationSteps(for: sameTierCrowd + [highProbabilityLowerRank], count: 35)
        let withoutProbabilityGuardrailCandidate = engine.recommendationSteps(for: sameTierCrowd, count: 35)

        XCTAssertEqual(steps.count, 35)
        XCTAssertTrue(
            steps.contains { $0.result.college.id == highProbabilityLowerRank.college.id },
            "High-probability schools with lower rank value should still enter the bounded window when repeated same-tier selections have diminishing marginal value."
        )
        XCTAssertGreaterThan(
            engine.recommendationBestOfferExpectedValue(for: steps),
            engine.recommendationBestOfferExpectedValue(for: withoutProbabilityGuardrailCandidate)
        )
    }

    func testRecommendationStepsMatchRecommendedCollegesAndExposeMarginalValues() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 6

        let recommendedIDs = engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id)
        let steps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)

        XCTAssertEqual(steps.map { $0.result.college.id }, recommendedIDs)
        XCTAssertEqual(steps.map(\.order), Array(1...steps.count))
        XCTAssertTrue(steps.allSatisfy { $0.rankScore >= 40 && $0.rankScore <= 100 })
        XCTAssertTrue(steps.allSatisfy { $0.sameTierDiscount > 0 && $0.sameTierDiscount <= 1 })
        XCTAssertTrue(steps.allSatisfy { $0.marginalExpectedValue <= $0.baseExpectedValue + 0.0001 })
    }

    func testPortfolioResultSummarizesAutomaticExpectedBestOfferValue() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 5
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)
        let expectedTotal = engine.recommendationBestOfferExpectedValue(for: result.recommendationSteps)
        let report = ReportService.makeReport(result: result)

        XCTAssertGreaterThan(result.recommendationExpectedValueTotal, 0)
        XCTAssertEqual(result.recommendationExpectedValueTotal, expectedTotal, accuracy: 0.0001)
        XCTAssertTrue(report.contains("组合最佳录取期望值"))
        XCTAssertTrue(report.contains("0-100 排名价值尺度"))
        XCTAssertTrue(report.contains("不是录取概率"))
    }

    func testPortfolioResultStoresRecommendationExpectedValueSnapshot() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 4
        let manual = engine.evaluate(profile: profile, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let automatic = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)

        XCTAssertEqual(manual.recommendationExpectedValueTotal, 0)
        XCTAssertEqual(
            automatic.recommendationExpectedValueTotal,
            automatic.recommendationSteps.reduce(0) { partial, step in
                partial + step.marginalExpectedValue
            },
            accuracy: 0.0001
        )
    }

    func testExpectedBestOfferValueDoesNotDoubleCountMultipleOffers() {
        let highValue = syntheticChanceResult(id: "high_value", name: "High Value", rank: 1, probability: 0.60)
        let lowerValue = syntheticChanceResult(id: "lower_value", name: "Lower Value", rank: 30, probability: 0.60)
        let highRankScore = engine.recommendationRankScore(for: highValue.college)
        let lowerRankScore = engine.recommendationRankScore(for: lowerValue.college)
        let steps = [
            RecommendationStep(
                order: 1,
                result: highValue,
                rankScore: highRankScore,
                confidenceMultiplier: 1,
                baseExpectedValue: highValue.adjustedProbability * highRankScore,
                sameTierDiscount: 1,
                marginalExpectedValue: highValue.adjustedProbability * highRankScore
            ),
            RecommendationStep(
                order: 2,
                result: lowerValue,
                rankScore: lowerRankScore,
                confidenceMultiplier: 1,
                baseExpectedValue: lowerValue.adjustedProbability * lowerRankScore,
                sameTierDiscount: 1,
                marginalExpectedValue: (1 - highValue.adjustedProbability) * lowerValue.adjustedProbability * lowerRankScore
            )
        ]

        let simpleSum = steps.reduce(0) { $0 + $1.baseExpectedValue }
        let expectedBestOffer = highValue.adjustedProbability * highRankScore +
            (1 - highValue.adjustedProbability) * lowerValue.adjustedProbability * lowerRankScore

        XCTAssertEqual(engine.recommendationBestOfferExpectedValue(for: steps), expectedBestOffer, accuracy: 0.0001)
        XCTAssertLessThan(engine.recommendationBestOfferExpectedValue(for: steps), simpleSum)
        XCTAssertEqual(steps[1].marginalExpectedValue, expectedBestOffer - steps[0].marginalExpectedValue, accuracy: 0.0001)
    }

    func testBestOfferValueKeepsMarginalSameTierDiscountMonotonic() {
        let lowerRankFirst = syntheticChanceResult(id: "lower_rank_first", name: "Lower Rank First", rank: 30, probability: 0.70)
        let higherRankSecond = syntheticChanceResult(id: "higher_rank_second", name: "Higher Rank Second", rank: 20, probability: 0.01)
        let lowerRankScore = engine.recommendationRankScore(for: lowerRankFirst.college)
        let higherRankScore = engine.recommendationRankScore(for: higherRankSecond.college)
        let t30Decay = 0.93
        let firstStep = RecommendationStep(
            order: 1,
            result: lowerRankFirst,
            rankScore: lowerRankScore,
            confidenceMultiplier: 1,
            baseExpectedValue: engine.recommendationExpectedValue(for: lowerRankFirst),
            sameTierDiscount: 1,
            marginalExpectedValue: 0
        )
        let secondStep = RecommendationStep(
            order: 2,
            result: higherRankSecond,
            rankScore: higherRankScore,
            confidenceMultiplier: 1,
            baseExpectedValue: engine.recommendationExpectedValue(for: higherRankSecond),
            sameTierDiscount: t30Decay,
            marginalExpectedValue: 0
        )
        let steps = [
            firstStep,
            secondStep
        ]

        let expected = higherRankSecond.adjustedProbability * t30Decay * higherRankScore +
            (1 - higherRankSecond.adjustedProbability * t30Decay) * lowerRankFirst.adjustedProbability * lowerRankScore
        let staleValueOrderReassignment = higherRankSecond.adjustedProbability * higherRankScore +
            (1 - higherRankSecond.adjustedProbability) * lowerRankFirst.adjustedProbability * t30Decay * lowerRankScore

        XCTAssertEqual(engine.recommendationBestOfferExpectedValue(for: steps), expected, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(
            engine.recommendationBestOfferExpectedValue(for: steps) + 0.0001,
            engine.recommendationBestOfferExpectedValue(for: [firstStep])
        )
        XCTAssertGreaterThan(engine.recommendationBestOfferExpectedValue(for: steps), staleValueOrderReassignment)
    }

    func testBestOfferValueUsesStoredMarginalSameTierDiscounts() {
        let highValue = syntheticChanceResult(id: "high_value_discounted", name: "High Value Discounted", rank: 1, probability: 0.50)
        let lowerValue = syntheticChanceResult(id: "lower_value_full", name: "Lower Value Full", rank: 30, probability: 0.50)
        let highRankScore = engine.recommendationRankScore(for: highValue.college)
        let lowerRankScore = engine.recommendationRankScore(for: lowerValue.college)
        let storedDiscount = 0.50
        let steps = [
            RecommendationStep(
                order: 1,
                result: lowerValue,
                rankScore: lowerRankScore,
                confidenceMultiplier: 1,
                baseExpectedValue: engine.recommendationExpectedValue(for: lowerValue),
                sameTierDiscount: 1,
                marginalExpectedValue: 0
            ),
            RecommendationStep(
                order: 2,
                result: highValue,
                rankScore: highRankScore,
                confidenceMultiplier: 1,
                baseExpectedValue: engine.recommendationExpectedValue(for: highValue),
                sameTierDiscount: storedDiscount,
                marginalExpectedValue: 0
            )
        ]

        let expected = highValue.adjustedProbability * storedDiscount * highRankScore +
            (1 - highValue.adjustedProbability * storedDiscount) * lowerValue.adjustedProbability * lowerRankScore
        let ignoringStoredDiscount = highValue.adjustedProbability * highRankScore +
            (1 - highValue.adjustedProbability) * lowerValue.adjustedProbability * lowerRankScore

        XCTAssertEqual(engine.recommendationBestOfferExpectedValue(for: steps), expected, accuracy: 0.0001)
        XCTAssertNotEqual(engine.recommendationBestOfferExpectedValue(for: steps), ignoringStoredDiscount, accuracy: 0.0001)
    }

    func testRecommendationValueDiscountsLowConfidenceWithoutChangingProbability() {
        var highConfidence = syntheticChanceResult(id: "high_confidence", name: "High Confidence", rank: 20, probability: 0.40, confidence: .high)
        let lowConfidence = syntheticChanceResult(id: "low_confidence", name: "Low Confidence", rank: 20, probability: 0.40, confidence: .low)
        highConfidence = ChanceResult(
            college: highConfidence.college,
            baseRate: highConfidence.baseRate,
            adjustedProbability: highConfidence.adjustedProbability,
            confidence: .high,
            bucket: highConfidence.bucket,
            factors: highConfidence.factors,
            warnings: highConfidence.warnings,
            gateResult: highConfidence.gateResult
        )

        let highStep = RecommendationStep(
            order: 1,
            result: highConfidence,
            rankScore: engine.recommendationRankScore(for: highConfidence.college),
            confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: highConfidence),
            baseExpectedValue: engine.recommendationExpectedValue(for: highConfidence),
            sameTierDiscount: 1,
            marginalExpectedValue: 0
        )
        let lowStep = RecommendationStep(
            order: 1,
            result: lowConfidence,
            rankScore: engine.recommendationRankScore(for: lowConfidence.college),
            confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: lowConfidence),
            baseExpectedValue: engine.recommendationExpectedValue(for: lowConfidence),
            sameTierDiscount: 1,
            marginalExpectedValue: 0
        )

        XCTAssertEqual(highConfidence.adjustedProbability, lowConfidence.adjustedProbability)
        XCTAssertEqual(engine.recommendationExpectedValue(for: highConfidence), engine.recommendationExpectedValue(for: lowConfidence), accuracy: 0.0001)
        XCTAssertLessThan(engine.recommendationConfidenceMultiplier(for: lowConfidence), engine.recommendationConfidenceMultiplier(for: highConfidence))
        XCTAssertLessThan(engine.recommendationBestOfferExpectedValue(for: [lowStep]), engine.recommendationBestOfferExpectedValue(for: [highStep]))
    }

    func testLowConfidenceOfferUsesReliabilityAdjustedFailureChain() {
        let lowConfidenceHighRank = syntheticChanceResult(id: "low_conf_high_rank", name: "Low Confidence High Rank", rank: 1, probability: 0.70, confidence: .low)
        let highConfidenceLowerRank = syntheticChanceResult(id: "high_conf_lower_rank", name: "High Confidence Lower Rank", rank: 30, probability: 0.60, confidence: .high)
        let highRankScore = engine.recommendationRankScore(for: lowConfidenceHighRank.college)
        let lowerRankScore = engine.recommendationRankScore(for: highConfidenceLowerRank.college)
        let highRankReliability = lowConfidenceHighRank.adjustedProbability * engine.recommendationConfidenceMultiplier(for: lowConfidenceHighRank)
        let lowerRankReliability = highConfidenceLowerRank.adjustedProbability * engine.recommendationConfidenceMultiplier(for: highConfidenceLowerRank)
        let steps = [
            RecommendationStep(
                order: 1,
                result: lowConfidenceHighRank,
                rankScore: highRankScore,
                confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: lowConfidenceHighRank),
                baseExpectedValue: engine.recommendationExpectedValue(for: lowConfidenceHighRank),
                sameTierDiscount: 1,
                marginalExpectedValue: 0
            ),
            RecommendationStep(
                order: 2,
                result: highConfidenceLowerRank,
                rankScore: lowerRankScore,
                confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: highConfidenceLowerRank),
                baseExpectedValue: engine.recommendationExpectedValue(for: highConfidenceLowerRank),
                sameTierDiscount: 1,
                marginalExpectedValue: 0
            )
        ]

        let expected = highRankReliability * highRankScore +
            (1 - highRankReliability) * lowerRankReliability * lowerRankScore
        let staleUnadjustedFailure = highRankReliability * highRankScore +
            (1 - lowConfidenceHighRank.adjustedProbability) * lowerRankReliability * lowerRankScore

        XCTAssertEqual(engine.recommendationBestOfferExpectedValue(for: steps), expected, accuracy: 0.0001)
        XCTAssertGreaterThan(engine.recommendationBestOfferExpectedValue(for: steps), staleUnadjustedFailure)
    }

    func testAutomaticReportExplainsRecommendationExpectedValue() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 4
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("自动推荐依据"))
        XCTAssertTrue(report.contains("单校概率 × 排名价值分"))
        XCTAssertTrue(report.contains("概率×排名价值"))
        XCTAssertTrue(report.contains("同层相关性"))
        XCTAssertTrue(report.contains("文理学院 T10 的排名价值对齐到综合大学 T20-T30 价值带"))
        XCTAssertTrue(report.contains("综合大学 T10 与文理学院 T10 共享同一个极端选择性相关性层"))
        XCTAssertTrue(report.contains("最高价值 offer"))
        XCTAssertTrue(report.contains("组合总空间"))
        XCTAssertTrue(report.contains("排名价值优先顺位"))
        XCTAssertTrue(report.contains("第1顺位"))
        XCTAssertTrue(report.contains("边际期望值"))
    }

    func testAutomaticReportIncludesEveryRecommendationStepBeyondResultsPreview() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 12
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)
        let report = ReportService.makeReport(result: result)

        XCTAssertEqual(result.recommendationSteps.count, profile.requestedSchoolCount)
        for step in result.recommendationSteps {
            XCTAssertTrue(report.contains("第\(step.order)顺位 \(step.result.college.name)"), step.result.college.name)
            XCTAssertTrue(report.contains("边际期望值 \(step.marginalExpectedValue.formatted(.number.precision(.fractionLength(2))))"), step.result.college.name)
        }
    }

    func testReportLabelsNCESLiberalArtsOfficialSources() {
        let ncesLAC = syntheticChanceResult(
            id: "synthetic_nces_lac",
            name: "Synthetic NCES LAC",
            category: .liberalArtsCollege,
            rank: 12,
            probability: 0.22,
            sourceURL: URL(string: "https://nces.ed.gov/ipeds/reported-data/html/123456?year=2024&surveyNumber=12&viewmode=print")!,
            sourceNote: "NCES/IPEDS admissions rate via UNITID 123456; synthetic fixture."
        )
        let result = PortfolioResult(
            profileSnapshot: .sample,
            selectedCollegeIDs: Set([ncesLAC.college.id]),
            schoolResults: [ncesLAC],
            recommendedSchools: [],
            recommendationSteps: [],
            selectionSource: .manual,
            selectedBucketCounts: PortfolioBucketCounts(likely: 0, target: 1, reach: 0, blocked: 0),
            selectionWarnings: [],
            recommendationWarnings: [],
            t10AtLeastOne: 0,
            t11T30AtLeastOne: 0,
            t30AtLeastOne: 0,
            t50AtLeastOne: 0,
            liberalArtsT10AtLeastOne: 0,
            liberalArtsT30AtLeastOne: 0.22,
            selectedAtLeastOne: 0.22,
            profileScore: 80,
            recommendationExpectedValueTotal: 0,
            generatedAt: Date()
        )

        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("NCES/IPEDS Reported Data Admissions"))
        XCTAssertFalse(report.contains("Synthetic NCES LAC：基础率 22.0%，已审阅 Top30 Liberal Arts Colleges 用户表"))
    }

    func testPortfolioResultCarriesMatchingAutomaticRecommendationSteps() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 5
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)

        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        XCTAssertEqual(result.recommendedSchools.map(\.id), result.recommendationSteps.map { $0.result.college.id })
        XCTAssertEqual(result.recommendationSteps.map(\.order), Array(1...result.recommendationSteps.count))
        XCTAssertTrue(result.recommendationSteps.allSatisfy { $0.marginalExpectedValue > 0 })
    }

    func testAutomaticEvaluationReusesSuppliedRecommendationStepsWhenTheyMatchSelection() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 7
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: suppliedSteps
        )

        XCTAssertEqual(result.recommendationSteps, suppliedSteps)
        XCTAssertEqual(result.recommendedSchools.map(\.id), suppliedSteps.map { $0.result.college.id })
        XCTAssertEqual(
            result.recommendationExpectedValueTotal,
            engine.recommendationBestOfferExpectedValue(for: suppliedSteps),
            accuracy: 0.0001
        )
    }

    func testAutomaticRecommendationConvenienceEvaluationCarriesGeneratedSteps() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 6
        let expectedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)

        let result = engine.evaluateAutomaticRecommendation(profile: profile)

        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, expectedSteps.map { $0.result.college.id })
        XCTAssertEqual(result.recommendationSteps.map(\.order), expectedSteps.map(\.order))
        XCTAssertEqual(result.recommendationSteps.map(\.rankScore), expectedSteps.map(\.rankScore))
        XCTAssertEqual(result.recommendationSteps.map(\.sameTierDiscount), expectedSteps.map(\.sameTierDiscount))
        XCTAssertEqual(result.recommendedSchools.map(\.id), expectedSteps.map { $0.result.college.id })
        XCTAssertEqual(result.selectedCollegeIDs, Set(expectedSteps.map(\.result.college.id)))
        XCTAssertEqual(
            result.recommendationExpectedValueTotal,
            engine.recommendationBestOfferExpectedValue(for: expectedSteps),
            accuracy: 0.0001
        )
    }

    func testAutomaticEvaluationRejectsSelfConsistentSuppliedStepsWithWrongRecommendationOrder() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 5
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))
        let reorderedSteps = recommendationStepsInTestOrder(from: suppliedSteps.reversed().map(\.result))

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: reorderedSteps
        )

        XCTAssertNotEqual(reorderedSteps.map { $0.result.college.id }, suppliedSteps.map { $0.result.college.id })
        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, suppliedSteps.map { $0.result.college.id })
        XCTAssertNotEqual(result.recommendationSteps.map { $0.result.college.id }, reorderedSteps.map { $0.result.college.id })
        XCTAssertEqual(
            result.recommendationExpectedValueTotal,
            engine.recommendationBestOfferExpectedValue(for: suppliedSteps),
            accuracy: 0.0001
        )
    }

    func testAutomaticEvaluationIgnoresSuppliedRecommendationStepsWhenTheyDoNotMatchSelection() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 5
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let selectedIDs: Set<String> = ["bu"]

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: suppliedSteps
        )

        XCTAssertEqual(Set(result.schoolResults.map(\.college.id)), selectedIDs)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationSteps.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
    }

    func testAutomaticEvaluationDoesNotReuseStaleRecommendationStepProbabilities() {
        var originalProfile = strongChineseInternationalProfile
        originalProfile.requestedSchoolCount = 5
        let suppliedSteps = engine.recommendationSteps(for: originalProfile, count: originalProfile.requestedSchoolCount)
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))
        var changedProfile = originalProfile
        changedProfile.gpaPercent = 82
        changedProfile.classRankPercentile = 35
        changedProfile.sat = 1380

        let result = engine.evaluate(
            profile: changedProfile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: suppliedSteps
        )

        XCTAssertNotEqual(result.recommendationSteps, suppliedSteps)
        for step in result.recommendationSteps {
            let current = engine.chance(for: step.result.college, profile: changedProfile)
            XCTAssertEqual(step.result.adjustedProbability, current.adjustedProbability, accuracy: 0.0001)
            XCTAssertEqual(step.result.confidence, current.confidence)
        }
    }

    func testAutomaticEvaluationRejectsDuplicateSuppliedRecommendationSteps() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 2
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let malformedSteps = suppliedSteps + [suppliedSteps[0]]
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: malformedSteps
        )

        XCTAssertNotEqual(result.recommendationSteps, malformedSteps)
        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, suppliedSteps.map { $0.result.college.id })
        XCTAssertEqual(result.recommendedSchools.map(\.id), suppliedSteps.map { $0.result.college.id })
    }

    func testAutomaticEvaluationRejectsSuppliedRecommendationStepsWithBadOrder() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 4
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))
        let first = suppliedSteps[0]
        var malformedSteps = suppliedSteps
        malformedSteps[0] = RecommendationStep(
            order: 99,
            result: first.result,
            rankScore: first.rankScore,
            confidenceMultiplier: first.confidenceMultiplier,
            baseExpectedValue: first.baseExpectedValue,
            sameTierDiscount: first.sameTierDiscount,
            marginalExpectedValue: first.marginalExpectedValue
        )

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: malformedSteps
        )

        XCTAssertNotEqual(result.recommendationSteps, malformedSteps)
        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, suppliedSteps.map { $0.result.college.id })
        XCTAssertEqual(result.recommendationSteps.map(\.order), Array(1...suppliedSteps.count))
    }

    func testAutomaticEvaluationRejectsSuppliedRecommendationStepsWithBadExpectedValueMetadata() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 4
        let suppliedSteps = engine.recommendationSteps(for: profile, count: profile.requestedSchoolCount)
        let selectedIDs = Set(suppliedSteps.map(\.result.college.id))
        let first = suppliedSteps[0]
        var malformedSteps = suppliedSteps
        malformedSteps[0] = RecommendationStep(
            order: first.order,
            result: first.result,
            rankScore: first.rankScore + 10,
            confidenceMultiplier: first.confidenceMultiplier,
            baseExpectedValue: first.baseExpectedValue,
            sameTierDiscount: first.sameTierDiscount,
            marginalExpectedValue: first.marginalExpectedValue
        )

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: selectedIDs,
            selectionSource: .automatic,
            automaticRecommendationSteps: malformedSteps
        )

        XCTAssertNotEqual(result.recommendationSteps, malformedSteps)
        XCTAssertEqual(result.recommendationSteps.map { $0.result.college.id }, suppliedSteps.map { $0.result.college.id })
        XCTAssertEqual(
            result.recommendationExpectedValueTotal,
            engine.recommendationBestOfferExpectedValue(for: suppliedSteps),
            accuracy: 0.0001
        )
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
        let eligibleCount = AdmissionsSeedData.colleges.map { engine.chance(for: $0, profile: profile) }.filter(\.gateResult.passed).count
        profile.requestedSchoolCount = eligibleCount + 5

        let result = engine.evaluate(
            profile: profile,
            selectedCollegeIDs: Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id)),
            selectionSource: .automatic
        )

        XCTAssertFalse(result.recommendationWarnings.isEmpty)
        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(result.recommendedSchools.count, Set(result.recommendedSchools.map(\.id)).count)
        XCTAssertEqual(result.recommendedSchools.count, eligibleCount)
        XCTAssertTrue(result.recommendationWarnings.contains("自动推荐数量不足：计划 \(profile.requestedSchoolCount) 所，当前生成 \(eligibleCount) 所。"))
    }

    func testManualSelectionDoesNotShowAutoRecommendationWarnings() {
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 99

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)

        XCTAssertEqual(result.selectionSource, .manual)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
        XCTAssertTrue(ReportService.makeReport(result: result).contains("当前为手动选校，未触发自动推荐缺口判断"))
        XCTAssertFalse(ReportService.makeReport(result: result).contains("自动推荐数量与计划选择数量一致"))
    }

    func testAutomaticSelectionIsOnlySourceThatCarriesRecommendedSchools() {
        let manual = engine.evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let none = engine.evaluate(profile: .sample, selectedCollegeIDs: [], selectionSource: .none)
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 2
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let automatic = engine.evaluate(profile: profile, selectedCollegeIDs: automaticIDs, selectionSource: .automatic)

        XCTAssertTrue(manual.recommendedSchools.isEmpty)
        XCTAssertTrue(none.recommendedSchools.isEmpty)
        XCTAssertFalse(automatic.recommendedSchools.isEmpty)
        XCTAssertEqual(Set(automatic.recommendedSchools.map(\.id)), automaticIDs)
        XCTAssertTrue(manual.recommendationSteps.isEmpty)
        XCTAssertTrue(none.recommendationSteps.isEmpty)
        XCTAssertFalse(automatic.recommendationSteps.isEmpty)
    }

    func testAutomaticSelectionRejectsPortfolioThatDoesNotMatchRegeneratedRecommendation() {
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 12

        let selectedIDs: Set<String> = ["bu"]
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selectedIDs, selectionSource: .automatic)

        XCTAssertEqual(result.selectionSource, .automatic)
        XCTAssertEqual(Set(result.schoolResults.map(\.college.id)), selectedIDs)
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationSteps.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
        XCTAssertTrue(ReportService.makeReport(result: result).contains("与按当前画像快照重新生成的自动推荐不完全一致"))
        XCTAssertTrue(ReportService.makeReport(result: result).contains("不会把它视为数量一致的自动推荐结果"))
        XCTAssertFalse(ReportService.makeReport(result: result).contains("自动推荐数量与计划选择数量一致"))
    }

    func testAutomaticSelectionRejectsRecommendationWhenRequestedIDsContainExcludedSchool() {
        var profile = strongChineseInternationalProfile
        profile.requestedSchoolCount = 3
        let automaticIDs = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let selectedIDs = automaticIDs.union(["outside_dataset"])

        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selectedIDs, selectionSource: .automatic)

        XCTAssertEqual(Set(result.schoolResults.map(\.college.id)), automaticIDs)
        XCTAssertTrue(result.selectionWarnings.contains { $0.contains("不在已审核 v1 数据集") })
        XCTAssertTrue(result.recommendedSchools.isEmpty)
        XCTAssertTrue(result.recommendationSteps.isEmpty)
        XCTAssertTrue(result.recommendationWarnings.isEmpty)
        XCTAssertTrue(ReportService.makeReport(result: result).contains("与按当前画像快照重新生成的自动推荐不完全一致"))
        XCTAssertTrue(ReportService.makeReport(result: result).contains("不会把它视为数量一致的自动推荐结果"))
        XCTAssertFalse(ReportService.makeReport(result: result).contains("自动推荐数量与计划选择数量一致"))
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

    func testDatasetStaysWithinApprovedSeedScope() {
        let source = AdmissionsSeedData.admissionsSightURL.absoluteString
        let lacSource = AdmissionsNormalizedData.liberalArtsCollegeURL.absoluteString
        let scorecardPrefix = "https://collegescorecard.ed.gov/school/?"
        let ipedsDataFilesPrefix = "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx"
        let ipedsReportedDataPrefix = "https://nces.ed.gov/ipeds/reported-data/html/"
        XCTAssertFalse(AdmissionsSeedData.colleges.isEmpty)
        XCTAssertTrue(AdmissionsSeedData.colleges.filter { $0.category == .nationalUniversity }.allSatisfy {
            $0.sourceURL.absoluteString == source ||
                ($0.sourceURL.absoluteString.hasPrefix(scorecardPrefix) && $0.sourceNote.contains("IMG_0749.JPG")) ||
                ($0.sourceURL.host == "irp.osu.edu" && $0.sourceNote.contains("IPEDS") && $0.sourceNote.contains("IMG_0749.JPG")) ||
                ($0.sourceURL.host == "oir.uga.edu" && $0.sourceNote.contains("IPEDS") && $0.sourceNote.contains("IMG_0749.JPG"))
        })
        XCTAssertTrue(AdmissionsSeedData.colleges.filter { $0.category == .liberalArtsCollege }.allSatisfy {
            $0.sourceURL.absoluteString == lacSource ||
                $0.sourceURL.absoluteString.hasPrefix(scorecardPrefix) ||
                $0.sourceURL.absoluteString.hasPrefix(ipedsDataFilesPrefix) ||
                $0.sourceURL.absoluteString.hasPrefix(ipedsReportedDataPrefix)
        })
        XCTAssertTrue(AdmissionsSeedData.colleges.allSatisfy { !$0.sourceNote.isEmpty })
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

    private func syntheticCollege(
        id: String,
        name: String,
        category: CollegeCategory = .nationalUniversity,
        rank: Int,
        rate: Double,
        sourceURL: URL? = nil,
        sourceNote: String = "Synthetic test college"
    ) -> College {
        College(
            id: id,
            name: name,
            category: category,
            rank: rank,
            acceptanceRates: [AcceptanceRate(classYear: 2029, rate: rate)],
            sourceURL: sourceURL ?? URL(string: "https://example.com/\(id)")!,
            sourceNote: sourceNote,
            dataQuality: 1
        )
    }

    private func syntheticChanceResult(
        id: String,
        name: String,
        category: CollegeCategory = .nationalUniversity,
        rank: Int,
        probability: Double,
        confidence: ConfidenceLabel = .high,
        sourceURL: URL? = nil,
        sourceNote: String = "Synthetic test college"
    ) -> ChanceResult {
        ChanceResult(
            college: syntheticCollege(
                id: id,
                name: name,
                category: category,
                rank: rank,
                rate: probability,
                sourceURL: sourceURL,
                sourceNote: sourceNote
            ),
            baseRate: probability,
            adjustedProbability: probability,
            confidence: confidence,
            bucket: .target,
            factors: [],
            warnings: [],
            gateResult: GateResult(passed: true, failedRules: [], inferredRules: [], confidenceImpact: 0)
        )
    }

    private func greedyExpectedBestOfferSteps(from results: [ChanceResult], count: Int) -> [RecommendationStep] {
        var steps: [RecommendationStep] = []
        var pickedIDs = Set<String>()

        while steps.count < count {
            let remaining = results.filter { !pickedIDs.contains($0.college.id) }
            guard let next = remaining.max(by: { lhs, rhs in
                let lhsValue = marginalExpectedBestOfferValue(for: lhs, selectedSteps: steps)
                let rhsValue = marginalExpectedBestOfferValue(for: rhs, selectedSteps: steps)
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

            let tierName = testCorrelationTierName(for: next.college)
            let tierCount = steps.filter { testCorrelationTierName(for: $0.result.college) == tierName }.count
            let discount = pow(testSameTierDecay(for: tierName), Double(tierCount))
            let marginal = marginalExpectedBestOfferValue(for: next, selectedSteps: steps)
            steps.append(RecommendationStep(
                order: steps.count + 1,
                result: next,
                rankScore: engine.recommendationRankScore(for: next.college),
                confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: next),
                baseExpectedValue: engine.recommendationExpectedValue(for: next),
                sameTierDiscount: discount,
                marginalExpectedValue: marginal
            ))
            pickedIDs.insert(next.college.id)
        }

        return steps
    }

    private func exhaustiveExpectedBestOfferSteps(from results: [ChanceResult], count: Int) -> [RecommendationStep] {
        let requested = min(max(0, count), results.count)
        guard requested > 0 else {
            return []
        }
        let sortedResults = results.sorted { lhs, rhs in
            let lhsValue = engine.recommendationExpectedValue(for: lhs)
            let rhsValue = engine.recommendationExpectedValue(for: rhs)
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
                let steps = bestOrderingExpectedBestOfferSteps(from: current)
                let value = engine.recommendationBestOfferExpectedValue(for: steps)
                if value > bestValue + 0.0001 {
                    bestSteps = steps
                    bestValue = value
                }
                return
            }

            let remainingSlots = requested - current.count
            guard sortedResults.count - startIndex >= remainingSlots else {
                return
            }
            let lastStart = sortedResults.count - remainingSlots
            guard startIndex <= lastStart else {
                return
            }

            for index in startIndex...lastStart {
                current.append(sortedResults[index])
                search(startIndex: index + 1)
                current.removeLast()
            }
        }

        search(startIndex: 0)
        return bestSteps
    }

    private func bestOrderingExpectedBestOfferSteps(from results: [ChanceResult]) -> [RecommendationStep] {
        let current = recommendationStepsInTestOrder(from: results)
        let greedy = greedyExpectedBestOfferSteps(from: results, count: results.count)
        let rankPriority = recommendationStepsInTestOrder(from: results.sorted { lhs, rhs in
            let lhsRankScore = engine.recommendationRankScore(for: lhs.college)
            let rhsRankScore = engine.recommendationRankScore(for: rhs.college)
            if lhsRankScore == rhsRankScore {
                if lhs.adjustedProbability == rhs.adjustedProbability {
                    if lhs.college.rank == rhs.college.rank {
                        return lhs.college.name < rhs.college.name
                    }
                    return lhs.college.rank < rhs.college.rank
                }
                return lhs.adjustedProbability > rhs.adjustedProbability
            }
            return lhsRankScore > rhsRankScore
        })
        let currentValue = engine.recommendationBestOfferExpectedValue(for: current)
        let greedyValue = engine.recommendationBestOfferExpectedValue(for: greedy)
        let bestCurrentOrGreedy = currentValue > greedyValue + 0.0001 ? current : greedy
        let bestCurrentOrGreedyValue = max(currentValue, greedyValue)
        return engine.recommendationBestOfferExpectedValue(for: rankPriority) > bestCurrentOrGreedyValue + 0.0001
            ? rankPriority
            : bestCurrentOrGreedy
    }

    private func recommendationStepsInTestOrder(from results: [ChanceResult]) -> [RecommendationStep] {
        var steps: [RecommendationStep] = []
        var tierCounts: [String: Int] = [:]

        for result in results {
            let tierName = testCorrelationTierName(for: result.college)
            let tierCount = tierCounts[tierName, default: 0]
            let discount = pow(testSameTierDecay(for: tierName), Double(tierCount))
            let stepWithoutMarginal = RecommendationStep(
                order: steps.count + 1,
                result: result,
                rankScore: engine.recommendationRankScore(for: result.college),
                confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: result),
                baseExpectedValue: engine.recommendationExpectedValue(for: result),
                sameTierDiscount: discount,
                marginalExpectedValue: 0
            )
            let marginal = engine.recommendationBestOfferExpectedValue(for: steps + [stepWithoutMarginal]) -
                engine.recommendationBestOfferExpectedValue(for: steps)
            steps.append(RecommendationStep(
                order: stepWithoutMarginal.order,
                result: stepWithoutMarginal.result,
                rankScore: stepWithoutMarginal.rankScore,
                confidenceMultiplier: stepWithoutMarginal.confidenceMultiplier,
                baseExpectedValue: stepWithoutMarginal.baseExpectedValue,
                sameTierDiscount: stepWithoutMarginal.sameTierDiscount,
                marginalExpectedValue: marginal
            ))
            tierCounts[tierName, default: 0] = tierCount + 1
        }

        return steps
    }

    private func marginalExpectedBestOfferValue(for result: ChanceResult, selectedSteps: [RecommendationStep]) -> Double {
        let tierName = testCorrelationTierName(for: result.college)
        let tierCount = selectedSteps.filter { testCorrelationTierName(for: $0.result.college) == tierName }.count
        let discount = pow(testSameTierDecay(for: tierName), Double(tierCount))
        let step = RecommendationStep(
            order: selectedSteps.count + 1,
            result: result,
            rankScore: engine.recommendationRankScore(for: result.college),
            confidenceMultiplier: engine.recommendationConfidenceMultiplier(for: result),
            baseExpectedValue: engine.recommendationExpectedValue(for: result),
            sameTierDiscount: discount,
            marginalExpectedValue: 0
        )
        return engine.recommendationBestOfferExpectedValue(for: selectedSteps + [step]) - engine.recommendationBestOfferExpectedValue(for: selectedSteps)
    }

    private func testCorrelationTierName(for college: College) -> String {
        if college.rank <= 10 {
            return "T10"
        }
        return college.tierName
    }

    private func testSameTierDecay(for tierName: String) -> Double {
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
}
