import XCTest
@testable import AdmissionCalculator

final class HarnessValidationTests: XCTestCase {
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
        XCTAssertTrue(report.contains("Massachusetts Institute of Technology：硬门槛未通过，未进入目标校学术匹配计算。"))
        XCTAssertFalse(report.contains("Massachusetts Institute of Technology：缺失"))
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
        XCTAssertTrue(report.contains("Boston University：基础率"))
        XCTAssertTrue(report.contains("AdmissionSight National Universities"))
        XCTAssertTrue(report.contains("国际生"))
        XCTAssertTrue(report.contains("中国本科"))
        XCTAssertTrue(report.contains("学术基准"))
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
    }

    func testOpenAIReportPromptRequiresDetailedPaidReportWithoutChangingProbabilities() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["bu", "mit"]), selectionSource: .manual)
        let prompt = ReportService.makeOpenAIReportPrompt(result: result)

        XCTAssertTrue(prompt.contains("逐校概率与风险表"))
        XCTAssertTrue(prompt.contains("差距分析"))
        XCTAssertTrue(prompt.contains("提高概率的努力方向"))
        XCTAssertTrue(prompt.contains("选校组合策略"))
        XCTAssertTrue(prompt.contains("不得修改、重算、覆盖或美化"))
        XCTAssertTrue(prompt.contains("Massachusetts Institute of Technology"))
        XCTAssertTrue(prompt.contains("Boston University"))
        XCTAssertTrue(prompt.contains("当前选择学校中至少被一所录取的估算概率"))
    }

    func testOpenAIReportPromptCarriesAutomaticRecommendationExpectedValueSteps() {
        var profile = StudentProfile.sample
        profile.requestedSchoolCount = 4
        let engine = ChanceEngine()
        let selected = Set(engine.recommendedColleges(for: profile, count: profile.requestedSchoolCount).map(\.id))
        let result = engine.evaluate(profile: profile, selectedCollegeIDs: selected, selectionSource: .automatic)
        let prompt = ReportService.makeOpenAIReportPrompt(result: result)

        XCTAssertFalse(result.recommendationSteps.isEmpty)
        XCTAssertTrue(prompt.contains("必须引用组合最佳录取期望值"))
        XCTAssertTrue(prompt.contains("逐项引用顺位、排名价值分、概率×排名价值、置信度折扣、同层折扣和边际期望值"))
        XCTAssertTrue(prompt.contains("第1顺位"))
        XCTAssertTrue(prompt.contains("排名价值分"))
        XCTAssertTrue(prompt.contains("同层边际折扣"))
        XCTAssertTrue(prompt.contains("边际期望值"))
        XCTAssertTrue(prompt.contains("候选短名单"))
        XCTAssertTrue(prompt.contains("概率 × 排名价值分 × 置信度折扣"))
        XCTAssertTrue(prompt.contains("有界窗口"))
        XCTAssertTrue(prompt.contains("有界快速近似"))
        XCTAssertTrue(prompt.contains("文理学院 T10 的排名价值对齐到综合大学 T20-T30 价值带"))
        XCTAssertTrue(prompt.contains("综合大学 T10 与文理学院 T10 共享同一个极端选择性相关性层"))
        XCTAssertTrue(prompt.contains("手机端响应速度"))
        XCTAssertTrue(prompt.contains("护栏"))
        XCTAssertTrue(prompt.contains("排名价值最高"))
        XCTAssertTrue(prompt.contains("单校概率最高"))
        XCTAssertTrue(prompt.contains("固定数量学校"))
        XCTAssertTrue(prompt.contains("替换试算使用较轻量的顺位比较"))
        XCTAssertTrue(prompt.contains("排名价值优先顺位"))
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

    func testReportSourceAuditIncludesStructuredRoundPolicy() {
        let result = ChanceEngine().evaluate(profile: .sample, selectedCollegeIDs: Set(["mit"]), selectionSource: .manual)
        let report = ReportService.makeReport(result: result)

        XCTAssertTrue(report.contains("First-year application rounds"))
        XCTAssertTrue(report.contains("允许轮次 EA/RD"))
        XCTAssertTrue(report.contains("EA加分 +0.00"))
        XCTAssertTrue(report.contains("ED加分 无明确数据"))
    }

    func testStudentProfileDoesNotRetainLegacyRecommendationBucketQuotas() {
        let labels = Set(Mirror(reflecting: StudentProfile.sample).children.compactMap(\.label))

        XCTAssertTrue(labels.contains("requestedSchoolCount"))
        XCTAssertFalse(labels.contains("requestedLikelyCount"))
        XCTAssertFalse(labels.contains("requestedTargetCount"))
        XCTAssertFalse(labels.contains("requestedReachCount"))
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
