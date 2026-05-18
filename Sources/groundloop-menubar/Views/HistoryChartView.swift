import SwiftUI
import Charts
import GroundLoop

/// 6-month usage history sheet for one account. Pulls snapshots from
/// UsageHistoryStore and draws one line per metric using Swift Charts.
struct HistoryChartView: View {
    let account: LLMAccount
    var onClose: () -> Void

    @State private var snapshots: [HistorySnapshot] = []
    @State private var range: HistoryRange = .month

    enum HistoryRange: String, CaseIterable, Identifiable {
        case week = "1W"
        case month = "1M"
        case quarter = "3M"
        case sixMonths = "6M"

        var id: String { rawValue }

        var interval: TimeInterval {
            switch self {
            case .week: return 60 * 60 * 24 * 7
            case .month: return 60 * 60 * 24 * 30
            case .quarter: return 60 * 60 * 24 * 90
            case .sixMonths: return 60 * 60 * 24 * 180
            }
        }
    }

    private var filtered: [HistorySnapshot] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        return snapshots
            .filter { $0.capturedAt >= cutoff }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(account.service.displayName) history")
                        .font(.headline)
                    Text(account.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No history yet")
                        .font(.subheadline)
                    Text("History is recorded as you use the app. Come back after a few refreshes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                Chart(filtered) { point in
                    LineMark(
                        x: .value("Date", point.capturedAt),
                        y: .value("Used %", point.usedPercent)
                    )
                    .foregroundStyle(by: .value("Metric", point.metricLabel))
                    .interpolationMethod(.monotone)

                    AreaMark(
                        x: .value("Date", point.capturedAt),
                        y: .value("Used %", point.usedPercent)
                    )
                    .foregroundStyle(by: .value("Metric", point.metricLabel))
                    .opacity(0.12)
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)%") }
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .frame(height: 220)
            }
        }
        .padding(16)
        .frame(width: 460)
        .task(id: account.id) {
            snapshots = await UsageHistoryStore.shared.snapshots(forAccount: account.id)
        }
    }
}
