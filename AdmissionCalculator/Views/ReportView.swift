import SwiftUI
import UIKit
import QuickLook

struct ReportView: View {
    let result: PortfolioResult?
    @Binding var generatedReports: [GeneratedReportPDF]
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool
    let onBackToResults: () -> Void
    let onStartOver: () -> Void
    var client = ReportProxyClient()

    @State private var pdfPreviewDocument: ReportPDFDocument?
    @State private var pdfErrorMessage: String?
    @State private var isPaymentInProgress = false
    @State private var isGenerating = false
    @State private var generationPhase: ReportGenerationPhase?
    @State private var generationProgress = 0.0
    @State private var virtualProgressTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showingDataSources = false
    @State private var showingPaymentSheet = false
    @State private var showingGeneratedReports = false

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            ScrollView {
            if let result {
                AdmissionSwipeableCard(
                    canSwipeBack: true,
                    canSwipeForward: false,
                    onSwipeBack: onBackToResults,
                    onSwipeForward: {},
                    previousPreview: {
                        ResultsFixedSnapshotContent(result: result)
                    },
                    nextPreview: {
                        EmptyView()
                    }
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isStale {
                            Label("当前结果已过期；请先回到计算页重新计算，再生成付费报告。", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
                        }

                        ResultsSnapshotCard(result: result, onStartOver: onStartOver, showsSubtitle: false)

                        ReportActionCard(
                            result: result,
                            purchaseState: purchaseState,
                            isStale: isStale,
                            isGenerating: isGenerating,
                            generationPhase: generationPhase,
                            generationProgress: generationProgress,
                            errorMessage: errorMessage,
                            pdfErrorMessage: pdfErrorMessage,
                            onGenerate: { showingPaymentSheet = true },
                            onShowDataSources: { showingDataSources = true }
                        )

                        ReportFrameworkPreview(
                            reportCount: generatedReports.count,
                            onPreviewReports: { showingGeneratedReports = true }
                        )
                    }
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
                    priceText: purchaseState.priceText,
                    hasPendingPaidReport: purchaseState.hasPendingPaidReport,
                    isPaymentInProgress: isPaymentInProgress,
                    isGenerating: isGenerating,
                    errorMessage: errorMessage,
                    onCancel: { showingPaymentSheet = false },
                    onPayAndGenerate: { completePaymentAndGenerate(for: result) }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingGeneratedReports) {
            GeneratedReportsSheet(
                reports: generatedReports,
                onPreview: { previewGeneratedReport($0) },
                onDelete: { deleteGeneratedReports(at: $0) }
            )
        }
        .sheet(item: $pdfPreviewDocument) { document in
            ReportPDFPreviewSheet(document: document)
        }
        .task {
            await purchaseState.loadProduct()
        }
    }

    private func completePaymentAndGenerate(for result: PortfolioResult) {
        guard !isStale else {
            errorMessage = "当前参数或选校已变化。请先回到计算页重新计算，再为新的结果生成报告。"
            return
        }
        guard result.profileSnapshot.round == .regularDecision else {
            errorMessage = "综合报告仅支持 RD 轮次；EA/ED 结果只显示本轮概率，不生成综合报告。"
            return
        }
        guard client.isConfigured else {
            errorMessage = "报告生成服务尚未配置。请先配置 REPORT_PROXY_URL 或 Info.plist 的 ReportProxyURL。"
            return
        }
        isPaymentInProgress = true
        isGenerating = false
        generationPhase = nil
        generationProgress = 0
        errorMessage = nil
        pdfErrorMessage = nil

        Task {
            do {
                let transaction = try await purchaseState.purchaseOrUsePendingToken()
                await MainActor.run {
                    isPaymentInProgress = false
                    isGenerating = true
                    generationPhase = .paymentVerified
                    generationProgress = 0.20
                    showingPaymentSheet = false
                    startVirtualReportProgress()
                }
                let prompt = ReportService.makeOpenAIReportPrompt(result: result)
                await MainActor.run {
                    generationPhase = .modelRequestStarted
                }
                let generated = try await client.generateReport(prompt: prompt, transaction: transaction)
                await MainActor.run {
                    generationPhase = .modelReturned
                }
                let merged = ReportService.mergeGeneratedReport(generated, result: result)
                var previewURL: URL?
                await MainActor.run {
                    do {
                        generationPhase = .pdfWriting
                        advanceGenerationProgress(to: 0.99)
                        let url = try writePDF(text: merged, result: result)
                        let report = GeneratedReportPDF(
                            url: url,
                            resultGeneratedAt: result.generatedAt,
                            createdAt: Date(),
                            schoolCount: result.schoolResults.count,
                            selectedAtLeastOne: result.selectedAtLeastOne
                        )
                        generatedReports.insert(report, at: 0)
                        previewURL = url
                        pdfErrorMessage = nil
                        generationPhase = .pdfWritten
                        advanceGenerationProgress(to: 1.00)
                    } catch {
                        pdfErrorMessage = "PDF 预览生成失败：\(error.localizedDescription)"
                    }
                    stopVirtualReportProgress()
                    purchaseState.markReportGenerated()
                }
                if let previewURL {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    await MainActor.run {
                        pdfPreviewDocument = ReportPDFDocument(url: previewURL)
                        isGenerating = false
                        generationPhase = nil
                    }
                } else {
                    await MainActor.run {
                        isGenerating = false
                        generationPhase = nil
                    }
                }
            } catch let error as ReportPurchaseError where error == .userCancelled {
                await MainActor.run {
                    stopVirtualReportProgress()
                    errorMessage = error.localizedDescription
                    isPaymentInProgress = false
                    isGenerating = false
                    generationPhase = nil
                    generationProgress = 0
                }
            } catch {
                await MainActor.run {
                    stopVirtualReportProgress()
                    errorMessage = "报告生成失败。如已完成支付，本次支付凭证会保留在本机，可稍后重试：\(error.localizedDescription)"
                    isPaymentInProgress = false
                    isGenerating = false
                    generationPhase = nil
                    generationProgress = 0
                }
            }
        }
    }

    @MainActor
    private func startVirtualReportProgress() {
        stopVirtualReportProgress()
        virtualProgressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard isGenerating, generationPhase != .pdfWritten else {
                    break
                }
                let ceiling = generationPhase == .pdfWriting ? 0.99 : 0.98
                let remaining = ceiling - generationProgress
                guard remaining > 0.001 else {
                    continue
                }
                let step = min(0.018, max(0.003, remaining * 0.08))
                advanceGenerationProgress(to: min(ceiling, generationProgress + step))
            }
        }
    }

    @MainActor
    private func stopVirtualReportProgress() {
        virtualProgressTask?.cancel()
        virtualProgressTask = nil
    }

    @MainActor
    private func advanceGenerationProgress(to target: Double) {
        let clampedTarget = min(1, max(0, target))
        guard clampedTarget > generationProgress else {
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            generationProgress = clampedTarget
        }
    }

    private func writePDF(text: String, result: PortfolioResult) throws -> URL {
        try ReportPDFRenderer.write(
            text: text,
            result: result,
            fileName: "Admission-Report-\(Self.pdfDateFormatter.string(from: result.generatedAt)).pdf"
        )
    }

    private func previewGeneratedReport(_ report: GeneratedReportPDF) {
        showingGeneratedReports = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            pdfPreviewDocument = ReportPDFDocument(url: report.url)
        }
    }

    private func deleteGeneratedReports(at offsets: IndexSet) {
        for index in offsets {
            guard generatedReports.indices.contains(index) else {
                continue
            }
            let report = generatedReports[index]
            try? FileManager.default.removeItem(at: report.url)
        }
        generatedReports.remove(atOffsets: offsets)
        if generatedReports.isEmpty {
            showingGeneratedReports = false
        }
    }

    private static let pdfDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()
}

