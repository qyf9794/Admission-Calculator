import SwiftUI
import UIKit

struct ReportView: View {
    let result: PortfolioResult?
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool
    let onBackToResults: () -> Void
    var client = OpenAIReportClient()

    @State private var reportText: String?
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingDataSources = false
    @State private var showingPaymentSheet = false
    @State private var showingReportSheet = false

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 16) {
                    ReportFrameworkHeader(result: result, onBackToResults: onBackToResults)

                    if isStale {
                        Label("当前结果已过期；请先回到计算页重新计算，再生成付费报告。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
                    }

                    ReportActionCard(
                        result: result,
                        purchaseState: purchaseState,
                        isStale: isStale,
                        isGenerating: isGenerating,
                        errorMessage: errorMessage,
                        onGenerate: { showingPaymentSheet = true },
                        onShowDataSources: { showingDataSources = true }
                    )

                    ReportFrameworkPreview()
                }
                .padding()
            } else {
                ContentUnavailableView("尚未生成报告", systemImage: "doc.text.magnifyingglass", description: Text("请先在计算页提交学生画像并计算结果。"))
                    .padding()
            }
            }
        }
        .sheet(isPresented: $showingDataSources) {
            NavigationStack {
                DataSourcesView()
                    .navigationTitle("数据与模型说明")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                showingDataSources = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingPaymentSheet) {
            if let result {
                ReportPaymentSheet(
                    isGenerating: isGenerating,
                    errorMessage: errorMessage,
                    onCancel: { showingPaymentSheet = false },
                    onPayAndGenerate: { completePaymentAndGenerate(for: result) }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            if let result, let reportText {
                NavigationStack {
                    ReportTextCard(
                        text: reportText,
                        pdfURL: pdfURL,
                        pdfErrorMessage: pdfErrorMessage,
                        onExportPDF: { exportPDF(text: reportText, result: result) }
                    )
                    .padding()
                    .admissionPage()
                    .navigationTitle("录取分析报告")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                showingReportSheet = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func completePaymentAndGenerate(for result: PortfolioResult) {
        guard !isStale else {
            return
        }
        guard result.profileSnapshot.round == .regularDecision else {
            errorMessage = "综合报告仅支持 RD 轮次；EA/ED 结果只显示本轮概率，不生成综合报告。"
            return
        }
        purchaseState.unlockForPrototype()
        generateReport(for: result)
    }

    private func generateReport(for result: PortfolioResult) {
        isGenerating = true
        errorMessage = nil
        pdfURL = nil
        pdfErrorMessage = nil

        Task {
            do {
                let prompt = ReportService.makeOpenAIReportPrompt(result: result)
                let generated = try await client.generateReport(prompt: prompt)
                await MainActor.run {
                    reportText = generated
                    pdfURL = nil
                    isGenerating = false
                    showingPaymentSheet = false
                    showingReportSheet = true
                }
            } catch {
                await MainActor.run {
                    reportText = ReportService.makeReport(result: result)
                    pdfURL = nil
                    errorMessage = "OpenAI 生成失败，已显示本地模板报告：\(error.localizedDescription)"
                    isGenerating = false
                    showingPaymentSheet = false
                    showingReportSheet = true
                }
            }
        }
    }

    private func exportPDF(text: String, result: PortfolioResult) {
        do {
            pdfURL = try ReportPDFRenderer.write(
                text: text,
                result: result,
                fileName: "Admission-Report-\(Self.pdfDateFormatter.string(from: result.generatedAt)).pdf"
            )
            pdfErrorMessage = nil
        } catch {
            pdfErrorMessage = "PDF 生成失败：\(error.localizedDescription)"
        }
    }

    private static let pdfDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()
}

private struct ReportHero: View {
    let result: PortfolioResult

    var body: some View {
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Label("付费 AI 综合报告 · \(result.profileSnapshot.round.rawValue)", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 8)
                    ReportBarsSummary(results: Array(result.schoolResults.prefix(6)))
                }
                Text("Application Report")
                    .font(AdmissionStyle.titleFont(34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(result.profileSnapshot.round == .regularDecision
                     ? "逐校解释概率、差距、提升路径和选校组合策略；AI 只解释已计算结果，不改变概率。"
                     : "EA/ED 只提供本轮次概率结果；综合报告仅开放给 RD 轮次。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    AdmissionProbabilityCard(
                        title: "全部已选",
                        subtitle: "综合报告基准概率",
                        value: result.selectedAtLeastOne,
                        colors: [Color.green.opacity(0.92), Color.black.opacity(0.84)],
                        countText: "当前组合 \(result.schoolResults.count) 所",
                        delayIndex: 0,
                        symbolName: "doc.text.magnifyingglass",
                        fontSize: 42
                    )
                    HStack(spacing: 10) {
                        AdmissionMetricPill(title: "学校", value: "\(result.schoolResults.count)")
                        AdmissionMetricPill(title: "阻断", value: "\(result.selectedBucketCounts.blocked)")
                    }
                }
            }
        }
    }
}

private struct ReportFrameworkHeader: View {
    let result: PortfolioResult
    let onBackToResults: () -> Void

    var body: some View {
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onBackToResults) {
                    Label("返回结果", systemImage: "chevron.left")
                }
                .buttonStyle(AdmissionQuietButtonStyle())
                .fixedSize()

                Label("付费 AI 综合报告 · \(result.profileSnapshot.round.rawValue)", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Report Framework")
                    .font(AdmissionStyle.titleFont(34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("生成前只展示报告结构。支付并生成后，报告会以弹窗显示，并可导出 PDF。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReportFrameworkPreview: View {
    private let sections = [
        ("测算摘要", "组合概率、风险层级、是否存在硬门槛阻断。"),
        ("逐校解释", "每所已选学校的概率、主要加分项和主要扣分项。"),
        ("学术画像对比", "GPA、排名、课程难度、标化和目标校基准差距。"),
        ("选校组合策略", "申请数量、排名价值、自动推荐逻辑和组合风险。"),
        ("提升行动计划", "短期补强事项、材料重点、家庭沟通版结论。")
    ]

    var body: some View {
        AdmissionGradientCard(
            title: "报告包含内容",
            subtitle: "这里只展示框架，不展示具体学校概率或个性化建议。",
            systemImage: "list.bullet.rectangle",
            colors: AdmissionStyle.mintNight
        ) {
            ForEach(sections, id: \.0) { section in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.86))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.0)
                            .font(.subheadline.weight(.black))
                        Text(section.1)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
    }
}

private struct ReportPaymentSheet: View {
    let isGenerating: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onPayAndGenerate: () -> Void

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("报告支付")
                    .font(AdmissionStyle.titleFont(30))
                    .foregroundStyle(Color.black.opacity(0.88))
                Text("支付后生成完整录取分析报告。当前为 StoreKit-ready 原型流程，不会改变任何已计算概率。")
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.62))
                if let errorMessage {
                    Label(errorMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .buttonStyle(AdmissionQuietButtonStyle(foreground: .black))
                        .disabled(isGenerating)
                    Button(action: onPayAndGenerate) {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text(isGenerating ? "正在生成" : "支付并生成")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.blackGlass))
                    .disabled(isGenerating)
                }
            }
            .padding(18)
        }
    }
}

private struct ReportBarsSummary: View {
    let results: [ChanceResult]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if results.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 12, height: 18)
            } else {
                ForEach(Array(results.enumerated()), id: \.offset) { index, school in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: school.bucket))
                        .frame(width: 10, height: CGFloat(18 + index * 4) + CGFloat(school.adjustedProbability * 32))
                }
            }
        }
        .frame(height: 52, alignment: .bottom)
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func color(for bucket: RecommendationBucket) -> Color {
        switch bucket {
        case .reach: .orange
        case .target: .blue
        case .likely: .green
        case .blocked: .red
        }
    }
}

