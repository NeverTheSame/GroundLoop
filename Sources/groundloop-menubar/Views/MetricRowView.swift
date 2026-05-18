import SwiftUI
import GroundLoop

struct MetricRowView: View {
    let metric: UsageMetric
    var onHide: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(metric.label).font(.caption)
                Spacer()
                Text(formattedValue).font(.caption).foregroundColor(.secondary)
                if let onHide {
                    Button(action: onHide) {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide this metric")
                    .opacity(isHovering ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(
                            width: geo.size.width * min(metric.usedPercent / 100, 1.0),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            if let resetsAt = metric.period?.resetsAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(resetCountdown(from: context.date, to: resetsAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func resetCountdown(from now: Date, to resetsAt: Date) -> String {
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 {
            return "Resets now"
        }

        let totalMinutes = Int(interval / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        let parts: String
        if days > 0 {
            parts = "\(days)d \(hours)h"
        } else if hours > 0 {
            parts = "\(hours)h \(minutes)m"
        } else {
            parts = "\(max(minutes, 1))m"
        }
        return "Resets in \(parts)"
    }

    private var formattedValue: String {
        switch metric.format {
        case .percent:
            String(format: "%.0f%%", metric.usedPercent)
        case .dollars(let used, let limit):
            String(format: "$%.2f / $%.2f", used, limit)
        case .count(let used, let limit, let suffix):
            "\(used)/\(limit) \(suffix)"
        }
    }

    private var barColor: Color {
        if metric.usedPercent >= 90 { return .red }
        if metric.usedPercent >= 75 { return .orange }
        return .green
    }
}
