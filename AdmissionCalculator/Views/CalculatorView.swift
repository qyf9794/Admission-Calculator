import SwiftUI

struct CalculatorView: View {
    @Binding var profile: StudentProfile
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    let onAutoRecommend: () -> Void
    let onEvaluate: () -> Void

    var body: some View {
        Form {
            Section("学生画像") {
                Picker("申请身份", selection: $profile.applicantStatus) {
                    ForEach(ApplicantStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
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
                CurriculumPerformanceInputs(profile: $profile)
                Picker("目标专业", selection: $profile.major) {
                    ForEach(MajorCategory.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("申请轮次", selection: $profile.round) {
                    ForEach(ApplicationRound.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Toggle("申请资助", isOn: $profile.needsAid)
            }

            Section("硬指标") {
                Toggle("Test Optional / 不提交标化", isOn: $profile.testOptional)
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

            Section("软实力") {
                BandStepper(title: "活动影响力", value: $profile.activities)
                BandStepper(title: "科研 / 夏校", value: $profile.research)
                BandStepper(title: "奖项区分度", value: $profile.honors)
                BandStepper(title: "文书成熟度", value: $profile.essay)
                BandStepper(title: "推荐信强度", value: $profile.recommendations)
                Toggle("艺术作品集已准备", isOn: $profile.hasPortfolio)
            }

            Section("中国高中背景") {
                Picker("高中学校", selection: $profile.highSchoolID) {
                    ForEach(AdmissionsSeedData.highSchools) { school in
                        Text("\(school.name) · \(school.city)").tag(school.id)
                    }
                }
            }

            Section("自动推荐组合") {
                Stepper("保底 \(profile.requestedLikelyCount) 所", value: $profile.requestedLikelyCount, in: 0...10)
                Stepper("目标 \(profile.requestedTargetCount) 所", value: $profile.requestedTargetCount, in: 0...12)
                Stepper("争取 \(profile.requestedReachCount) 所", value: $profile.requestedReachCount, in: 0...12)
                LabeledContent("计划数量", value: "\(requestedRecommendationTotal) 所")
                Button {
                    profile.requestedSchoolCount = requestedRecommendationTotal
                    onAutoRecommend()
                } label: {
                    Label("按三档生成组合", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestedRecommendationTotal == 0)
                if selectionSource == .automatic {
                    Label("已自动推荐 \(selectedCollegeIDs.count) 所学校", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("手动选校") {
                NavigationLink {
                    CollegePickerView(selectedCollegeIDs: $selectedCollegeIDs, selectionSource: $selectionSource)
                } label: {
                    Label(selectedCollegeIDs.isEmpty ? "尚未选择学校" : "已选择 \(selectedCollegeIDs.count) 所", systemImage: "building.columns")
                }
                if !selectedCollegeIDs.isEmpty {
                    Button("清空已选学校") {
                        selectedCollegeIDs.removeAll()
                        selectionSource = .none
                    }
                }
            }

            Section {
                Button(action: onEvaluate) {
                    Label("重新计算", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var requestedRecommendationTotal: Int {
        profile.requestedLikelyCount + profile.requestedTargetCount + profile.requestedReachCount
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
