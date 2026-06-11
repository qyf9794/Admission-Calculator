import XCTest
import PDFKit
@testable import AdmissionCalculator

final class HarnessValidationTests: XCTestCase {
    func testReportPDFRendererWritesReadableText() throws {
        var profile = StudentProfile.sample
        profile.round = .regularDecision
        let result = ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["bu", "mit"]))
        let report = ReportService.makeReport(result: result) + """

        | 学校 | 概率 | 分类 |
        | --- | --- | --- |
        | Boston University | 50% | 目标 |
        | MIT | 2% | 争取 |
        """
        let url = try ReportPDFRenderer.write(
            text: report,
            result: result,
            fileName: "Admission-Report-Test-\(UUID().uuidString).pdf"
        )
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(fileSize, 1_000)

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 0)
        let extractedText = document.string ?? ""
        XCTAssertTrue(extractedText.contains("美本录取计算器"))
        XCTAssertTrue(extractedText.contains("Admission Report"))
        XCTAssertTrue(extractedText.contains("Boston University"))
        XCTAssertTrue(extractedText.contains("分类"))
        XCTAssertFalse(extractedText.contains("| --- |"))

        let firstPage = try XCTUnwrap(document.page(at: 0))
        let renderedPage = firstPage.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        let nonWhitePixels = try renderedPage.nonWhitePixelCount(in: CGRect(x: 40, y: 120, width: 515, height: 190))
        XCTAssertGreaterThan(nonWhitePixels, 1_000, "The PDF should render visible text or probability cards outside the logo area.")
    }

    func testGeneratedDataSnapshotHasMetadataAndSources() {
        XCTAssertFalse(AdmissionsSeedData.dataVersion.isEmpty)
        XCTAssertFalse(AdmissionsSeedData.generatedAt.isEmpty)
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "admissionsight_acceptance_rates" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "usnews_2026_t50_user_image" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "college_scorecard_national_university_supplement" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "ipeds_national_university_supplement" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "liberal_arts_top30_user_table" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "college_scorecard_lac_rate_review" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "ipeds_lac_rate_review" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "liberal_arts_unitid_map" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "official_cds_gates" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "international_student_signals" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "china_undergrad_admissions" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "academic_benchmark_proxy" })
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains { $0.id == "major_selectivity_signals" })
    }

    func testCurrentLiberalArtsBaseRatesUseReviewedOfficialScorecardRows() {
        let liberalArts = AdmissionsSeedData.colleges.filter { $0.category == .liberalArtsCollege }
        let scorecardPrefix = "https://collegescorecard.ed.gov/school/?"
        let scorecardSource = AdmissionsSeedData.sourceRecords.first { $0.id == "college_scorecard_lac_rate_review" }

        XCTAssertEqual(AdmissionsSeedData.dataVersion, "2026.05.usnews-t50-official-supplement.v1")
        XCTAssertEqual(liberalArts.count, 30)
        XCTAssertTrue(scorecardSource?.note.contains("official Scorecard rates were applied") == true)
        XCTAssertTrue(liberalArts.allSatisfy { $0.sourceURL.absoluteString.hasPrefix(scorecardPrefix) })
        XCTAssertTrue(liberalArts.allSatisfy { $0.sourceNote.contains("official base rate applied via UNITID") })
        XCTAssertTrue(liberalArts.allSatisfy { $0.sourceNote.contains("Original IMG_0742.JPG table retained for LAC list/rank scope") })
        XCTAssertTrue(liberalArts.allSatisfy { $0.dataQuality >= 0.9 })

        let colby = liberalArts.first { $0.id == "colby" }
        let coloradoCollege = liberalArts.first { $0.id == "colorado_college" }
        XCTAssertEqual(colby?.latestAvailableRate ?? 0, 0.0709, accuracy: 0.0001)
        XCTAssertEqual(coloradoCollege?.latestAvailableRate ?? 0, 0.1847, accuracy: 0.0001)
    }

    func testDataSourceSearchMatchesRoleNoteConfidenceAndURL() {
        let source = AdmissionsSeedData.sourceRecords.first { $0.id == "admissionsight_acceptance_rates" }!

        XCTAssertTrue(source.matchesSourceQuery("AdmissionSight"))
        XCTAssertTrue(source.matchesSourceQuery("statistics"))
        XCTAssertTrue(source.matchesSourceQuery(source.confidence))
        XCTAssertTrue(source.matchesSourceQuery("college-acceptance-rates"))
        XCTAssertFalse(source.matchesSourceQuery("not-a-source"))
    }

    func testAdmissionSightDatasetHasLatestAvailableRates() {
        for college in AdmissionsSeedData.colleges {
            XCTAssertGreaterThan(college.latestAvailableRate, 0, college.name)
            XCTAssertLessThanOrEqual(college.latestAvailableRate, 1, college.name)
        }
    }

    func testOfficialRoundPoliciesCoverApprovedDataset() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))
        let roundRules = AdmissionsSeedData.gateRules.filter { $0.type == .round }
        let roundIDs = Set(roundRules.map(\.collegeID))

        XCTAssertTrue(collegeIDs.subtracting(roundIDs).isEmpty)
        XCTAssertTrue(roundRules.allSatisfy { !$0.allowedRounds.isEmpty })
        XCTAssertTrue(roundRules.allSatisfy { $0.isOfficial })
        XCTAssertTrue(roundRules.allSatisfy { $0.sourceURL != nil })
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "duke" && $0.type == .round }
            .first?.allowedRounds, [.earlyDecision, .regularDecision])
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "duke" && $0.type == .round }
            .first?.earlyDecisionAdjustment, 0.65)
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "princeton" && $0.type == .round }
            .first?.earlyActionAdjustment, 0.35)
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "mit" && $0.type == .round }
            .first?.allowedRounds, [.earlyAction, .regularDecision])
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "mit" && $0.type == .round }
            .first?.earlyActionAdjustment, 0)
        XCTAssertEqual(AdmissionsSeedData.gateRules
            .filter { $0.collegeID == "uc_berkeley" && $0.type == .round }
            .first?.allowedRounds, [.regularDecision])
    }

    func testNationalUniversityT50SupplementIsCompleteFromUSNewsImage() {
        let expectedSupplementIDs: Set<String> = [
            "wisconsin",
            "ucsb",
            "ohio_state",
            "rutgers_nb",
            "umd",
            "uw_seattle",
            "lehigh",
            "purdue",
            "uga",
            "rochester"
        ]
        let nationalUniversities = AdmissionsSeedData.colleges.filter { $0.category == .nationalUniversity }
        let nationalIDs = Set(nationalUniversities.map(\.id))

        XCTAssertTrue(expectedSupplementIDs.isSubset(of: nationalIDs))
        XCTAssertEqual(nationalUniversities.first { $0.id == "ohio_state" }?.rank, 41)
        XCTAssertEqual(nationalUniversities.first { $0.id == "rochester" }?.rank, 46)
        XCTAssertEqual(nationalUniversities.first { $0.id == "ohio_state" }?.latestAvailableRate ?? 0, 0.6057, accuracy: 0.0001)
        XCTAssertEqual(nationalUniversities.first { $0.id == "uga" }?.latestAvailableRate ?? 0, 0.3769, accuracy: 0.0001)
        XCTAssertTrue(nationalUniversities
            .filter { expectedSupplementIDs.contains($0.id) }
            .allSatisfy { $0.sourceNote.contains("IMG_0749.JPG") })
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

    func testCollegePickerSearchMatchesNameRankIDAndTier() {
        let mit = AdmissionsSeedData.colleges.first { $0.id == "mit" }!
        let florida = AdmissionsSeedData.colleges.first { $0.id == "uf" }!
        let caseWestern = AdmissionsSeedData.colleges.first { $0.id == "case" }!
        let williams = AdmissionsSeedData.colleges.first { $0.id == "williams" }!
        let barnard = AdmissionsSeedData.colleges.first { $0.id == "barnard" }!

        XCTAssertEqual(mit.tierDisplayName, "综合大学 T10")
        XCTAssertEqual(caseWestern.tierDisplayName, "综合大学 50+")
        XCTAssertEqual(williams.tierDisplayName, "文理学院 T10")
        XCTAssertEqual(barnard.tierDisplayName, "文理学院 T30")
        XCTAssertTrue(mit.matchesPickerQuery("MIT"))
        XCTAssertTrue(mit.matchesPickerQuery("mit"))
        XCTAssertTrue(mit.matchesPickerQuery("#2"))
        XCTAssertTrue(mit.matchesPickerQuery("T10"))
        XCTAssertTrue(mit.matchesPickerQuery("T30"))
        XCTAssertTrue(mit.matchesPickerQuery("T50"))
        XCTAssertFalse(mit.matchesPickerQuery("Listed"))
        XCTAssertTrue(florida.matchesPickerQuery("T30"))
        XCTAssertTrue(florida.matchesPickerQuery("T50"))
        XCTAssertFalse(florida.matchesPickerQuery("T10"))
        XCTAssertTrue(caseWestern.matchesPickerQuery("Listed"))
        XCTAssertTrue(caseWestern.matchesPickerQuery("50+"))
        XCTAssertTrue(caseWestern.matchesPickerQuery("T50+"))
        XCTAssertTrue(caseWestern.matchesPickerQuery("综合大学 50+"))
        XCTAssertFalse(caseWestern.matchesPickerQuery("T50"))
        XCTAssertTrue(williams.matchesPickerQuery("文理学院"))
        XCTAssertTrue(williams.matchesPickerQuery("LAC T10"))
        XCTAssertTrue(barnard.matchesPickerQuery("文理学院 T30"))
        XCTAssertFalse(williams.matchesPickerQuery("综合大学 T10"))
        XCTAssertFalse(mit.matchesPickerQuery("文理学院"))
        XCTAssertFalse(mit.matchesPickerQuery("50+"))
        XCTAssertFalse(mit.matchesPickerQuery("not-a-school"))
    }

    func testCollegeSourceAuditSearchMatchesSourceNotesURLsAndGateDetails() {
        let mit = AdmissionsSeedData.colleges.first { $0.id == "mit" }!
        let internationalSignal = AdmissionsSeedData.internationalSignals.first { $0.collegeID == mit.id }
        let chinaSignal = AdmissionsSeedData.chinaAdmissionSignals.first { $0.collegeID == mit.id }
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == mit.id }
        let gateRules = AdmissionsSeedData.gateRules.filter { $0.collegeID == mit.id || $0.collegeID == "*" }

        XCTAssertTrue(mit.matchesSourceAuditQuery("process/stats", internationalSignal: internationalSignal, chinaSignal: chinaSignal, academicBenchmark: benchmark, gateRules: gateRules))
        XCTAssertTrue(mit.matchesSourceAuditQuery("official_class_profile_sat_act_midpoint", internationalSignal: internationalSignal, chinaSignal: chinaSignal, academicBenchmark: benchmark, gateRules: gateRules))
        XCTAssertTrue(mit.matchesSourceAuditQuery("Required standardized testing", internationalSignal: internationalSignal, chinaSignal: chinaSignal, academicBenchmark: benchmark, gateRules: gateRules))
        XCTAssertTrue(mit.matchesSourceAuditQuery("IMG_0740", internationalSignal: internationalSignal, chinaSignal: chinaSignal, academicBenchmark: benchmark, gateRules: gateRules))
        XCTAssertFalse(mit.matchesSourceAuditQuery("not-a-source-field", internationalSignal: internationalSignal, chinaSignal: chinaSignal, academicBenchmark: benchmark, gateRules: gateRules))
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

    func testUnknownHighSchoolFallbackStaysConservative() {
        let unknown = AdmissionsSeedData.highSchools.first { $0.id == "unknown" }

        XCTAssertEqual(StudentProfile.sample.highSchoolID, "unknown")
        XCTAssertNotNil(unknown)
        XCTAssertGreaterThanOrEqual(unknown?.admitRankingBand ?? 0, 3)
        XCTAssertLessThanOrEqual(unknown?.resources ?? 99, 3)
        XCTAssertLessThanOrEqual(unknown?.counseling ?? 99, 3)
        XCTAssertLessThanOrEqual(unknown?.top30TrackRecord ?? 99, 2)
        XCTAssertLessThanOrEqual(unknown?.transparency ?? 99, 3)
    }

    func testAdmitRankingHighSchoolContextHasExpandedReviewedCoverage() {
        let schoolIDs = Set(AdmissionsSeedData.highSchools.map(\.id))

        XCTAssertGreaterThanOrEqual(AdmissionsSeedData.highSchools.count, 90)
        XCTAssertEqual(AdmissionsSeedData.highSchools.first?.id, "unknown")
        XCTAssertTrue(schoolIDs.isSuperset(of: [
            "bnu_experimental",
            "rdfz_icc",
            "shsid",
            "shenzhen_middle",
            "uwc_changshu",
            "unknown"
        ]))
        XCTAssertLessThan(
            AdmissionsSeedData.highSchools.filter { $0.admitRankingBand == 1 }.count,
            AdmissionsSeedData.highSchools.count / 2
        )
    }

    func testHighSchoolDirectoryKeepsStaticInitialOrder() {
        let highSchools = AdmissionsSeedData.highSchools

        XCTAssertEqual(highSchools.first?.id, "unknown")
        XCTAssertEqual(
            Array(highSchools.dropFirst().prefix(4).map(\.id)),
            ["ar_288", "ar_161", "ar_13479", "bnu_experimental"]
        )
        XCTAssertEqual(Array(highSchools.suffix(2).map(\.id)), ["uwc_changshu", "ar_518"])
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

    func testMajorSelectivitySignalsAreScopedAndDisclosed() {
        let collegeIDs = Set(AdmissionsSeedData.colleges.map(\.id))

        XCTAssertGreaterThanOrEqual(AdmissionsSeedData.majorSelectivitySignals.count, 20)
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.allSatisfy { collegeIDs.contains($0.collegeID) })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.allSatisfy(\.isUndergradFirstYear))
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.allSatisfy { !$0.sourceNote.isEmpty })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.allSatisfy { $0.sourceURL.scheme?.hasPrefix("http") == true })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.allSatisfy { signal in
            guard let classYear = signal.classYear else {
                return true
            }
            return classYear >= signal.entryYear && classYear <= signal.entryYear + 6
        })
        XCTAssertFalse(MajorCategory.allCases.contains { $0.rawValue == "Nursing / Health" })
        XCTAssertFalse(MajorCategory.allCases.contains { $0.rawValue == "Film / Media / Design" })
        XCTAssertTrue(MajorCategory.allCases.contains(.nursing))
        XCTAssertTrue(MajorCategory.allCases.contains(.film))
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.contains {
            $0.collegeID == "ucla" &&
                $0.majorCategory == .nursing &&
                $0.entryYear == 2025 &&
                $0.classYear == 2029 &&
                $0.admitRate == 0.005 &&
                $0.sourceTier == .official
        })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.contains {
            $0.collegeID == "ucla" &&
                $0.majorCategory == .film &&
                $0.programLabel == "Film and Television" &&
                $0.admitRate == 0.013
        })
        XCTAssertFalse(AdmissionsSeedData.majorSelectivitySignals.contains {
            $0.programLabel == "Design Media Arts" &&
                $0.majorCategory == .film
        })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.contains {
            $0.collegeID == "uw_seattle" &&
                $0.majorCategory == .computerScience &&
                $0.entryYear == 2025 &&
                $0.classYear == nil
        })
        XCTAssertTrue(AdmissionsSeedData.majorSelectivitySignals.contains {
            $0.collegeID == "cmu" &&
                $0.majorCategory == .computerScience &&
                $0.entryYear == 2025 &&
                $0.classYear == 2029 &&
                $0.sourceTier == .consultantEstimate &&
                !$0.isDirectAdmitRate
        })
    }

    func testMajorSelectivitySignalSearchesInSourceAudit() {
        let ucla = AdmissionsSeedData.colleges.first { $0.id == "ucla" }!
        let internationalSignal = AdmissionsSeedData.internationalSignals.first { $0.collegeID == ucla.id }
        let chinaSignal = AdmissionsSeedData.chinaAdmissionSignals.first { $0.collegeID == ucla.id }
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == ucla.id }
        let gateRules = AdmissionsSeedData.gateRules.filter { $0.collegeID == ucla.id || $0.collegeID == "*" }
        let majorSignals = AdmissionsSeedData.majorSelectivitySignals.filter { $0.collegeID == ucla.id }

        XCTAssertTrue(ucla.matchesSourceAuditQuery(
            "Nursing Prelicensure",
            internationalSignal: internationalSignal,
            chinaSignal: chinaSignal,
            academicBenchmark: benchmark,
            gateRules: gateRules,
            majorSelectivitySignals: majorSignals
        ))
    }

    func testMITAcademicBenchmarkDisclosesMixedOfficialAndInferredFields() {
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == "mit" }
        var profile = StudentProfile.sample
        profile.testOptional = false
        profile.sat = 1560
        profile.toefl = 110
        let result = ChanceEngine().chance(
            for: AdmissionsSeedData.colleges.first { $0.id == "mit" }!,
            profile: profile
        )
        let detail = result.factors.first { $0.label == "目标校学术匹配" }?.detail ?? ""
        let report = ReportService.makeReport(result: ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["mit"])))

        XCTAssertEqual(benchmark?.satBenchmark, 1550)
        XCTAssertEqual(benchmark?.actBenchmark, 35)
        XCTAssertTrue(benchmark?.sourceFields.contains("official_class_profile_sat_act_midpoint") == true)
        XCTAssertTrue(detail.contains("部分官方/部分推断基准"))
        XCTAssertFalse(report.contains("MIT Class of 2029 official SAT/ACT"))
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
        XCTAssertTrue(report.contains("历史数据与外部环境说明"))
        XCTAssertTrue(report.contains("历史公开数据和本地模型校准的参考"))
        XCTAssertTrue(report.contains("经济兴衰"))
        XCTAssertTrue(report.contains("行业景气度"))
        XCTAssertTrue(report.contains("就业市场"))
        XCTAssertTrue(report.contains("AI 对计算机、商科、传媒、设计等方向"))
        XCTAssertTrue(report.contains("可能出现较大波动"))
    }

    func testReportFocusesOnUsefulInputsInsteadOfSystemDataLimitations() {
        var profile = StudentProfile.sample
        profile.major = .humanities
        profile.curriculum = .ap
        profile.apCourseCount = 0
        profile.apAverageScore = 5.0

        let result = ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["bu"]))
        let report = ReportService.makeReport(result: result)

        XCTAssertFalse(report.contains("数据限制与警告"))
        XCTAssertFalse(report.contains("逐校数据来源审计"))
        XCTAssertTrue(report.contains("提高申请数量对概率的影响"))
        XCTAssertTrue(report.contains("边际收益测算"))
        XCTAssertTrue(report.contains("精力约束"))
        XCTAssertTrue(report.contains("申请不是越多越好"))
        XCTAssertTrue(report.contains("目前影响概率较大的因素"))
        XCTAssertTrue(report.contains("Boston University"))
        XCTAssertTrue(report.contains("AP 门数为 0"))
    }

    func testReportIncludesEverySelectedSchoolProbabilityAndFit() {
        let selected = Set(["princeton", "mit", "harvard", "stanford", "yale", "bu"])
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: selected, selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        for school in result.schoolResults {
            XCTAssertTrue(report.contains("| \(school.college.name) |"))
            XCTAssertTrue(report.contains(school.adjustedProbability.formatted(.percent.precision(.fractionLength(0)))))
            XCTAssertFalse(report.contains("置信度 \(school.confidence.rawValue)"))
            XCTAssertTrue(report.contains("\(school.college.name)："))
        }
        XCTAssertTrue(report.contains("概率分析结果"))
        XCTAssertTrue(report.contains("每所学校差距和优势比较"))
        XCTAssertTrue(report.contains("这里的“可比水平”是本地模型可用的学校平均/内部参考线"))
        XCTAssertTrue(report.contains("逐校策略摘要"))
        XCTAssertFalse(report.contains("学校简表"))
        XCTAssertFalse(report.contains("逐校精简判断"))
        XCTAssertTrue(report.contains("学术匹配"))
        XCTAssertTrue(report.contains("成绩位置"))
        XCTAssertTrue(report.contains("班级位置"))
        XCTAssertTrue(report.contains("课程挑战度"))
        XCTAssertTrue(report.contains("该校可比水平"))
        XCTAssertFalse(report.contains("图标说明"))
        XCTAssertFalse(report.contains("▲"))
        XCTAssertFalse(report.contains("●"))
        XCTAssertFalse(report.contains("▼"))
        XCTAssertTrue(report.contains("关键风险"))
        XCTAssertTrue(report.contains("主要驱动"))
        XCTAssertTrue(report.contains("优先动作"))
        XCTAssertTrue(report.contains("申请策略与提升动作"))
        XCTAssertTrue(report.contains("0-1 个月优先动作"))
        XCTAssertEqual(result.schoolResults.count, selected.count)
        XCTAssertTrue(report.contains("Boston University"))
    }

    func testReportIncludesFailedGateReasonsWithoutSourceAudit() {
        var profile = StudentProfile.sample
        profile.testOptional = true
        profile.sat = nil
        profile.act = nil

        let result = ChanceEngine().evaluate(profile: profile, selectedCollegeIDs: Set(["mit"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("硬门槛"))
        XCTAssertTrue(report.contains("官方 Required standardized testing"))
        XCTAssertTrue(report.contains("MIT requires SAT/ACT"))
        XCTAssertFalse(report.contains("https://mitadmissions.org/apply/firstyear/tests-scores/"))
        XCTAssertTrue(report.contains("Massachusetts Institute of Technology：硬门槛未通过，先补齐Required standardized testing；阻断解除前不讨论材料加分。"))
        XCTAssertFalse(report.contains("Massachusetts Institute of Technology：缺失"))
    }

    func testFailedGateDisplaySummaryIncludesSourceURL() {
        let rule = AdmissionsSeedData.gateRules.first { $0.id == "mit_sat" }!
        let summary = GateRuleDisplay.failureSummary(rule)

        XCTAssertTrue(summary.contains("官方 Required standardized testing"))
        XCTAssertTrue(summary.contains("MIT requires SAT/ACT"))
        XCTAssertTrue(summary.contains("https://mitadmissions.org/apply/firstyear/tests-scores/"))
    }

    func testReportOmitsSourceAuditFromBody() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertFalse(report.contains("逐校数据来源审计"))
        XCTAssertFalse(report.contains("Boston University：基础率"))
        XCTAssertFalse(report.contains("AdmissionSight National Universities"))
        XCTAssertTrue(report.contains("Boston University"))
        XCTAssertTrue(report.contains("硬门槛"))
    }

    func testReportTierProbabilitiesIncludeCurrentPortfolioCounts() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("当前选择学校中至少被一所录取的估算概率"))
        XCTAssertTrue(report.contains("综合大学 T10 至少一所（当前组合 0 所）：0%"))
        XCTAssertTrue(report.contains("综合大学 T30 至少一所（当前组合 0 所）：0%"))
        XCTAssertTrue(report.contains("综合大学 T50 至少一所（当前组合 1 所）"))
        XCTAssertTrue(report.contains("文理学院 T10 至少一所（当前组合 0 所）：0%"))
        XCTAssertTrue(report.contains("文理学院 T30 至少一所（当前组合 0 所）：0%"))
        XCTAssertTrue(report.contains("全部已选至少一所（1 所）"))
    }

    func testReportDisclosesGeneratedSnapshotTime() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("生成时间："))
        XCTAssertTrue(report.contains("快照说明：本报告只解释该次提交的学生画像和选校组合"))
        XCTAssertTrue(report.contains("后续修改表单或选校后需要重新计算"))
        XCTAssertTrue(report.contains("学生画像及背景情况"))
        XCTAssertTrue(report.contains("概率分析结果"))
        XCTAssertTrue(report.contains("每所学校差距和优势比较"))
        XCTAssertTrue(report.contains("综合分析：整体优势、劣势与主要差距"))
        XCTAssertTrue(report.contains("下一步需要优化提升的方向"))
    }

    func testOpenAIReportPromptRequiresDetailedPaidReportWithoutChangingProbabilities() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "mit"]), selectionSource: .manual)
        let prompt = ReportService.makeOpenAIReportPrompt(result: result)

        XCTAssertTrue(prompt.contains("报告事实包"))
        XCTAssertTrue(prompt.contains("学生画像"))
        XCTAssertTrue(prompt.contains("组合摘要"))
        XCTAssertTrue(prompt.contains("逐校分析事实"))
        XCTAssertTrue(prompt.contains("主要概率驱动"))
        XCTAssertTrue(prompt.contains("客户端已插入"))
        XCTAssertFalse(prompt.contains("## 本地基础报告"))
        XCTAssertTrue(prompt.contains("总长度控制在 5000 个中文字以内"))
        XCTAssertTrue(prompt.contains("只输出 5 个标题"))
        XCTAssertTrue(prompt.contains("学生画像及背景分析"))
        XCTAssertTrue(prompt.contains("概率分析结果解读"))
        XCTAssertTrue(prompt.contains("逐校差距与优势分析"))
        XCTAssertTrue(prompt.contains("综合分析"))
        XCTAssertTrue(prompt.contains("下一步优化提升方向"))
        XCTAssertTrue(prompt.contains("概率分析必须点到每一所学校"))
        XCTAssertTrue(prompt.contains("学生条件与目标校平均/内部基准"))
        XCTAssertTrue(prompt.contains("不要重建表格"))
        XCTAssertTrue(prompt.contains("硬门槛"))
        XCTAssertTrue(prompt.contains("极强、强、中、弱、极弱"))
        XCTAssertTrue(prompt.contains("不得修改、重算、覆盖或美化"))
        XCTAssertTrue(prompt.contains("历史数据只是校准参考"))
        XCTAssertTrue(prompt.contains("不能代表未来申请季"))
        XCTAssertTrue(prompt.contains("Massachusetts Institute of Technology"))
        XCTAssertTrue(prompt.contains("Boston University"))
        XCTAssertTrue(prompt.contains("全部已选至少一所"))
        XCTAssertTrue(prompt.contains("匹配："))
        XCTAssertLessThan(prompt.count, 14000)
        XCTAssertFalse(prompt.contains("图标说明"))
        XCTAssertFalse(prompt.contains("▲"))
        XCTAssertFalse(prompt.contains("●"))
        XCTAssertFalse(prompt.contains("▼"))
    }

    func testMergedOpenAIReportRemovesDuplicatedDeterministicTables() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "mit"]), selectionSource: .manual)
        let generated = """
        ## 执行摘要
        当前组合需要先看硬门槛和目标校匹配。

        ## 逐校录取概率表
        | 学校 | 排名/类型 | 单校概率 | 分档 | 硬门槛 | 主要差距 | 优先动作 |
        | --- | --- | ---: | --- | --- | --- | --- |
        | 重复学校 | #1 综合大学 | 1% | 争取 | 通过 | 重复 | 重复 |

        ## 逐校学术匹配解读
        | 学校 | 成绩位置 | 班级位置 | 标化判断 | 课程挑战度 |
        | --- | --- | --- | --- | --- |
        | 重复学校 | 重复 | 重复 | 重复 | 重复 |

        ## 逐校策略
        Boston University：保留非重复策略。
        """

        let merged = ReportService.mergeGeneratedReport(generated, result: result)

        XCTAssertTrue(merged.contains("概率分析结果"))
        XCTAssertTrue(merged.contains("每所学校差距和优势比较"))
        XCTAssertTrue(merged.contains("待补资料"))
        XCTAssertTrue(merged.contains("提高申请数量对概率的影响分析"))
        XCTAssertTrue(merged.contains("自动推荐的提示和依据"))
        XCTAssertTrue(merged.contains("自动推荐提示"))
        XCTAssertTrue(merged.contains("自动推荐依据"))
        XCTAssertTrue(merged.contains("逐校策略摘要"))
        XCTAssertTrue(merged.contains("当前为手动选校，未触发自动推荐缺口判断。"))
        XCTAssertTrue(merged.contains("当前为手动选校；报告仍展示逐校概率和组合概率"))
        XCTAssertTrue(merged.contains("边际收益测算"))
        XCTAssertFalse(merged.contains("重复学校"))
        XCTAssertTrue(merged.contains("Boston University：保留非重复策略。"))
    }

    func testOpenAIReportPromptCarriesAutomaticRecommendationExpectedValueSteps() {
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 4
        let engine = ChanceEngine()
        let selected = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selected, selectionSource: .automatic)
        let prompt = ReportService.makeOpenAIReportPrompt(result: result)

        XCTAssertFalse(result.recommendationSteps.isEmpty)
        XCTAssertTrue(prompt.contains("自动推荐依据"))
        XCTAssertTrue(prompt.contains("自动推荐先排除硬门槛失败学校"))
        XCTAssertTrue(prompt.contains("顺位"))
        XCTAssertTrue(prompt.contains("学校价值"))
        XCTAssertTrue(prompt.contains("第1顺位"))
        XCTAssertTrue(prompt.contains("学校价值"))
        XCTAssertTrue(prompt.contains("同层"))
        XCTAssertTrue(prompt.contains("边际贡献"))
        XCTAssertTrue(prompt.contains("不要展开系统缺失数据、来源审计或置信度说明"))
        XCTAssertTrue(prompt.contains("单校概率、学校价值和同层相关性边际折扣"))
        XCTAssertTrue(prompt.contains("不要暴露内部调整值、权重、参数或公式"))
        XCTAssertTrue(prompt.contains("本地规划补充段落"))
        XCTAssertTrue(prompt.contains("待补资料、提高申请数量对概率的影响分析、自动推荐的提示和依据、逐校策略摘要"))
        XCTAssertTrue(prompt.contains("禁止推荐、点名或举例事实包外的具体学校名称"))
        XCTAssertTrue(prompt.contains("禁止估算新增学校后的具体组合概率"))
        XCTAssertTrue(prompt.contains("唯一允许出现的学校名称"))
        XCTAssertTrue(prompt.contains("即使讨论高中背景、历史录取或补校方向，也不得用未列入事实包的学校举例"))
    }

    func testCalculationFlowDocumentsApproximationAndSharedT10Correlation() throws {
        let docURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/calculation-flow.md")
        let flow = try String(contentsOf: docURL)

        XCTAssertTrue(flow.contains("大组合使用有界近似"))
        XCTAssertTrue(flow.contains("文理学院 T10 对齐到综合大学 T20-T30 价值带"))
        XCTAssertTrue(flow.contains("综合大学 T10 与文理学院 T10"))
        XCTAssertTrue(flow.contains("共享同一个极端选择性相关层"))
        XCTAssertTrue(flow.contains("不能因为类别不同而把顶尖学校当作独立机会相乘"))
    }

    func testHarnessDocumentsAllLACOfficialReviewPaths() {
        let sourceIDs = Set(AdmissionsSeedData.sourceRecords.map(\.id))

        XCTAssertTrue(sourceIDs.contains("college_scorecard_lac_rate_review"))
        XCTAssertTrue(sourceIDs.contains("ipeds_lac_rate_review"))
        XCTAssertTrue(AdmissionsSeedData.sourceRecords.contains {
            $0.id == "ipeds_lac_rate_review" &&
                $0.note.localizedCaseInsensitiveContains("DRVADM") &&
                $0.note.localizedCaseInsensitiveContains("Reported Data")
        })
    }

    func testReportBodyOmitsStructuredRoundPolicySourceAudit() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["mit"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertFalse(report.contains("First-year application rounds"))
        XCTAssertFalse(report.contains("允许轮次 EA/RD"))
        XCTAssertFalse(report.contains("EA加分 +0.00"))
        XCTAssertFalse(report.contains("ED加分 无明确数据"))
    }

    func testStudentProfileDoesNotRetainLegacyRecommendationBucketQuotas() {
        let labels = Set(Mirror(reflecting: StudentProfile.sample).children.compactMap(\.label))

        XCTAssertTrue(labels.contains("requestedSchoolCount"))
        XCTAssertFalse(labels.contains("requestedLikelyCount"))
        XCTAssertFalse(labels.contains("requestedTargetCount"))
        XCTAssertFalse(labels.contains("requestedReachCount"))
    }

    func testReportBodyOmitsCaltechRoundPolicySourceAuditURL() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["caltech"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertFalse(report.contains("Caltech offers Restrictive Early Action and Regular Decision"))
        XCTAssertFalse(report.contains("允许轮次 EA/RD"))
        XCTAssertFalse(report.contains("EA加分 +0.00"))
        XCTAssertFalse(report.contains("https://www.admissions.caltech.edu/apply/first-year-applicants/deadlines"))
    }

    private func assertChinaTotal(_ early: Int?, _ rd: Int?, _ total: Int?, _ collegeID: String) {
        guard let early, let rd, let total else {
            return
        }
        XCTAssertEqual(early + rd, total, collegeID)
    }
}

private extension UIImage {
    func nonWhitePixelCount(in rect: CGRect) throws -> Int {
        guard let cgImage else {
            return 0
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let xRange = max(0, Int(rect.minX))..<min(width, Int(rect.maxX))
        let yRange = max(0, Int(rect.minY))..<min(height, Int(rect.maxY))
        var count = 0
        for y in yRange {
            for x in xRange {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                if alpha > 0 && (red < 245 || green < 245 || blue < 245) {
                    count += 1
                }
            }
        }
        return count
    }
}
