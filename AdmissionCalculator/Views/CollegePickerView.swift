import SwiftUI

struct CollegePickerView: View {
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    @State private var searchText = ""
    @State private var filter: CollegePickerFilter = .all
    private let colleges = AdmissionsSeedData.colleges

    private var filteredColleges: [College] {
        colleges.filter { college in
            filter.includes(college: college, selectedIDs: selectedCollegeIDs) &&
            college.matchesPickerQuery(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CollegePickerHero(
                    selectedCount: selectedCollegeIDs.count,
                    totalCount: colleges.count,
                    filteredCount: filteredColleges.count
                )

                Picker("筛选", selection: $filter) {
                    ForEach(CollegePickerFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                SelectedPortfolioCard(
                    selectedCount: selectedCollegeIDs.count,
                    selectedColleges: selectedColleges
                )

                VStack(alignment: .leading, spacing: 12) {
                    Label("学校列表", systemImage: "building.columns")
                        .font(.headline)
                        .foregroundStyle(.indigo)
                    Text("仅显示 AdmissionSight National Universities v1 数据集内学校；这里的录取率是学校基础统计，不是个人概率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if filteredColleges.isEmpty {
                        ContentUnavailableView("没有匹配学校", systemImage: "magnifyingglass", description: Text("调整搜索词或筛选范围。"))
                    }

                    ForEach(filteredColleges) { college in
                        CollegeSelectionCard(
                            college: college,
                            isSelected: selectedCollegeIDs.contains(college.id),
                            toggle: { toggle(college.id) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("目标学校")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索学校、排名或分层")
        .toolbar {
            Button {
                selectedCollegeIDs.removeAll()
                selectionSource = .none
            } label: {
                Label("全清", systemImage: "trash")
            }
            .disabled(selectedCollegeIDs.isEmpty)
        }
    }

    private var selectedColleges: [College] {
        colleges.filter { selectedCollegeIDs.contains($0.id) }
    }

    private func toggle(_ id: String) {
        if selectedCollegeIDs.contains(id) {
            selectedCollegeIDs.remove(id)
        } else {
            selectedCollegeIDs.insert(id)
        }
        selectionSource = selectedCollegeIDs.isEmpty ? .none : .manual
    }
}

private enum CollegePickerFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case selected = "已选"
    case top10 = "综大T10"
    case top30 = "综大T30"
    case top50 = "综大T50"

    var id: String { rawValue }

    func includes(college: College, selectedIDs: Set<String>) -> Bool {
        switch self {
        case .all:
            return true
        case .selected:
            return selectedIDs.contains(college.id)
        case .top10:
            return college.rank <= 10
        case .top30:
            return college.rank <= 30
        case .top50:
            return college.rank <= 50
        }
    }
}

private struct CollegePickerHero: View {
    let selectedCount: Int
    let totalCount: Int
    let filteredCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.16, blue: 0.31)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heroColor(index))
                        .frame(width: 20, height: CGFloat(42 + index % 4 * 22))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.58)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("手动选校组合", systemImage: "rectangle.stack.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(selectedCount) 所已选")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("用搜索和分层筛选整理目标学校；计算仍只使用 v1 审核数据集。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    HeroBadge(title: "数据集", value: "\(totalCount)")
                    HeroBadge(title: "当前", value: "\(filteredCount)")
                    HeroBadge(title: "来源", value: "v1")
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 238)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func heroColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue, .green]
        return colors[index % colors.count]
    }
}

private struct HeroBadge: View {
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
        .frame(minWidth: 58, alignment: .leading)
    }
}

private struct SelectedPortfolioCard: View {
    let selectedCount: Int
    let selectedColleges: [College]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("当前组合", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(selectedCount == 0 ? "尚未选择学校" : selectedColleges.prefix(4).map(\.name).joined(separator: "、"))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("手动改动会把组合来源切换为手动选择；自动推荐缺口提示只会出现在自动推荐组合里。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if selectedColleges.count > 4 {
                Text("另有 \(selectedColleges.count - 4) 所已选学校。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CollegeSelectionCard: View {
    let college: College
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("#\(college.rank)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tierColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(tierColor)
                        Text(college.tierDisplayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tierColor)
                    }
                    Text(college.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 12) {
                        MetricPill(title: "基础率", value: college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))), color: .blue)
                        MetricPill(title: "届别", value: "\(college.latestAvailableClassYear)", color: .purple)
                    }
                    Text("数据质量 \(college.dataQuality.formatted(.number.precision(.fractionLength(2)))) · AdmissionSight v1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.green.opacity(0.45) : tierColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var tierColor: Color {
        switch college.rank {
        case ...10:
            return .purple
        case 11...30:
            return .blue
        case 31...50:
            return .teal
        default:
            return .secondary
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }
}
