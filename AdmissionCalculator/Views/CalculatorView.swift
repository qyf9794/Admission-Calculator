import SwiftUI

struct CalculatorView: View {
    @Binding var profile: StudentProfile
    @Binding var selectedCollegeIDs: Set<String>
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

            Section("选校") {
                Stepper("自动推荐 \(profile.requestedSchoolCount) 所", value: $profile.requestedSchoolCount, in: 1...30)
                NavigationLink {
                    CollegePickerView(selectedCollegeIDs: $selectedCollegeIDs)
                } label: {
                    Label(selectedCollegeIDs.isEmpty ? "使用自动推荐组合" : "已手选 \(selectedCollegeIDs.count) 所", systemImage: "building.columns")
                }
                if !selectedCollegeIDs.isEmpty {
                    Button("清空手选学校") {
                        selectedCollegeIDs.removeAll()
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
            LabeledContent("AP 平均分") {
                Stepper(String(format: "%.1f", profile.apAverageScore), value: $profile.apAverageScore, in: 1...5, step: 0.5)
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

private struct BandStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            Stepper("\(value)/5", value: $value, in: 1...5)
        }
    }
}