struct ReportPageSnapshotContent: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ResultsSnapshotCard(result: result, showsSubtitle: false)
            AdmissionGradientCard(
                title: "报告生成",
                subtitle: "报告会围绕逐校概率、组合概率、差距优势和提升路径展开。",
                systemImage: "sparkles",
                colors: AdmissionStyle.pinkMist
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                    Text("付费生成报告")
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: AdmissionStyle.blackGlass, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                Text("综合报告未付费生成")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
            }
            ReportFrameworkPreview(reportCount: 0, onPreviewReports: {})
        }
    }
}

private struct ReportFrameworkPreview: View {
    let reportCount: Int
    let onPreviewReports: () -> Void

    private let sections = [
        ("测算摘要", "组合概率、风险层级、是否存在硬门槛阻断。"),
        ("逐校解释", "每所已选学校的概率、主要加分项和主要扣分项。"),
        ("学术画像对比", "用通俗语言解释成绩、排名、课程难度和标化相对目标校可比水平的位置。"),
        ("选校组合策略", "申请数量、排名价值、自动推荐逻辑和组合风险。"),
        ("提升行动计划", "短期补强事项、材料重点、家庭沟通版结论。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.headline.weight(.bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(AdmissionStyle.textPrimary)
                    .background(AdmissionStyle.textPrimary.opacity(0.14), in: Circle())
                Text("报告包含内容")
                    .font(AdmissionStyle.sectionFont())
                    .foregroundStyle(AdmissionStyle.textPrimary)

                Spacer(minLength: 8)

                if reportCount > 0 {
                    Button {
                        onPreviewReports()
                    } label: {
                        Label("预览报告", systemImage: "doc.richtext")
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .buttonStyle(AdmissionQuietButtonStyle())
                    .accessibilityLabel("预览已生成报告")
                }
            }

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
        .font(AdmissionStyle.bodyFont())
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: AdmissionStyle.mintNight, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.cornerRadius, style: .continuous)
                .stroke(AdmissionStyle.hairline, lineWidth: 1)
        )
        .foregroundStyle(AdmissionStyle.textPrimary)
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

private struct ReportPaymentSheet: View {
    let priceText: String
    let hasPendingPaidReport: Bool
    let isPaymentInProgress: Bool
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
                Text(hasPendingPaidReport ? "检测到本机已有已支付但未完成的报告生成凭证，本次会直接继续生成，不会再次扣费。生成完成后会自动打开 PDF 预览。" : "通过 Apple 内购按次购买完整录取分析报告。付款确认后报告会在后台生成，完成后直接打开 PDF 预览。")
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.62))
                Label(hasPendingPaidReport ? "待生成报告" : priceText, systemImage: hasPendingPaidReport ? "checkmark.seal.fill" : "creditcard.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.68))
                if let errorMessage {
                    Label(errorMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .buttonStyle(AdmissionQuietButtonStyle(foreground: .black))
                        .disabled(isPaymentInProgress || isGenerating)
                    Button(action: onPayAndGenerate) {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text(isGenerating ? "正在生成" : (hasPendingPaidReport ? "继续生成" : "支付并后台生成"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.blackGlass))
                    .disabled(isPaymentInProgress || isGenerating)
                }
            }
            .padding(18)
        }
    }
}

