import SwiftUI

struct DataSourcesView: View {
    @State private var searchText = ""
    @State private var mode: DataSourcesMode = .sources

    private var filteredSources: [DataSourceRecord] {
        AdmissionsSeedData.sourceRecords.filter { $0.matchesSourceQuery(searchText) }
    }

    private var filteredColleges: [College] {
        AdmissionsSeedData.colleges.filter { $0.matchesPickerQuery(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DataSourcesHero()
                DataSnapshotCard()

                Picker("数据视图", selection: $mode) {
                    ForEach(DataSourcesMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .sources:
                    SourceRecordsSection(sources: filteredSources)
                case .statistics:
                    CollegeStatisticsSection(colleges: filteredColleges)
                case .audit:
                    CollegeAuditSection(colleges: filteredColleges)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索学校或来源")
    }
}

private enum DataSourcesMode: String, CaseIterable, Identifiable {
    case sources = "来源"
    case statistics = "统计"
    case audit = "审计"

    var id: String { rawValue }
}

private struct DataSourcesHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.07, green: 0.14, blue: 0.28)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heroColor(index))
                        .frame(width: 22, height: CGFloat(44 + index % 4 * 24))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.62)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("数据透明度", systemImage: "tablecells.badge.ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("来源审计")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("查看每个概率输入来自哪里、哪些是官方数据、哪些只是保守代理。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    DataHeroMetric(title: "学校", value: "\(AdmissionsSeedData.colleges.count)")
                    DataHeroMetric(title: "来源", value: "\(AdmissionsSeedData.sourceRecords.count)")
                    DataHeroMetric(title: "版本", value: AdmissionsSeedData.dataVersion)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 238)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func heroColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue]
        return colors[index % colors.count]
    }
}

private struct DataHeroMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

private struct DataSnapshotCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("当前数据快照", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DataMetricCell(title: "版本", value: AdmissionsSeedData.dataVersion, tint: .green)
                DataMetricCell(title: "生成日期", value: AdmissionsSeedData.generatedAt, tint: .blue)
                DataMetricCell(title: "学校数量", value: "\(AdmissionsSeedData.colleges.count)", tint: .purple)
                DataMetricCell(title: "硬门槛", value: "\(AdmissionsSeedData.gateRules.count)", tint: .orange)
            }
            Text("学校统计范围固定为 AdmissionSight National Universities v1；国际生、中国本科、学术基准和硬门槛来源会在逐校审计中单独披露。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct DataMetricCell: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SourceRecordsSection: View {
    let sources: [DataSourceRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "固定数据源", subtitle: "来源只说明角色和口径；不会自动提高概率。", systemImage: "link.circle", tint: .blue)
            if sources.isEmpty {
                ContentUnavailableView("没有匹配来源", systemImage: "magnifyingglass", description: Text("换一个来源名或关键词。"))
            }
            ForEach(sources) { source in
                SourceCard(source: source)
            }
        }
    }
}

private struct SourceCard: View {
    let source: DataSourceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.headline)
                    Text(source.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(source.confidence)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(confidenceColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(confidenceColor)
            }
            Text(source.note)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("刷新方式", value: source.refreshMode)
                .font(.caption)
            Link(source.url.absoluteString, destination: source.url)
                .font(.caption2)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(confidenceColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var confidenceColor: Color {
        source.confidence.localizedCaseInsensitiveContains("high") ? .green : .orange
    }
}

private struct CollegeStatisticsSection: View {
    let colleges: [College]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "学校统计", subtitle: "基础录取率只作为模型种子，个人概率会被画像、门槛和数据质量修正。", systemImage: "chart.bar.doc.horizontal", tint: .purple)
            if colleges.isEmpty {
                ContentUnavailableView("没有匹配学校", systemImage: "magnifyingglass", description: Text("可按学校名、排名或 T10/T30/T50 搜索。"))
            }
            ForEach(colleges) { college in
                CollegeStatCard(college: college)
            }
        }
    }
}

