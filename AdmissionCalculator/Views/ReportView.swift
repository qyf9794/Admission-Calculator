import SwiftUI
import UIKit

struct ReportView: View {
    let result: PortfolioResult?
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool
    var client = OpenAIReportClient()

    @State private var reportText: String?
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingDataSources = false

    var body: some View {
        ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 16) {
                    ReportHero(result: result)

                    if isStale {
                        Label("当前结果已过期；请先回到计算页重新计算，再生成付费报告。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    ReportActionCard(
                        result: result,
                        purchaseState: purchaseState,
                        isStale: isStale,
                        isGenerating: isGenerating,
                        errorMessage: errorMessage,
                        onGenerate: { generateReport(for: result) },
                        onShowDataSources: { showingDataSources = true }
                    )

                    ReportSchoolProbabilityList(results: result.schoolResults, round: result.profileSnapshot.round)

                    if result.profileSnapshot.round == .regularDecision {
                        if let reportText {
                            ReportTextCard(
                                text: reportText,
                                pdfURL: pdfURL,
                                pdfErrorMessage: pdfErrorMessage,
                                onExportPDF: { exportPDF(text: reportText, result: result) }
                            )
                        } else {
                            ReportTemplatePreview(result: result)
                        }
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("尚未生成报告", systemImage: "doc.text.magnifyingglass", description: Text("请先在计算页提交学生画像并计算结果。"))
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
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
    }

    private func generateReport(for result: PortfolioResult) {
        guard !isStale else {
            return
        }
        guard result.profileSnapshot.round == .regularDecision else {
            errorMessage = "综合报告仅支持 RD 轮次；EA/ED 结果只显示本轮概率，不生成综合报告。"
            return
        }
        purchaseState.unlockForPrototype()
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
                }
            } catch {
                await MainActor.run {
                    reportText = ReportService.makeReport(result: result)
                    pdfURL = nil
                    errorMessage = "OpenAI 生成失败，已显示本地模板报告：\(error.localizedDescription)"
                    isGenerating = false
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
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.12, green: 0.10, blue: 0.27)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(result.schoolResults.prefix(8).enumerated()), id: \.offset) { index, school in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: school.bucket))
                        .frame(width: 22, height: CGFloat(38 + index * 8) + CGFloat(school.adjustedProbability * 80))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.65)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("付费 AI 综合报告 · \(result.profileSnapshot.round.rawValue)", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Application Report")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(result.profileSnapshot.round == .regularDecision
                     ? "逐校解释概率、差距、提升路径和选校组合策略；AI 只解释已计算结果，不改变概率。"
                     : "EA/ED 只提供本轮次概率结果；综合报告仅开放给 RD 轮次。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ReportHeroMetric(title: "全部已选", value: result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))
                    ReportHeroMetric(title: "学校", value: "\(result.schoolResults.count)")
                    ReportHeroMetric(title: "阻断", value: "\(result.selectedBucketCounts.blocked)")
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private struct ReportHeroMetric: View {
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
        }
        .frame(minWidth: 56, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 12) {
            Label("报告生成", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.purple)
            Text("报告会围绕逐校概率、组合概率、差距优势和提升路径展开；AI 只解释已计算结果，不改变概率。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isStale || isGenerating || result.schoolResults.isEmpty || result.profileSnapshot.round != .regularDecision)

                Button {
                    onShowDataSources()
                } label: {
                    Label("说明", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
            }
            Text(purchaseState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AI 正在整理不足项、申请策略和学校简表，请保持页面打开。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ReportSchoolProbabilityList: View {
    let results: [ChanceResult]
    let round: ApplicationRound

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("逐校概率 · \(round.rawValue)", systemImage: "building.2.crop.circle")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("以下概率只对应 \(round.rawValue) 轮次；不会混合其他轮次。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if results.isEmpty {
                ContentUnavailableView("暂无逐校概率", systemImage: "building.columns", description: Text("请先在计算页选择学校并计算。"))
            }
            ForEach(results) { result in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.college.name)
                            .font(.subheadline.weight(.semibold))
                        Text("#\(result.college.rank) · \(result.college.tierDisplayName) · \(result.bucket.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(result.adjustedProbability.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(color(for: result.bucket))
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color(for: result.bucket).opacity(0.18), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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

private struct ReportTemplatePreview: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("报告模板", systemImage: "doc.plaintext")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("生成后报告会覆盖以下内容：测算结果、当前不足、申请数量影响、学校简表、提升动作、选校策略和家庭沟通版结论。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(ReportService.makeReport(result: result))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(12)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReportTextCard: View {
    let text: String
    let pdfURL: URL?
    let pdfErrorMessage: String?
    let onExportPDF: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("生成报告", systemImage: "doc.text")
                .font(.headline)
                .foregroundStyle(.green)
            HStack(spacing: 10) {
                Button {
                    onExportPDF()
                } label: {
                    Label(pdfURL == nil ? "生成 PDF" : "重新生成 PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("下载 PDF", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.16), lineWidth: 1)
        )
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