private struct ReportActionCard: View {
    let result: PortfolioResult
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool
    let isGenerating: Bool
    let errorMessage: String?
    let onGenerate: () -> Void
    let onShowDataSources: () -> Void

    var body: some View {
        AdmissionGradientCard(
            title: "报告生成",
            subtitle: "报告会围绕逐校概率、组合概率、差距优势和提升路径展开；AI 只解释已计算结果，不改变概率。",
            systemImage: "sparkles",
            colors: AdmissionStyle.pinkMist
        ) {
            if result.profileSnapshot.round != .regularDecision {
                Label("综合报告仅针对 RD 轮次。当前为 \(result.profileSnapshot.round.rawValue)，可查看本轮逐校概率，但不能生成综合报告。", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                Button {
                    onGenerate()
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: purchaseState.isUnlocked ? "arrow.clockwise" : "lock.open")
                        }
                        Text(isGenerating ? "正在生成" : (purchaseState.isUnlocked ? "重新生成报告" : "付费生成报告"))
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.blackGlass))
                .disabled(isStale || isGenerating || result.schoolResults.isEmpty || result.profileSnapshot.round != .regularDecision)

                Button {
                    onShowDataSources()
                } label: {
                    Label("说明", systemImage: "info.circle")
                }
                .buttonStyle(AdmissionQuietButtonStyle())
            }
            Text(purchaseState.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AI 正在整理不足项、申请策略和学校简表，请保持页面打开。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.70))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
            }
            if result.schoolResults.isEmpty {
                Label("当前没有进入计算的学校，请先选择学校并重新计算。", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct ReportSchoolProbabilityList: View {
    let results: [ChanceResult]
    let round: ApplicationRound

    var body: some View {
        AdmissionGradientCard(
            title: "逐校概率 · \(round.rawValue)",
            subtitle: "以下概率只对应 \(round.rawValue) 轮次；不会混合其他轮次。",
            systemImage: "building.2.crop.circle",
            colors: AdmissionStyle.bluePulse
        ) {
            if results.isEmpty {
                ContentUnavailableView("暂无逐校概率", systemImage: "building.columns", description: Text("请先在计算页选择学校并计算。"))
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                AdmissionProbabilityCard(
                    title: result.college.name,
                    subtitle: "#\(result.college.rank) · \(result.college.tierDisplayName) · \(result.bucket.rawValue)",
                    value: result.adjustedProbability,
                    colors: [color(for: result.bucket).opacity(0.62), Color.black.opacity(0.84)],
                    countText: "\(round.rawValue) 轮次单校估算",
                    delayIndex: min(index, 12),
                    symbolName: symbol(for: result.bucket),
                    fontSize: 32
                )
            }
        }
    }

    private func color(for bucket: RecommendationBucket) -> Color {
        switch bucket {
        case .reach: .orange
        case .target: .blue
        case .likely: .green
        case .blocked: .red
        }
    }

    private func symbol(for bucket: RecommendationBucket) -> String {
        switch bucket {
        case .reach:
            return "flame"
        case .target:
            return "scope"
        case .likely:
            return "checkmark.seal"
        case .blocked:
            return "xmark.octagon"
        }
    }
}

private struct ReportTemplatePreview: View {
    let result: PortfolioResult

    var body: some View {
        AdmissionGradientCard(
            title: "报告模板",
            subtitle: "生成后报告会覆盖测算结果、当前不足、申请数量影响、学校简表、提升动作、选校策略和家庭沟通版结论。",
            systemImage: "doc.plaintext",
            colors: AdmissionStyle.mintNight
        ) {
            Text(ReportService.makeReport(result: result))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }
}

private struct ReportTextCard: View {
    let text: String
    let pdfURL: URL?
    let pdfErrorMessage: String?
    let onExportPDF: () -> Void

    var body: some View {
        AdmissionGradientCard(
            title: "生成报告",
            systemImage: "doc.text",
            colors: AdmissionStyle.mintNight
        ) {
            HStack(spacing: 10) {
                Button {
                    onExportPDF()
                } label: {
                    Label(pdfURL == nil ? "生成 PDF" : "重新生成 PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(AdmissionQuietButtonStyle())

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("下载 PDF", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.blackGlass))
                }
            }
            if let pdfErrorMessage {
                Label(pdfErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

enum ReportPDFRenderer {
    static func write(text: String, result: PortfolioResult, fileName: String) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 44
        let contentWidth = pageRect.width - margin * 2
        let bottomLimit = pageRect.height - margin
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: url) { context in
            beginPage(context: context, pageRect: pageRect)
            var y = drawHeader(result: result, in: pageRect, margin: margin)

            for rawLine in text.components(separatedBy: .newlines) {
                let displayLine = normalizeMarkdown(rawLine)
                let attributes = attributesForLine(rawLine)
                let lineHeight = height(for: displayLine, width: contentWidth, attributes: attributes)
                let spacing = displayLine.isEmpty ? CGFloat(6) : CGFloat(8)

                if y + lineHeight > bottomLimit {
                    beginPage(context: context, pageRect: pageRect)
                    y = drawHeader(result: result, in: pageRect, margin: margin)
                }

                let drawRect = CGRect(x: margin, y: y, width: contentWidth, height: lineHeight)
                (displayLine as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
                y += lineHeight + spacing
            }
        }

        return url
    }

    private static func beginPage(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        context.beginPage()
        UIColor.white.setFill()
        context.fill(pageRect)
    }

    private static func drawHeader(result: PortfolioResult, in pageRect: CGRect, margin: CGFloat) -> CGFloat {
        let title = "Admission Report"
        let subtitle = "Generated \(result.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(result.schoolResults.count) schools · At least one \(result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))"
        (title as NSString).draw(
            at: CGPoint(x: margin, y: margin),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
        (subtitle as NSString).draw(
            in: CGRect(x: margin, y: margin + 28, width: pageRect.width - margin * 2, height: 24),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 9.5, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
        return margin + 66
    }

    private static func normalizeMarkdown(_ line: String) -> String {
        var text = line
        while text.hasPrefix("#") {
            text.removeFirst()
        }
        return text
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func attributesForLine(_ line: String) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isHeading = trimmed.hasPrefix("#") || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil || trimmed.hasSuffix("：")
        return [
            .font: isHeading ? UIFont.systemFont(ofSize: 13.5, weight: .semibold) : UIFont.systemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
    }

    private static func height(for text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard !text.isEmpty else {
            return 6
        }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(rect.height)
    }
}
