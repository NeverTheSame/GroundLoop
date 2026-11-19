import Foundation
import UserNotifications
import GroundLoop

/// Sends a macOS notification when a metric's quota window rolls over —
/// i.e. the `resetsAt` timestamp we last observed has passed and the
/// provider now reports a fresh window. We persist the last-seen resetsAt
/// per (account, metric), so each reset triggers exactly one notification.
@MainActor
final class QuotaResetNotifier {
    static let shared = QuotaResetNotifier()

    private lazy var center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false
    private let seenKeyPrefix = "quotaResetSeen."

    /// Ask for permission once. Safe to call repeatedly.
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Evaluate the latest usage and fire notifications for any metric whose
    /// quota window just reset. Called from MenuBarViewModel after each
    /// successful refresh.
    func evaluate(usages: [UsageData]) {
        let defaults = UserDefaults.standard
        // Default-on: use object(forKey:) so an unset key means enabled.
        guard defaults.object(forKey: "enableQuotaResetAlerts") as? Bool ?? true else { return }

        let now = Date().timeIntervalSince1970
        requestAuthorizationIfNeeded()

        for usage in usages {
            for metric in usage.metrics {
                guard let resetsAt = metric.period?.resetsAt else { continue }
                let key = seenKey(for: usage.account, metric: metric)
                let current = String(Int(resetsAt.timeIntervalSince1970))

                if let previous = defaults.string(forKey: key),
                   previous != current,
                   let previousTS = TimeInterval(previous),
                   previousTS < now {
                    // The window we last observed has elapsed and the
                    // provider moved on — the quota just reset.
                    schedule(for: usage.account, metric: metric, resetsAt: resetsAt)
                }
                defaults.set(current, forKey: key)
            }
        }

        pruneOldKeys(now: now)
    }

    private func schedule(for account: LLMAccount, metric: UsageMetric, resetsAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = "\(account.service.displayName) quota reset"
        content.body = "\(metric.label) is back — now at \(Int(metric.usedPercent.rounded()))% used."
        if metric.usedPercent > 0 {
            content.body += " Resets again in \(countdown(to: resetsAt))."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "groundloop.quotaReset.\(account.id.uuidString).\(metric.label)",
            content: content,
            trigger: nil   // deliver immediately
        )
        center.add(request, withCompletionHandler: nil)
    }

    private func seenKey(for account: LLMAccount, metric: UsageMetric) -> String {
        "\(seenKeyPrefix)\(account.id.uuidString).\(metric.label)"
    }

    /// Remove observed-reset markers older than 35 days (longer than any
    /// weekly window) so the UserDefaults set does not grow forever.
    private func pruneOldKeys(now: TimeInterval) {
        let defaults = UserDefaults.standard
        let cutoff = now - 35 * 24 * 60 * 60
        for (key, value) in defaults.dictionaryRepresentation()
            where key.hasPrefix(seenKeyPrefix) {
            if let stringValue = value as? String,
               let ts = TimeInterval(stringValue),
               ts < cutoff {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func countdown(to date: Date) -> String {
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}
