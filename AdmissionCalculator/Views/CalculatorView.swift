import SwiftUI

struct CalculatorView: View {
    @Binding var profile: StudentProfile
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    let onAutoRecommend: () -> Void
    let onEvaluate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CalculatorHero(
                    selectedCount: selectedCollegeIDs.count,
                    promptCount: completionPrompts.count,
                    requestedTotal: requestedRecommendationTotal
                )

                ProfileReadinessCard(prompts: completionPrompts)

                CardSection(title: "学生画像", subtitle: "先确定身份、成绩口径、课程体系和申请方向。", systemImage: "person.text.rectangle", tint: .indigo) {
                Picker("申请身份", selection: $profile.applicantStatus) {
                    ForEach(ApplicantStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                GradeScaleInputs(
                    title: "GPA / 校内成绩",
                    scale: $profile.gradeScale,
                    percent: $profile.gpaPercent,
                    fourPoint: $profile.gpaFourPoint,
                    fivePoint: $profile.gpaFivePoint,
                    letterGrade: $profile.letterGrade
                )
                LabeledContent("年级排名百分位") {
                    Stepper("前 \(Int(profile.classRankPercentile))%", value: $profile.classRankPercentile, in: 1...80, step: 1)
                }
                Picker("课程体系", selection: $profile.curriculum) {
                    ForEach(CurriculumType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                CurriculumPerformanceInputs(profile: $profile)
                Picker("目标专业", selection: $profile.major) {
                    ForEach(MajorCategory.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                Picker("申请轮次", selection: $profile.round) {
                    ForEach(ApplicationRound.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("申请资助", isOn: $profile.needsAid)
            }

                CardSection(title: "硬指标", subtitle: "标化和语言成绩会先经过硬门槛，再进入概率修正。", systemImage: "target", tint: .teal) {
                Toggle("Test Optional / 不提交标化", isOn: testOptionalBinding)
                ScoreField(title: "SAT", value: $profile.sat, range: 900...1600, disabled: profile.testOptional)
                ScoreField(title: "ACT", value: $profile.act, range: 18...36, disabled: profile.testOptional)
                ScoreField(title: "TOEFL", value: $profile.toefl, range: 70...120, disabled: false)
                DecimalScoreField(title: "IELTS", value: $profile.ielts, range: 5.5...9.0, step: 0.5)
                if !profile.applicantStatus.requiresEnglishProof {
                    Text("当前申请身份通常不触发国际生英语硬门槛；语言成绩仍可作为学术证明。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("课程难度") {
                    Stepper("\(profile.rigor)/5", value: $profile.rigor, in: 1...5)
                }
            }

                CardSection(title: "软实力", subtitle: "顶尖校不能只看 GPA，活动、奖项、文书和推荐信会影响画像分。", systemImage: "sparkles", tint: .pink) {
                BandStepper(title: "活动影响力", value: $profile.activities)
                BandStepper(title: "科研 / 夏校", value: $profile.research)
                BandStepper(title: "奖项区分度", value: $profile.honors)
                BandStepper(title: "文书成熟度", value: $profile.essay)
                BandStepper(title: "推荐信强度", value: $profile.recommendations)
                Toggle("艺术作品集已准备", isOn: $profile.hasPortfolio)
            }

                CardSection(title: "中国高中背景", subtitle: "高中背景只是代理校准，不是个人录取证明。", systemImage: "graduationcap.fill", tint: .orange) {
                Picker("高中学校", selection: $profile.highSchoolID) {
                    ForEach(AdmissionsSeedData.highSchools) { school in
                        Text("\(school.name) · \(school.city)").tag(school.id)
                    }
                }
                .pickerStyle(.menu)
                Text("高中背景仅作为 AdmitRanking 风格代理校准；不确定时请选择“其他/手动评估学校”，避免默认名校背景抬高估算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                CardSection(title: "自动推荐数量", subtitle: "先设定三档数量，再用单独按钮生成组合。", systemImage: "slider.horizontal.3", tint: .blue) {
                Stepper("保底 \(profile.requestedLikelyCount) 所", value: $profile.requestedLikelyCount, in: 0...10)
                Stepper("目标 \(profile.requestedTargetCount) 所", value: $profile.requestedTargetCount, in: 0...12)
                Stepper("争取 \(profile.requestedReachCount) 所", value: $profile.requestedReachCount, in: 0...12)
                LabeledContent("计划数量", value: "\(requestedRecommendationTotal) 所")
            }

                CardSection(title: "选校动作", subtitle: "自动推荐不会悄悄触发；手动选校会切换为手动组合。", systemImage: "rectangle.stack.badge.plus", tint: .green) {
                Button {
                    profile.requestedSchoolCount = requestedRecommendationTotal
                    onAutoRecommend()
                } label: {
                    Label("按三档生成组合", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(requestedRecommendationTotal == 0)
                if selectionSource == .automatic {
                    Label("已自动推荐 \(selectedCollegeIDs.count) 所学校", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    CollegePickerView(selectedCollegeIDs: $selectedCollegeIDs, selectionSource: $selectionSource)
                } label: {
                    Label(selectedCollegeIDs.isEmpty ? "尚未选择学校" : "已选择 \(selectedCollegeIDs.count) 所", systemImage: "building.columns")
                }
                .buttonStyle(.bordered)
                if !selectedCollegeIDs.isEmpty {
                    Button("清空已选学校") {
                        selectedCollegeIDs.removeAll()
                        selectionSource = .none
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

                Button(action: onEvaluate) {
                    Label("重新计算", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var requestedRecommendationTotal: Int {
        profile.requestedLikelyCount + profile.requestedTargetCount + profile.requestedReachCount
    }

    private var completionPrompts: [ProfileCompletionPrompt] {
        profile.completionPrompts(selectedCollegeIDs: selectedCollegeIDs)
    }

    private var testOptionalBinding: Binding<Bool> {
        Binding(
            get: { profile.testOptional },
            set: { isOptional in
                profile.testOptional = isOptional
                if isOptional {
                    profile.sat = nil
                    profile.act = nil
                }
            }
        )
    }
}

private struct CalculatorHero: View {
    let selectedCount: Int
    let promptCount: Int
    let requestedTotal: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.18, blue: 0.32)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heroBlockColor(index))
                        .frame(width: 18, height: CGFloat(34 + index % 4 * 20))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.55)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("中国学生美本录取概率规划", systemImage: "sparkle.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Admit Chance")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("用硬门槛、学术匹配、国际生数据和中国本科录取容量，生成可解释的选校估算。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    HeroMetric(title: "已选", value: "\(selectedCount)")
                    HeroMetric(title: "待补", value: "\(promptCount)")
                    HeroMetric(title: "计划", value: "\(requestedTotal)")
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 238)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func heroBlockColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue, .green, .red]
        return colors[index % colors.count]
    }
}

private struct HeroMetric: View {
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

private struct ProfileReadinessCard: View {
    let prompts: [ProfileCompletionPrompt]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: prompts.isEmpty ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                    .foregroundStyle(prompts.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompts.isEmpty ? "关键资料已就绪" : "需要补充的关键信息")
                        .font(.headline)
                    Text(prompts.isEmpty ? "可以直接计算，也可以继续微调选校组合。" : "这些信息会影响硬门槛、置信度或推荐组合。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if prompts.isEmpty {
                Text("系统仍会在结果页披露数据缺口、推断基准和来源审计。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(prompts.prefix(4)) { prompt in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.impact.rawValue)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(promptImpactColor(prompt.impact).opacity(0.14), in: Capsule())
                                .foregroundStyle(promptImpactColor(prompt.impact))
                            Text(prompt.title)
                                .font(.subheadline.weight(.semibold))
                            Text(prompt.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: prompt.systemImage)
                            .foregroundStyle(.orange)
                    }
                }
                if prompts.count > 4 {
                    Text("还有 \(prompts.count - 4) 项可补充信息会在后续细化中影响判断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((prompts.isEmpty ? Color.green : Color.orange).opacity(0.22), lineWidth: 1)
        )
    }

    private func promptImpactColor(_ impact: ProfileCompletionImpact) -> Color {
        switch impact {
        case .gate:
            return .red
        case .probability:
            return .blue
        case .confidence:
            return .orange
        case .portfolio:
            return .purple
        }
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    private let content: Content

    init(title: String, subtitle: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CurriculumPerformanceInputs: View {
    @Binding var profile: StudentProfile

    var body: some View {
        switch profile.curriculum {
        case .chinese:
            GradeScaleInputs(
                title: "核心课程成绩",
                scale: $profile.curriculumGradeScale,
                percent: $profile.chineseCurriculumScore,
                fourPoint: $profile.chineseCurriculumGPAFourPoint,
                fivePoint: $profile.chineseCurriculumGPAFivePoint,
                letterGrade: $profile.chineseCurriculumLetterGrade
            )
        case .ap:
            LabeledContent("AP / 高级课程门数") {
                Stepper("\(profile.apCourseCount)", value: $profile.apCourseCount, in: 0...12)
            }
            if profile.apCourseCount > 0 {
                LabeledContent("AP 平均分") {
                    Stepper(String(format: "%.1f", profile.apAverageScore), value: $profile.apAverageScore, in: 1...5, step: 0.5)
                }
            } else {
                Text("AP 课程门数为 0 时，AP 平均分不会计入课程体系成绩。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ib:
            LabeledContent("IB 预估总分") {
                Stepper("\(profile.ibPredictedScore)", value: $profile.ibPredictedScore, in: 24...45)
            }
        case .alevel:
            LabeledContent("A-Level A* 科目") {
                Stepper("\(profile.aLevelAStarCount)", value: $profile.aLevelAStarCount, in: 0...5)
            }
            LabeledContent("A-Level A 科目") {
                Stepper("\(profile.aLevelACount)", value: $profile.aLevelACount, in: 0...5)
            }
            LabeledContent("A-Level B 科目") {
                Stepper("\(profile.aLevelBCount)", value: $profile.aLevelBCount, in: 0...5)
            }
        }
    }
}

private struct GradeScaleInputs: View {
    let title: String
    @Binding var scale: GradeScale
    @Binding var percent: Double
    @Binding var fourPoint: Double
    @Binding var fivePoint: Double
    @Binding var letterGrade: LetterGradeBand

    var body: some View {
        Picker("\(title)方式", selection: $scale) {
            ForEach(GradeScale.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }

        switch scale {
        case .percent:
            LabeledContent(title) {
                Stepper("\(Int(percent))", value: $percent, in: 60...100, step: 1)
            }
        case .fourPoint:
            LabeledContent(title) {
                Stepper(String(format: "%.1f", fourPoint), value: $fourPoint, in: 0...4, step: 0.1)
            }
        case .fivePoint:
            LabeledContent(title) {
                Stepper(String(format: "%.1f", fivePoint), value: $fivePoint, in: 0...5, step: 0.1)
            }
        case .letter:
            Picker(title, selection: $letterGrade) {
                ForEach(LetterGradeBand.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
        }
    }
}

private struct ScoreField: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let disabled: Bool

    var body: some View {
        LabeledContent(title) {
            HStack {
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(value == nil)

                Stepper(value.map(String.init) ?? "未填写", value: Binding(
                    get: { value ?? range.lowerBound },
                    set: { value = $0 }
                ), in: range, step: title == "SAT" ? 10 : 1)
                .disabled(disabled)
            }
        }
    }
}

private struct DecimalScoreField: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            HStack {
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(value == nil)

                Stepper(value.map { String(format: "%.1f", $0) } ?? "未填写", value: Binding(
                    get: { value ?? range.lowerBound },
                    set: { value = $0 }
                ), in: range, step: step)
            }
        }
    }
}

private struct BandStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            Stepper("\(value)/5", value: $value, in: 1...5)
        }
    }
}
