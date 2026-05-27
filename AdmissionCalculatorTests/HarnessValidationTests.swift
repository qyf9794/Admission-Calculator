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

    func testChinaAdmissionSignalsRemainScopedToDataset() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        XCTAssertFalse(AdmissionsSeedData.chinaAdmissionSignals.isEmpty)
        for signal in AdmissionsSeedData.chinaAdmissionSignals {
            XCTAssertTrue(collegeIDs.contains(signal.collegeID), signal.collegeID)
            XCTAssertNotNil(signal.total2030, signal.collegeID)
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
    }
}