private struct ReportActionCard: View {
    let result: PortfolioResult
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool
    let isGenerating: Bool
    let generationPhase: ReportGenerationPhase?
    let generationProgress: Double
    let errorMessage: String?
    let pdfErrorMessage: String?
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
                            Image(systemName: purchaseState.hasPendingPaidReport ? "checkmark.seal.fill" : "lock.open")
                        }
                        Text(isGenerating ? "正在生成" : (purchaseState.hasPendingPaidReport ? "继续生成报告" : "付费生成报告"))
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.blackGlass))
                .disabled(isGenerating || result.schoolResults.isEmpty || result.profileSnapshot.round != .regularDecision)

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
                ReportGenerationProgressView(phase: generationPhase ?? .paymentVerified, progress: generationProgress)
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
            if let pdfErrorMessage {
                Label(pdfErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct ReportGenerationProgressView: View {
    let phase: ReportGenerationPhase
    let progress: Double

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    private var percentText: String {
        "\(Int((clampedProgress * 100).rounded()))%"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
            let pulse = timeline.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 5)
                        Circle()
                            .trim(from: 0.12, to: 0.82)
                            .stroke(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.36)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(pulse * 120))
                        Image(systemName: phase.symbolName)
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(phase.title)
                                .font(.subheadline.weight(.black))
                            if phase != .pdfWritten {
                                LoadingDots(elapsed: pulse)
                            }
                        }
                        Text(phase.detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.70))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(percentText)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }

                AnimatedProgressBar(progress: clampedProgress, elapsed: pulse)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: clampedProgress)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Array(ReportGenerationPhase.allCases.enumerated()), id: \.element) { _, step in
                        HStack(spacing: 7) {
                            Image(systemName: iconName(for: step, currentPhase: phase))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(step.rawValue <= phase.rawValue ? .white : .white.opacity(0.42))
                                .frame(width: 15)
                            Text(step.stepTitle)
                                .font(.caption2.weight(step == phase ? .bold : .medium))
                                .foregroundStyle(step.rawValue <= phase.rawValue ? .white.opacity(0.86) : .white.opacity(0.48))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("报告生成中，\(phase.title)，进度 \(percentText)")
        }
    }

    private func iconName(for step: ReportGenerationPhase, currentPhase: ReportGenerationPhase) -> String {
        if step.rawValue < currentPhase.rawValue {
            return "checkmark.circle.fill"
        }
        if step == currentPhase {
            return "circle.dotted"
        }
        return "circle"
    }
}

