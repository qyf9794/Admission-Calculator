import SwiftUI

struct DataSourcesView: View {
    @State private var searchText = ""
    @State private var mode: DataSourcesMode = .sources

    private var filteredSources: [DataSourceRecord] {
        AdmissionsSeedData.sourceRecords.filter { $0.matchesSourceQuery(searchText) }
    }

    private var filteredColleges: [College] {
        AdmissionsSeedData.colleges.filter { college in
            college.matchesSourceAuditQuery(
                searchText,
                internationalSignal: AdmissionsSeedData.internationalSignals.first { $0.collegeID == college.id },
                chinaSignal: AdmissionsSeedData.chinaAdmissionSignals.first { $0.collegeID == college.id },
                academicBenchmark: AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == college.id },
                gateRules: AdmissionsSeedData.gateRules.filter { $0.collegeID == college.id || $0.collegeID == "*" }
            )
        }
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
        .admissionPage()
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
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
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
                    .font(AdmissionStyle.titleFont(36))
                    .foregroundStyle(.white)
                Text("查看每个概率输入来自哪里、哪些是官方数据、哪些只是保守代理。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    AdmissionMetricPill(title: "学校", value: "\(AdmissionsSeedData.colleges.count)")
                    AdmissionMetricPill(title: "来源", value: "\(AdmissionsSeedData.sourceRecords.count)")
                    AdmissionMetricPill(title: "版本", value: AdmissionsSeedData.dataVersion)
                }
            }
        }
    }

    private func heroColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue]
        return colors[index % colors.count]
    }
}

private struct DataSnapshotCard: View {
    var body: some View {
        AdmissionGradientCard(
            title: "当前数据快照",
            systemImage: "checkmark.seal.fill",
            colors: AdmissionStyle.mintNight
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DataMetricCell(title: "版本", value: AdmissionsSeedData.dataVersion, tint: .green)
                DataMetricCell(title: "生成日期", value: AdmissionsSeedData.generatedAt, tint: .blue)
                DataMetricCell(title: "学校数量", value: "\(AdmissionsSeedData.colleges.count)", tint: .purple)
                DataMetricCell(title: "硬门槛", value: "\(AdmissionsSeedData.gateRules.count)", tint: .orange)
            }
            Text("学校统计范围固定为已审核 v1 数据集：AdmissionSight 综合大学与用户提供表格中的 Top30 文理学院；国际生、中国本科、学术基准和硬门槛来源会在逐校审计中单独披露。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct DataMetricCell: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .admissionSmallCard(colors: [tint.opacity(0.92), Color.black.opacity(0.78)])
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
        AdmissionGradientCard(
            title: source.name,
            subtitle: source.role,
            colors: isHighConfidence ? AdmissionStyle.mintNight : AdmissionStyle.citrus
        ) {
            Text(source.confidence)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)
            Text(source.note)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            LabeledContent("刷新方式", value: source.refreshMode)
                .font(.caption)
            Link(source.url.absoluteString, destination: source.url)
                .font(.caption2)
        }
    }

    private var confidenceColor: Color {
        isHighConfidence ? .green : .orange
    }

    private var isHighConfidence: Bool {
        source.confidence.localizedCaseInsensitiveContains("high")
    }
}

private struct CollegeStatisticsSection: View {
    let colleges: [College]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "学校统计", subtitle: "基础录取率只作为模型种子，个人概率会被画像、门槛和数据质量修正。", systemImage: "chart.bar.doc.horizontal", tint: .purple)
            if colleges.isEmpty {
                ContentUnavailableView("没有匹配学校", systemImage: "magnifyingglass", description: Text("可按学校名、排名或综合大学 T10/T30/T50/50+ 搜索。"))
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
        AdmissionGradientCard(
            title: college.name,
            subtitle: "#\(college.rank) · \(college.tierDisplayName)",
            colors: AdmissionStyle.bluePulse
        ) {
            Text(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                DataMetricCell(title: "数据槽", value: "\(college.latestAvailableClassYear)", tint: .purple)
                DataMetricCell(title: "质量", value: college.dataQuality.formatted(.number.precision(.fractionLength(2))), tint: .green)
            }
            Text(college.sourceNote)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
            Link("基础率来源", destination: college.sourceURL)
                .font(.caption2)
        }
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
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                            Text("录取率、国际生代理、中国本科录取容量、学术基准与硬门槛来源")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        Spacer()
                        Text(college.tierDisplayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 4)
                }
                .padding(14)
                .background(
                    LinearGradient(colors: AdmissionStyle.roseSlate, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
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
                    .font(AdmissionStyle.sectionFont())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.35), in: Circle())
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
                value: "最新可用基础录取率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))",
                note: "\(collegeStatsSourceLabel)；\(college.sourceNote)；数据槽 \(college.latestAvailableClassYear)，数据质量 \(college.dataQuality.formatted(.number.precision(.fractionLength(2))))。",
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
                    note: "当前生成数据没有该校本科国际生代理行；该信息仅用于数据说明，不通过置信度折扣概率。",
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
                    note: "当前没有该校学术基准行；该信息仅用于数据说明，不通过置信度折扣概率。",
                    url: nil,
                    tint: .orange
                )
            }
            if schoolRules.isEmpty {
                SourceAuditRow(
                    title: "该校硬门槛",
                    value: "未配置学校专属硬门槛",
                    note: "仍会按适用身份/专业检查全局推断门槛；缺官方数据不会通过置信度折扣概率。",
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
                note: "全局规则不会无差别扣分；只有适用于该学生身份、专业或学校政策时才检查或披露。",
                url: nil,
                tint: .orange
            )
        }
        .padding(.top, 8)
    }

    private var collegeStatsSourceLabel: String {
        switch college.category {
        case .nationalUniversity:
            return "AdmissionSight National Universities 表；v1 综合大学统计种子"
        case .liberalArtsCollege:
            if college.sourceURL.absoluteString.hasPrefix("https://collegescorecard.ed.gov/school/?") {
                return "U.S. Department of Education College Scorecard；v1 文理学院基础率来源"
            }
            if college.sourceURL.absoluteString.hasPrefix("https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx") {
                return "NCES/IPEDS DataFiles；v1 文理学院官方基础率来源"
            }
            if college.sourceURL.absoluteString.hasPrefix("https://nces.ed.gov/ipeds/reported-data/html/") {
                return "NCES/IPEDS Reported Data Admissions；v1 文理学院官方基础率来源"
            }
            return "已审阅 Top30 Liberal Arts Colleges 用户表；v1 文理学院统计种子"
        }
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
                .foregroundStyle(.white.opacity(0.70))
            if let url {
                Link(url.absoluteString, destination: url)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
