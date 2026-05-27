import XCTest
@testable import AdmissionCalculator

final class HarnessValidationTests: XCTestCase {
    func testGeneratedDataSnapshotHasMetadataAndSources() {
        XCTAssertFalse(AdmissionsSeedData.dataVersion.isEmpty)
        XCTAssertFalse(AdmissionsSeedData.generatedAt.isEmpty)
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "admissionsight_acceptance_rates" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "official_cds_gates" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "international_student_signals" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "china_undergrad_admissions" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "academic_benchmark_proxy" })
    }

    func testAdmissionSightDatasetHasLatestAvailableRates() {
        for college in AdmissionsSeedData.colleges {
            XCTAssertGreaterThan(college.latestAvailableRate, 0, college.name)
            XCTAssertLessThanOrEqual(college.latestAvailableRate, 1, college.name)
        }
    }

    func testAdmissionSightRatesAndRanksStayInBounds() {
        for college in AdmissionsSeedData.colleges {
            XCTAssertGreaterThan(college.rank, 0, college.name)
            XCTAssertLessThanOrEqual(college.rank, 500, college.name)
            for rate in college.acceptanceRates.compactMap(\.rate) {
                XCTAssertGreaterThan(rate, 0, college.name)
                XCTAssertLessThanOrEqual(rate, 1, college.name)
            }
        }
    }

    func testGeneratedDataKeepsGateTargetsInsideAdmissionSightScope() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        for rule in AdmissionsSeedData.gateRules where rule.collegeID != "*" {
            XCTAssertTrue(collegeIDs.contains(rule.collegeID), rule.id)
        }
    }

    func testInternationalSignalsCoverAdmissionSightDataset() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        let signalIDs = Set(AdmissionsSeedData.internationalSignals.map(\.collegeID))

        XCTAssertEqual(signalIDs, collegeIDs)
        XCTAssertTrue(AdmissionsSeedData.internationalSignals.allSatisfy(\.isUndergradOnly))
    }

    func testInternationalAdmitCoefficientRequiresAdmittedCounts() {
        for signal in AdmissionsSeedData.internationalSignals where signal.internationalAdmitCoefficient != nil {
            XCTAssertNotNil(signal.internationalAdmittedCount, signal.collegeID)
            XCTAssertNotNil(signal.totalAdmittedCount, signal.collegeID)
        }
    }

    func testMITUsesOfficialAdmissionsStatsForInternationalSignal() {
        let signal = AdmissionsSeedData.internationalSignals.first { $0.collegeID == "mit" }

        XCTAssertEqual(signal?.internationalAdmittedCount, 136)
        XCTAssertEqual(signal?.totalAdmittedCount, 1334)
        XCTAssertEqual(signal?.internationalAdmitCoefficient ?? 0, 0.1019, accuracy: 0.0001)
        XCTAssertTrue(signal?.sourceURL?.absoluteString.contains("mitadmissions.org/apply/process/stats") == true)
        XCTAssertTrue(signal?.sourceFields.contains("official_admissions_statistics.international_admitted_count") == true)
    }

    func testChinaAdmissionSignalsRemainScopedToDataset() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        XCTAssertFalse(AdmissionsSeedData.chinaAdmissionSignals.isEmpty)
        for signal in AdmissionsSeedData.chinaAdmissionSignals {
            XCTAssertTrue(collegeIDs.contains(signal.collegeID), signal.collegeID)
            XCTAssertNotNil(signal.total2030, signal.collegeID)
        }
    }

    func testChinaAdmissionRoundCountsReconcileWithTotals() {
        for signal in AdmissionsSeedData.chinaAdmissionSignals {
            assertChinaTotal(signal.early2028, signal.rd2028, signal.total2028, signal.collegeID)
            assertChinaTotal(signal.early2029, signal.rd2029, signal.total2029, signal.collegeID)
            assertChinaTotal(signal.early2030, signal.rd2030, signal.total2030, signal.collegeID)
        }
    }

    func testChinaShareRequiresAllAdmitsDenominator() {
        for signal in AdmissionsSeedData.chinaAdmissionSignals where signal.chinaShareOfAllAdmits != nil {
            XCTAssertFalse(signal.sourceNote.isEmpty, signal.collegeID)
        }
    }

    func testAcademicBenchmarksCoverAdmissionSightDatasetAndDiscloseInference() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        let benchmarkIDs = Set(AdmissionsSeedData.academicBenchmarks.map(\.collegeID))

        XCTAssertEqual(benchmarkIDs, collegeIDs)
        XCTAssertTrue(AdmissionsSeedData.academicBenchmarks.allSatisfy { !$0.sourceNote.isEmpty })
        XCTAssertTrue(AdmissionsSeedData.academicBenchmarks.filter(\.isInferred).allSatisfy { $0.dataQuality < 0.6 })
    }

    func testMITAcademicBenchmarkDisclosesMixedOfficialAndInferredFields() {
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == "mit" }
        let result = ChanceEngine().chance(
            for: AdmissionsSeedData.colleges.first { $0.id == "mit" }!,
            profile: .sample
        )
        let detail = result.factors.first { $0.label == "目标校学术匹配" }?.detail ?? ""
        let report = ReportService.makeReport(result: ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["mit"])))

        XCTAssertEqual(benchmark?.satBenchmark, 1550)
        XCTAssertEqual(benchmark?.actBenchmark, 35)
        XCTAssertTrue(benchmark?.sourceFields.contains("official_class_profile_sat_act_midpoint") == true)
        XCTAssertTrue(detail.contains("部分官方/部分推断基准"))
        XCTAssertTrue(report.contains("部分官方/部分推断"))
        XCTAssertTrue(report.contains("MIT Class of 2029 official SAT/ACT"))
    }

    func testPerSchoolSourceAuditDataIsDisplayable() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        let internationalIDs = Set(AdmissionsSeedData.internationalSignals.map(\.collegeID))
        let chinaIDs = Set(AdmissionsSeedData.chinaAdmissionSignals.map(\.collegeID))
        let benchmarkIDs = Set(AdmissionsSeedData.academicBenchmarks.map(\.collegeID))

        XCTAssertEqual(internationalIDs, collegeIDs)
        XCTAssertTrue(chinaIDs.isSubset(of: collegeIDs))
        XCTAssertFalse(chinaIDs.isEmpty)
        XCTAssertEqual(benchmarkIDs, collegeIDs)
        XCTAssertTrue(AdmissionsSeedData.internationalSignals.allSatisfy { !$0.sourceNote.isEmpty })
        XCTAssertTrue(AdmissionsSeedData.chinaAdmissionSignals.allSatisfy { !$0.sourceNote.isEmpty })
        XCTAssertTrue(AdmissionsSeedData.academicBenchmarks.allSatisfy { !$0.sourceNote.isEmpty })
        XCTAssertTrue(AdmissionsSeedData.gateRules.contains { $0.collegeID == "*" && !$0.isOfficial })
    }

    func testDataQualityAndProxyValuesStayInBounds() {
        for signal in AdmissionsSeedData.internationalSignals {
            XCTAssertGreaterThanOrEqual(signal.dataQuality, 0, signal.collegeID)
            XCTAssertLessThanOrEqual(signal.dataQuality, 1, signal.collegeID)
            if let share = signal.undergradNonresidentShare {
                XCTAssertGreaterThanOrEqual(share, 0, signal.collegeID)
                XCTAssertLessThanOrEqual(share, 1, signal.collegeID)
            }
            if let coefficient = signal.internationalAdmitCoefficient {
                XCTAssertGreaterThanOrEqual(coefficient, 0, signal.collegeID)
                XCTAssertLessThanOrEqual(coefficient, 1, signal.collegeID)
            }
        }

        for signal in AdmissionsSeedData.chinaAdmissionSignals {
            XCTAssertGreaterThanOrEqual(signal.dataQuality, 0, signal.collegeID)
            XCTAssertLessThanOrEqual(signal.dataQuality, 1, signal.collegeID)
            if let share = signal.chinaShareOfAllAdmits {
                XCTAssertGreaterThanOrEqual(share, 0, signal.collegeID)
                XCTAssertLessThanOrEqual(share, 1, signal.collegeID)
            }
        }

        for benchmark in AdmissionsSeedData.academicBenchmarks {
            XCTAssertGreaterThanOrEqual(benchmark.dataQuality, 0, benchmark.collegeID)
            XCTAssertLessThanOrEqual(benchmark.dataQuality, 1, benchmark.collegeID)
        }
    }

    func testInferredRulesAreExplicitlyMarked() {
        let inferred = AdmissionsSeedData.gateRules.filter { !$0.isOfficial }
        XCTAssertFalse(inferred.isEmpty)
        XCTAssertTrue(inferred.allSatisfy { $0.sourceURL == nil || $0.sourceURL?.scheme?.hasPrefix("http") == true })
    }

    func testOfficialGateRulesHaveSources() {
        let official = AdmissionsSeedData.gateRules.filter(\.isOfficial)
        XCTAssertFalse(official.isEmpty)
        XCTAssertTrue(official.allSatisfy { $0.sourceURL != nil })
    }

    func testNoReportCanChangeComputedProbabilities() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "tufts"]))
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("不改变概率"))
        XCTAssertTrue(report.contains("不承诺录取"))
        XCTAssertTrue(report.contains("保底是相对规划标签，不代表录取保证"))
    }

    func testReportIncludesComputedWarningsAndDataLimitations() {
        var profile = StudentProfile.sample
        profile.major = .humanities
        profile.curriculum = .ap
        profile.apCourseCount = 0
        profile.apAverageScore = 5.0

        let result = ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["bu"]))
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("数据限制与警告"))
        XCTAssertTrue(report.contains("Boston University"))
        XCTAssertTrue(report.contains("AP 体系课程门数为 0"))
        XCTAssertTrue(report.contains("目标校学术基准为推断值"))
    }

    func testReportIncludesEverySelectedSchoolProbabilityAndFit() {
        let selected = Set(["princeton", "mit", "harvard", "stanford", "yale", "bu"])
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: selected, selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        for school in result.schoolResults {
            XCTAssertTrue(report.contains("\(school.college.name)：\(school.adjustedProbability.formatted(.percent.precision(.fractionLength(0))))"))
            XCTAssertTrue(report.contains("置信度 \(school.confidence.rawValue)"))
            XCTAssertTrue(report.contains("\(school.college.name)："))
        }
        XCTAssertEqual(result.schoolResults.count, selected.count)
        XCTAssertTrue(report.contains("Boston University"))
    }

    func testReportIncludesFailedGateReasonsAndSources() {
        var profile = StudentProfile.sample
        profile.testOptional = true
        profile.sat = nil
        profile.act = nil

        let result = ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["mit"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("硬门槛"))
        XCTAssertTrue(report.contains("官方 Required standardized testing"))
        XCTAssertTrue(report.contains("MIT requires SAT/ACT"))
        XCTAssertTrue(report.contains("https://mitadmissions.org/apply/firstyear/tests-scores/"))
    }

    func testFailedGateDisplaySummaryIncludesSourceURL() {
        let rule = AdmissionsSeedData.gateRules.first { $0.id == "mit_sat" }!
        let summary = GateRuleDisplay.failureSummary(rule)

        XCTAssertTrue(summary.contains("官方 Required standardized testing"))
        XCTAssertTrue(summary.contains("MIT requires SAT/ACT"))
        XCTAssertTrue(summary.contains("https://mitadmissions.org/apply/firstyear/tests-scores/"))
    }

    func testReportIncludesSelectedSchoolSourceAudit() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("逐校数据来源审计"))
        XCTAssertTrue(report.contains("Boston University：录取率"))
        XCTAssertTrue(report.contains("AdmissionSight National Universities"))
        XCTAssertTrue(report.contains("国际生"))
        XCTAssertTrue(report.contains("中国本科"))
        XCTAssertTrue(report.contains("学术基准"))
        XCTAssertTrue(report.contains("硬门槛"))
    }

    func testReportSourceAuditIncludesStructuredRoundPolicy() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["mit"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("First-year application rounds"))
        XCTAssertTrue(report.contains("允许轮次 EA/RD"))
        XCTAssertTrue(report.contains("EA加分 +0.00"))
        XCTAssertTrue(report.contains("ED加分 无明确数据"))
    }

    func testCaltechRoundPolicySourceAuditUsesOfficialDeadlinePage() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["caltech"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("Caltech offers Restrictive Early Action and Regular Decision"))
        XCTAssertTrue(report.contains("允许轮次 EA/RD"))
        XCTAssertTrue(report.contains("EA加分 +0.00"))
        XCTAssertTrue(report.contains("https://www.admissions.caltech.edu/apply/first-year-applicants/deadlines"))
    }

    private func assertChinaTotal(_ early: Int?, _ rd: Int?, _ total: Int?, _ collegeID: String) {
        guard let early, let rd, let total else {
            return
        }
        XCTAssertEqual(early + rd, total, collegeID)
    }
}
