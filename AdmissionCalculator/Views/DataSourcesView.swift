import SwiftUI

struct DataSourcesView: View {
    var body: some View {
        List {
            Section("数据快照") {
                LabeledContent("版本", value: AdmissionsSeedData.dataVersion)
                LabeledContent("生成日期", value: AdmissionsSeedData.generatedAt)
                LabeledContent("学校数量", value: "\(AdmissionsSeedData.colleges.count)")
            }

            Section("固定数据源") {
                ForEach(AdmissionsSeedData.sourceRecords) { source in
                    SourceRow(source: source)
                }
            }

            Section("学校统计") {
                ForEach(AdmissionsSeedData.colleges) { college in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(college.name)
                            .font(.headline)
                        Text("#\(college.rank) · \(college.tierName) · \(college.latestAvailableClassYear) 届 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: DataSourceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.headline)
            Text(source.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(source.refreshMode) · confidence: \(source.confidence)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(source.url.absoluteString, destination: source.url)
                .font(.caption2)
        }
    }
}