enum ReportGenerationPhase: Int, CaseIterable {
    case paymentVerified
    case modelRequestStarted
    case modelReturned
    case pdfWriting
    case pdfWritten

    var stepTitle: String {
        switch self {
        case .paymentVerified:
            return "支付完成"
        case .modelRequestStarted:
            return "请求模型"
        case .modelReturned:
            return "模型返回"
        case .pdfWriting:
            return "写入 PDF"
        case .pdfWritten:
            return "PDF 完成"
        }
    }

    var title: String {
        switch self {
        case .paymentVerified:
            return "支付已完成"
        case .modelRequestStarted:
            return "正在请求模型"
        case .modelReturned:
            return "模型已返回"
        case .pdfWriting:
            return "正在写入 PDF"
        case .pdfWritten:
            return "PDF 已生成"
        }
    }

    var detail: String {
        switch self {
        case .paymentVerified:
            return "支付已收起，正在回到报告卡片并整理报告事实包。"
        case .modelRequestStarted:
            return "已发起模型请求，进度会持续前进直到 PDF 写入。"
        case .modelReturned:
            return "模型正文已返回，正在合并概率校验。"
        case .pdfWriting:
            return "正在写入 PDF，完成后会自动打开报告预览。"
        case .pdfWritten:
            return "PDF 已写入完成，即将自动打开报告预览。"
        }
    }

    var symbolName: String {
        switch self {
        case .paymentVerified:
            return "checkmark.seal.fill"
        case .modelRequestStarted:
            return "paperplane.fill"
        case .modelReturned:
            return "sparkles"
        case .pdfWriting:
            return "square.and.pencil"
        case .pdfWritten:
            return "doc.richtext.fill"
        }
    }
}

struct GeneratedReportPDF: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let resultGeneratedAt: Date
    let createdAt: Date
    let schoolCount: Int
    let selectedAtLeastOne: Double
}

