import SwiftUI

struct CollegePickerView: View {
    @Binding var selectedCollegeIDs: Set<String>
    private let colleges = AdmissionsSeedData.colleges

    var body: some View {
        List {
            ForEach(colleges) { college in
                Button {
                    toggle(college.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(college.name)
                                .font(.headline)
                            Text("#\(college.rank) · \(college.tierName) · 最新录取率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedCollegeIDs.contains(college.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedCollegeIDs.contains(college.id) ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("目标学校")
        .toolbar {
            Button("全清") {
                selectedCollegeIDs.removeAll()
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedCollegeIDs.contains(id) {
            selectedCollegeIDs.remove(id)
        } else {
            selectedCollegeIDs.insert(id)
        }
    }
}
