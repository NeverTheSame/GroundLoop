import Foundation
import UserNotifications
import GroundLoop

/// Sends a single macOS notification per metric whenever its usage crosses
/// the user-configured threshold. We key 'already alerted' state by the
/// metric's resetsAt date so the user gets one notification per quota
/// window — and a fresh one after the quota resets.
@MainActor
final class LowQuotaNotifier {
    static let shared = LowQuotaNotifier()

    private lazy var center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false
    private let alertedKeyPrefix = "lowQuotaAlert."

    /// Ask for permission once. Safe to call repeatedly.
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Evaluate the latest usage and fire notifications for any metric that
    /// just crossed the threshold. Called from MenuBarViewModel after each
    /// successful refresh.
    func evaluate(usages: [UsageData]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "enableLowQuotaAlerts") else { return }

        let threshold = defaults.object(forKey: "lowQuotaThreshold") as? Double ?? 90
        requestAuthorizationIfNeeded()

        for usage in usages {
            for metric in usage.metrics where metric.usedPercent >= threshold {
                let key = alertKey(for: usage.account, metric: metric)
                if defaults.string(forKey: key) == alertValue(for: metric) {
                    continue   // already alerted for this window
                }
                schedule(for: usage.account, metric: metric)
                defaults.set(alertValue(for: metric), forKey: key)
            }
        }

        pruneOldKeys()
    }

    private func schedule(for account: LLMAccount, metric: UsageMetric) {
        let content = UNMutableNotificationContent()
        content.title = "\(account.service.displayName) running low"
        let remaining = max(0, Int((100 - metric.usedPercent).rounded()))
        content.body = "\(metric.label) is at \(Int(metric.usedPercent.rounded()))% — only \(remaining)% remaining."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "groundloop.lowQuota.\(account.id.uuidString).\(metric.label)",
            content: content,
            trigger: nil   // deliver immediately
        )
        center.add(request, withCompletionHandler: nil)
    }

    private func alertKey(for account: LLMAccount, metric: UsageMetric) -> String {
        "\(alertedKeyPrefix)\(account.id.uuidString).\(metric.label)"
    }

    /// We tag the stored value with the metric's reset timestamp (or 'none').
    /// When the metric resets, resetsAt advances and the stored value no
    /// longer matches, so a fresh notification fires.
    private func alertValue(for metric: UsageMetric) -> String {
        if let reset = metric.period?.resetsAt {
            return String(Int(reset.timeIntervalSince1970))
        }
        return "none"
    }

    /// Remove alert markers for any metric whose reset window has elapsed
    /// (i.e. the stored timestamp is in the past) so the UserDefaults set
    /// does not grow forever.
    private func pruneOldKeys() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        for (key, value) in defaults.dictionaryRepresentation()
            where key.hasPrefix(alertedKeyPrefix) {
            if let stringValue = value as? String,
               let ts = TimeInterval(stringValue),
               ts < now {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