private struct GeneratedReportsSheet: View {
    let reports: [GeneratedReportPDF]
    let onPreview: (GeneratedReportPDF) -> Void
    let onDelete: (IndexSet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if reports.isEmpty {
                    ContentUnavailableView("暂无已生成报告", systemImage: "doc.text.magnifyingglass", description: Text("完成报告生成后会出现在这里。"))
                } else {
                    ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                        Button {
                            onPreview(report)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: index == 0 ? "doc.richtext.fill" : "doc.richtext")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(index == 0 ? AdmissionStyle.controlBlue : Color.secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(index == 0 ? "最新生成报告" : "已生成报告")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Color.primary)
                                    Text(report.createdAt.formatted(date: .numeric, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                    Text("\(report.schoolCount) 所学校 · 至少一所 \(report.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.secondary.opacity(0.62))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .onDelete(perform: onDelete)
                }
            }
            .navigationTitle("预览报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(reports.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LoadingDots: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.84))
                    .frame(width: 4, height: 4)
                    .scaleEffect(dotScale(index: index))
            }
        }
        .frame(width: 22, height: 8)
        .accessibilityHidden(true)
    }

    private func dotScale(index: Int) -> CGFloat {
        let wave = sin((elapsed * 5.2) - Double(index) * 0.75)
        return 0.72 + CGFloat(max(0, wave)) * 0.46
    }
}

private struct AnimatedProgressBar: View {
    let progress: Double
    let elapsed: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = max(24, width * progress)
            let highlightWidth = max(38, width * 0.20)
            let highlightOffset = (elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8) * (fillWidth + highlightWidth) - highlightWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.50),
                                Color.white.opacity(0.88),
                                Color.white.opacity(0.56)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: highlightWidth)
                            .offset(x: highlightOffset)
                            .blur(radius: 5)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct ReportPDFDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ReportPDFPreviewSheet: View {
    let document: ReportPDFDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookPDFPreview(url: document.url)
                .navigationTitle("录取分析报告")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: document.url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct QuickLookPDFPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
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

private struct ReportTextCard: View {
    let text: String
    let pdfURL: URL?
    let pdfErrorMessage: String?
    let onExportPDF: () -> Void

    var body: some View {
        GeometryReader { proxy in
            AdmissionGradientCard(
                title: "生成报告",
                systemImage: "doc.text",
                colors: AdmissionStyle.mintNight,
                fixedHeight: proxy.size.height
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
                ScrollView {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            y = drawProbabilityCards(result: result, in: pageRect, margin: margin, y: y) + 18

            let lines = text.components(separatedBy: .newlines)
            var lineIndex = 0
            while lineIndex < lines.count {
                if let table = markdownTable(startingAt: lineIndex, in: lines) {
                    y = drawMarkdownTable(
                        table,
                        context: context,
                        result: result,
                        pageRect: pageRect,
                        margin: margin,
                        startY: y,
                        contentWidth: contentWidth,
                        bottomLimit: bottomLimit
                    )
                    lineIndex = table.nextLineIndex
                    continue
                }

                let rawLine = lines[lineIndex]
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
                lineIndex += 1
            }
        }

        return url
    }

    private struct MarkdownTable {
        let headers: [String]
        let rows: [[String]]
        let nextLineIndex: Int
    }

    private static func beginPage(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        context.beginPage()
        UIColor.white.setFill()
        context.fill(pageRect)
    }

    private static func drawHeader(result: PortfolioResult, in pageRect: CGRect, margin: CGFloat) -> CGFloat {
        let logoRect = CGRect(x: margin, y: margin - 2, width: 42, height: 42)
        drawLogo(in: logoRect)

        let title = "美本录取计算器"
        let subtitle = "Admission Report · 录取分析报告"
        let detail = "Generated \(result.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(result.schoolResults.count) schools · At least one \(result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))"
        let textX = logoRect.maxX + 12
        (title as NSString).draw(
            at: CGPoint(x: textX, y: margin - 1),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )
        (subtitle as NSString).draw(
            in: CGRect(x: textX, y: margin + 23, width: pageRect.width - textX - margin, height: 16),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: UIColor.darkGray
            ]
        )
        (detail as NSString).draw(
            in: CGRect(x: margin, y: margin + 50, width: pageRect.width - margin * 2, height: 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8.8, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
        return margin + 82
    }

    private static func drawLogo(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        if let image = UIImage(named: "AppLogo") {
            guard let cgContext = UIGraphicsGetCurrentContext() else {
                image.draw(in: rect)
                return
            }
            cgContext.saveGState()
            defer { cgContext.restoreGState() }
            UIColor.white.setFill()
            path.fill()
            path.addClip()
            image.draw(in: rect)
        } else {
            UIColor(red: 0.88, green: 0.13, blue: 0.50, alpha: 1).setFill()
            path.fill()
            let symbol = "A+"
            (symbol as NSString).draw(
                in: rect.insetBy(dx: 7, dy: 10),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .black),
                    .foregroundColor: UIColor.white
                ]
            )
        }
        UIColor(white: 0, alpha: 0.08).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private static func drawProbabilityCards(result: PortfolioResult, in pageRect: CGRect, margin: CGFloat, y: CGFloat) -> CGFloat {
        let contentWidth = pageRect.width - margin * 2
        let gap: CGFloat = 10
        let leftWidth: CGFloat = 178
        let rightWidth = contentWidth - leftWidth - gap
        let smallWidth = (rightWidth - gap) / 2
        let smallHeight: CGFloat = 50
        let totalHeight = smallHeight * 3 + gap * 2

        drawCard(
            rect: CGRect(x: margin, y: y, width: leftWidth, height: totalHeight),
            title: "全部已选至少一所",
            value: result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))),
            detail: "\(result.schoolResults.count) 所学校 · \(result.selectionSource.rawValue)",
            fill: UIColor(red: 0.88, green: 0.13, blue: 0.50, alpha: 1),
            valueSize: 34
        )

        let metrics: [(String, String, String, UIColor)] = [
            ("综大 T10", result.t10AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .nationalUniversity, maxRank: 10, result: result)) 所", UIColor(red: 0.50, green: 0.18, blue: 0.82, alpha: 1)),
            ("综大 T11-T30", result.t11T30AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .nationalUniversity, minRankExclusive: 10, maxRank: 30, result: result)) 所", UIColor(red: 0.27, green: 0.30, blue: 0.86, alpha: 1)),
            ("综大 T30", result.t30AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .nationalUniversity, maxRank: 30, result: result)) 所", UIColor(red: 0.10, green: 0.34, blue: 0.95, alpha: 1)),
            ("综大 T50", result.t50AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .nationalUniversity, maxRank: 50, result: result)) 所", UIColor(red: 0.03, green: 0.50, blue: 0.52, alpha: 1)),
            ("文理 T10", result.liberalArtsT10AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .liberalArtsCollege, maxRank: 10, result: result)) 所", UIColor(red: 0.85, green: 0.44, blue: 0.84, alpha: 1)),
            ("文理 T30", result.liberalArtsT30AtLeastOne.formatted(.percent.precision(.fractionLength(0))), "\(tierCount(category: .liberalArtsCollege, maxRank: 30, result: result)) 所", UIColor(red: 0.95, green: 0.43, blue: 0.48, alpha: 1))
        ]

        for (index, metric) in metrics.enumerated() {
            let column = index % 2
            let row = index / 2
            let rect = CGRect(
                x: margin + leftWidth + gap + CGFloat(column) * (smallWidth + gap),
                y: y + CGFloat(row) * (smallHeight + gap),
                width: smallWidth,
                height: smallHeight
            )
            drawCard(
                rect: rect,
                title: metric.0,
                value: metric.1,
                detail: metric.2,
                fill: metric.3,
                valueSize: 15
            )
        }

        let note = "以上概率均为当前 RD 选校组合的估算结果，不代表录取承诺；PDF 正文中的表格继续逐校解释差距和行动。"
        let noteRect = CGRect(x: margin, y: y + totalHeight + 8, width: contentWidth, height: 18)
        (note as NSString).draw(
            in: noteRect,
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8.8, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
        )
        return y + totalHeight + 26
    }

    private static func drawCard(rect: CGRect, title: String, value: String, detail: String, fill: UIColor, valueSize: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        fill.setFill()
        path.fill()

        UIColor(white: 1, alpha: 0.22).setStroke()
        path.lineWidth = 0.7
        path.stroke()

        (title as NSString).draw(
            in: CGRect(x: rect.minX + 10, y: rect.minY + 8, width: rect.width - 20, height: 12),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8.5, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.72)
            ]
        )
        (value as NSString).draw(
            in: CGRect(x: rect.minX + 10, y: rect.minY + (rect.height > 70 ? 32 : 19), width: rect.width - 20, height: valueSize + 8),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: valueSize, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        )
        (detail as NSString).draw(
            in: CGRect(x: rect.minX + 10, y: rect.maxY - 18, width: rect.width - 20, height: 12),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 7.8, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.66)
            ]
        )
    }

    private static func tierCount(category: CollegeCategory, minRankExclusive: Int = 0, maxRank: Int, result: PortfolioResult) -> Int {
        result.schoolResults.filter { $0.college.category == category && $0.college.rank > minRankExclusive && $0.college.rank <= maxRank }.count
    }

    private static func markdownTable(startingAt index: Int, in lines: [String]) -> MarkdownTable? {
        guard index + 1 < lines.count,
              let headers = parseMarkdownTableRow(lines[index]),
              headers.count >= 2,
              isMarkdownSeparatorLine(lines[index + 1])
        else {
            return nil
        }

        var rows: [[String]] = []
        var nextIndex = index + 2
        while nextIndex < lines.count,
              let row = parseMarkdownTableRow(lines[nextIndex]),
              !isMarkdownSeparatorLine(lines[nextIndex]) {
            rows.append(normalizedTableCells(row, count: headers.count))
            nextIndex += 1
        }

        return MarkdownTable(
            headers: normalizedTableCells(headers, count: headers.count),
            rows: rows,
            nextLineIndex: nextIndex
        )
    }

    private static func parseMarkdownTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return nil
        }

        var content = trimmed
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }

        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { normalizeMarkdown(String($0)) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isMarkdownSeparatorLine(_ line: String) -> Bool {
        guard let cells = parseMarkdownTableRow(line) else {
            return false
        }
        return cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            guard compact.contains("-") else {
                return false
            }
            return compact.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private static func normalizedTableCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count > count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func drawMarkdownTable(
        _ table: MarkdownTable,
        context: UIGraphicsPDFRendererContext,
        result: PortfolioResult,
        pageRect: CGRect,
        margin: CGFloat,
        startY: CGFloat,
        contentWidth: CGFloat,
        bottomLimit: CGFloat
    ) -> CGFloat {
        let columnWidths = tableColumnWidths(columnCount: table.headers.count, contentWidth: contentWidth)
        let headerAttributes = tableCellAttributes(isHeader: true)
        let bodyAttributes = tableCellAttributes(isHeader: false)
        var y = startY + 3

        func drawHeaderIfNeeded() {
            let headerHeight = tableRowHeight(cells: table.headers, columnWidths: columnWidths, attributes: headerAttributes)
            if y + headerHeight > bottomLimit {
                beginPage(context: context, pageRect: pageRect)
                y = drawHeader(result: result, in: pageRect, margin: margin)
            }
            drawTableRow(
                cells: table.headers,
                x: margin,
                y: y,
                columnWidths: columnWidths,
                height: headerHeight,
                attributes: headerAttributes,
                isHeader: true
            )
            y += headerHeight
        }

        drawHeaderIfNeeded()

        for row in table.rows {
            let rowHeight = tableRowHeight(cells: row, columnWidths: columnWidths, attributes: bodyAttributes)
            if y + rowHeight > bottomLimit {
                beginPage(context: context, pageRect: pageRect)
                y = drawHeader(result: result, in: pageRect, margin: margin)
                drawHeaderIfNeeded()
            }
            drawTableRow(
                cells: row,
                x: margin,
                y: y,
                columnWidths: columnWidths,
                height: rowHeight,
                attributes: bodyAttributes,
                isHeader: false
            )
            y += rowHeight
        }

        return y + 12
    }

    private static func tableColumnWidths(columnCount: Int, contentWidth: CGFloat) -> [CGFloat] {
        guard columnCount > 0 else {
            return []
        }
        let firstColumnWeight: CGFloat = columnCount >= 3 ? 1.35 : 1.0
        let otherColumnWeight: CGFloat = 1.0
        let totalWeight = firstColumnWeight + CGFloat(columnCount - 1) * otherColumnWeight
        return (0..<columnCount).map { index in
            let weight = index == 0 ? firstColumnWeight : otherColumnWeight
            return floor(contentWidth * weight / totalWeight)
        }
    }

    private static func tableCellAttributes(isHeader: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 0
        return [
            .font: UIFont.systemFont(ofSize: isHeader ? 8.2 : 7.8, weight: isHeader ? .semibold : .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
    }

    private static func tableRowHeight(cells: [String], columnWidths: [CGFloat], attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let padding: CGFloat = 8
        let heights = cells.enumerated().map { index, cell in
            let width = max(16, columnWidths[min(index, columnWidths.count - 1)] - padding * 2)
            return height(for: cell, width: width, attributes: attributes) + padding * 2
        }
        return max(24, ceil(heights.max() ?? 24))
    }

    private static func drawTableRow(
        cells: [String],
        x: CGFloat,
        y: CGFloat,
        columnWidths: [CGFloat],
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        isHeader: Bool
    ) {
        let fillColor = isHeader ? UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1) : UIColor.white
        let borderColor = UIColor(white: 0.84, alpha: 1)
        var currentX = x

        for (index, cell) in cells.enumerated() {
            let width = columnWidths[min(index, columnWidths.count - 1)]
            let cellRect = CGRect(x: currentX, y: y, width: width, height: height)
            fillColor.setFill()
            UIRectFill(cellRect)
            borderColor.setStroke()
            let borderPath = UIBezierPath(rect: cellRect)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            let textRect = cellRect.insetBy(dx: 8, dy: 6)
            (cell as NSString).draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            currentX += width
        }
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
