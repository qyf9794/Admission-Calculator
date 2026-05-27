import SwiftUI

struct DataSourcesView: View {
    var body: some View {
        List {
            Section("数据快照") {
                LabeledContent("版本", value: AdmissionsSeedData.dataVersion)
                LabeledContent("生成日期", value: AdmissionsSeedData.generatedAt)
                LabeledContent("学校数量", value: "\(AdmissionsSeedData.colleges.count)")
            }

            Section("固定数据源") {
                ForEach(AdmissionsSeedData.sourceRecords) { source in
                    SourceRow(source: source)
                }
            }

            Section("学校统计") {
                ForEach(AdmissionsSeedData.colleges) { college in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(college.name)
                            .font(.headline)
                        Text("#\(college.rank) · \(college.tierName) · \(college.latestAvailableClassYear) 届 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("逐校来源审计") {
                ForEach(AdmissionsSeedData.colleges) { college in
                    DisclosureGroup {
                        CollegeSourceAudit(college: college)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(college.name)
                                .font(.headline)
                            Text("录取率、国际生代理、中国本科录取容量、学术基准与硬门槛来源")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: DataSourceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.headline)
            Text(source.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(source.refreshMode) · confidence: \(source.confidence)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(source.url.absoluteString, destination: source.url)
                .font(.caption2)
        }
    }
}

private struct CollegeSourceAudit: View {
    let college: College

    private var internationalSignal: InternationalSignal? {
        AdmissionsSeedData.internationalSignals.first { $0.collegeID == college.id }
    }

    private var chinaSignal: ChinaUndergradAdmissionSignal? {
        AdmissionsSeedData.chinaAdmissionSignals.first { $0.collegeID == college.id }
    }

    private var benchmark: AcademicBenchmark? {
        AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == college.id }
    }

    private var schoolRules: [CollegeGateRule] {
        AdmissionsSeedData.gateRules.filter { $0.collegeID == college.id }
    }

    private var globalRules: [CollegeGateRule] {
        AdmissionsSeedData.gateRules.filter { $0.collegeID == "*" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SourceAuditRow(
                title: "学校统计",
                value: "\(college.latestAvailableClassYear) 届录取率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))",
                note: "AdmissionSight National Universities 表；v1 唯一学校统计种子。数据质量 \(college.dataQuality.formatted(.number.precision(.fractionLength(2))))。",
                url: college.sourceURL
            )
            if let internationalSignal {
                SourceAuditRow(
                    title: "国际生本科信号",
                    value: internationalSignalValue(internationalSignal),
                    note: "\(internationalSignal.dataScope)：\(internationalSignal.sourceNote)",
                    url: internationalSignal.sourceURL
                )
            } else {
                SourceAuditRow(
                    title: "国际生本科信号",
                    value: "缺失",
                    note: "当前生成数据没有该校本科国际生代理行；概率应降低置信度并披露缺口。",
                    url: nil
                )
            }
            if let chinaSignal {
                SourceAuditRow(
                    title: "中国本科录取容量",
                    value: chinaSignalValue(chinaSignal),
                    note: "\(chinaSignal.dataScope)：\(chinaSignal.sourceNote)",
                    url: nil
                )
            } else {
                SourceAuditRow(
                    title: "中国本科录取容量",
                    value: "缺失",
                    note: "当前没有该校中国本科录取人数行；不得推导中国录取率或容量优势。",
                    url: nil
                )
            }
            if let benchmark {
                SourceAuditRow(
                    title: "目标校学术基准",
                    value: academicBenchmarkValue(benchmark),
                    note: "\(benchmarkSourceLabel(benchmark))：\(benchmark.sourceNote)",
                    url: benchmark.sourceURL
                )
            } else {
                SourceAuditRow(
                    title: "目标校学术基准",
                    value: "缺失",
                    note: "当前没有该校学术基准行；概率应降低置信度并提示补官方 CDS 或 class profile。",
                    url: nil
                )
            }
            if schoolRules.isEmpty {
                SourceAuditRow(
                    title: "该校硬门槛",
                    value: "未配置学校专属硬门槛",
                    note: "仍会按适用身份/专业检查全局推断门槛；缺官方数据会降低置信度。",
                    url: nil
                )
            } else {
                ForEach(schoolRules) { rule in
                    SourceAuditRow(
                        title: "该校硬门槛",
                        value: "\(rule.title) · \(rule.isOfficial ? "官方" : "推断")",
                        note: rule.detail,
                        url: rule.sourceURL
                    )
                }
            }
            SourceAuditRow(
                title: "全局推断门槛",
                value: "\(globalRules.count) 条按身份/专业适用性过滤",
                note: "全局规则不会无差别扣分；只有适用于该学生身份、专业或学校政策时才检查、披露或降低置信度。",
                url: nil
            )
        }
        .padding(.vertical, 6)
    }

    private func internationalSignalValue(_ signal: InternationalSignal) -> String {
        let share = signal.undergradNonresidentShare?.formatted(.percent.precision(.fractionLength(1))) ?? "缺失"
        let coefficient = signal.internationalAdmitCoefficient?.formatted(.number.precision(.fractionLength(2))) ?? "缺失"
        return "本科非居民比例 \(share)，admit coefficient \(coefficient)，资助政策 \(signal.internationalAidPolicy.rawValue)"
    }

    private func chinaSignalValue(_ signal: ChinaUndergradAdmissionSignal) -> String {
        let early = signal.early2030.map(String.init) ?? "缺失"
        let rd = signal.rd2030.map(String.init) ?? "缺失"
        let total = signal.total2030.map(String.init) ?? "缺失"
        return "2030 届早申 \(early)，RD \(rd)，合计 \(total)"
    }

    private func academicBenchmarkValue(_ benchmark: AcademicBenchmark) -> String {
        let gpa = benchmark.gpaPercentBenchmark.map { "\($0.formatted(.number.precision(.fractionLength(0))))" } ?? "缺失"
        let rank = benchmark.classRankPercentileBenchmark.map { "前 \($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "缺失"
        let sat = benchmark.satBenchmark.map(String.init) ?? "不使用/缺失"
        let rigor = benchmark.rigorBenchmark.map { "\($0)/5" } ?? "缺失"
        return "GPA \(gpa)，排名 \(rank)，SAT \(sat)，课程难度 \(rigor)"
    }

    private func benchmarkSourceLabel(_ benchmark: AcademicBenchmark) -> String {
        if benchmark.isInferred && benchmark.sourceFields.contains(where: { $0.localizedCaseInsensitiveContains("official") }) {
            return "部分官方/部分推断"
        }
        return benchmark.isInferred ? "推断值" : "官方/学校来源"
    }
}

private struct SourceAuditRow: View {
    let title: String
    let value: String
    let note: String
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let url {
                Link(url.absoluteString, destination: url)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