private struct CollegeStatCard: View {
    let college: College

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(college.name)
                        .font(.headline)
                    Text("#\(college.rank) · \(college.tierName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
            }
            HStack(spacing: 10) {
                DataMetricCell(title: "届别", value: "\(college.latestAvailableClassYear)", tint: .purple)
                DataMetricCell(title: "质量", value: college.dataQuality.formatted(.number.precision(.fractionLength(2))), tint: .green)
            }
            Link("AdmissionSight source", destination: college.sourceURL)
                .font(.caption2)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CollegeAuditSection: View {
    let colleges: [College]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "逐校来源审计", subtitle: "逐项查看录取率、国际生、中国本科容量、学术基准和硬门槛来源。", systemImage: "doc.text.magnifyingglass", tint: .orange)
            if colleges.isEmpty {
                ContentUnavailableView("没有匹配学校", systemImage: "magnifyingglass", description: Text("可按学校名、排名或分层搜索。"))
            }
            ForEach(colleges) { college in
                DisclosureGroup {
                    CollegeSourceAudit(college: college)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(college.name)
                                .font(.headline)
                            Text("录取率、国际生代理、中国本科录取容量、学术基准与硬门槛来源")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(college.tierName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
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
                url: college.sourceURL,
                tint: .blue
            )
            if let internationalSignal {
                SourceAuditRow(
                    title: "国际生本科信号",
                    value: internationalSignalValue(internationalSignal),
                    note: "\(internationalSignal.dataScope)：\(internationalSignal.sourceNote)",
                    url: internationalSignal.sourceURL,
                    tint: .teal
                )
            } else {
                SourceAuditRow(
                    title: "国际生本科信号",
                    value: "缺失",
                    note: "当前生成数据没有该校本科国际生代理行；概率应降低置信度并披露缺口。",
                    url: nil,
                    tint: .orange
                )
            }
            if let chinaSignal {
                SourceAuditRow(
                    title: "中国本科录取容量",
                    value: chinaSignalValue(chinaSignal),
                    note: "\(chinaSignal.dataScope)：\(chinaSignal.sourceNote)",
                    url: nil,
                    tint: .purple
                )
            } else {
                SourceAuditRow(
                    title: "中国本科录取容量",
                    value: "缺失",
                    note: "当前没有该校中国本科录取人数行；不得推导中国录取率或容量优势。",
                    url: nil,
                    tint: .orange
                )
            }
            if let benchmark {
                SourceAuditRow(
                    title: "目标校学术基准",
                    value: academicBenchmarkValue(benchmark),
                    note: "\(benchmarkSourceLabel(benchmark))：\(benchmark.sourceNote)",
                    url: benchmark.sourceURL,
                    tint: .green
                )
            } else {
                SourceAuditRow(
                    title: "目标校学术基准",
                    value: "缺失",
                    note: "当前没有该校学术基准行；概率应降低置信度并提示补官方 CDS 或 class profile。",
                    url: nil,
                    tint: .orange
                )
            }
            if schoolRules.isEmpty {
                SourceAuditRow(
                    title: "该校硬门槛",
                    value: "未配置学校专属硬门槛",
                    note: "仍会按适用身份/专业检查全局推断门槛；缺官方数据会降低置信度。",
                    url: nil,
                    tint: .orange
                )
            } else {
                ForEach(schoolRules) { rule in
                    SourceAuditRow(
                        title: "该校硬门槛",
                        value: gateRuleValue(rule),
                        note: gateRuleNote(rule),
                        url: rule.sourceURL,
                        tint: rule.isOfficial ? .green : .orange
                    )
                }
            }
            SourceAuditRow(
                title: "全局推断门槛",
                value: "\(globalRules.count) 条按身份/专业适用性过滤",
                note: "全局规则不会无差别扣分；只有适用于该学生身份、专业或学校政策时才检查、披露或降低置信度。",
                url: nil,
                tint: .orange
            )
        }
        .padding(.top, 8)
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

    private func gateRuleValue(_ rule: CollegeGateRule) -> String {
        let status = rule.isOfficial ? "官方" : "推断"
        guard rule.type == .round else {
            return "\(rule.title) · \(status)"
        }

        let allowed = rule.allowedRounds.isEmpty
            ? "未列"
            : rule.allowedRounds.map(\.rawValue).joined(separator: "/")
        return "\(rule.title) · \(status) · 允许轮次 \(allowed)"
    }

    private func gateRuleNote(_ rule: CollegeGateRule) -> String {
        guard rule.type == .round else {
            return rule.detail
        }

        return "\(rule.detail) EA加分 \(roundAdjustmentText(rule.earlyActionAdjustment))；ED加分 \(roundAdjustmentText(rule.earlyDecisionAdjustment))。"
    }

    private func roundAdjustmentText(_ value: Double?) -> String {
        guard let value else {
            return "无明确数据"
        }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))"
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
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
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
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
