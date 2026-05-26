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
                LabeledContent("GPA / 均分") {
                    Stepper("\(Int(profile.gpaPercent))", value: $profile.gpaPercent, in: 60...100, step: 1)
                }
                LabeledContent("年级排名百分位") {
                    Stepper("前 \(Int(profile.classRankPercentile))%", value: $profile.classRankPercentile, in: 1...80, step: 1)
                }
                Picker("课程体系", selection: $profile.curriculum) {
                    ForEach(CurriculumType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
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
