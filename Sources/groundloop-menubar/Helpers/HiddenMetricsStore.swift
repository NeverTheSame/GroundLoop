import Foundation
import Combine

/// Tracks metrics the user has hidden, scoped per (account, metric label).
/// Persisted to UserDefaults so the choice survives relaunches.
@MainActor
final class HiddenMetricsStore: ObservableObject {
    static let shared = HiddenMetricsStore()

    private let defaultsKey = "hiddenMetrics.v1"
    private let hiddenAccountsKey = "hiddenAccounts.v1"
    private let defaults = UserDefaults.standard

    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var hiddenAccounts: Set<String> = []

    private init() {
        if let arr = defaults.array(forKey: defaultsKey) as? [String] {
            hidden = Set(arr)
        }
        if let arr = defaults.array(forKey: hiddenAccountsKey) as? [String] {
            hiddenAccounts = Set(arr)
        }
    }

    private func key(accountID: UUID, metricLabel: String) -> String {
        "\(accountID.uuidString)|\(metricLabel)"
    }

    func isHidden(accountID: UUID, metricLabel: String) -> Bool {
        hidden.contains(key(accountID: accountID, metricLabel: metricLabel))
    }

    func hiddenCount(accountID: UUID) -> Int {
        let prefix = "\(accountID.uuidString)|"
        return hidden.reduce(0) { $0 + ($1.hasPrefix(prefix) ? 1 : 0) }
    }

    func hide(accountID: UUID, metricLabel: String) {
        hidden.insert(key(accountID: accountID, metricLabel: metricLabel))
        persist()
    }

    func unhide(accountID: UUID, metricLabel: String) {
        hidden.remove(key(accountID: accountID, metricLabel: metricLabel))
        persist()
    }

    func unhideAll(accountID: UUID) {
        let prefix = "\(accountID.uuidString)|"
        hidden = hidden.filter { !$0.hasPrefix(prefix) }
        persist()
    }

    private func persist() {
        defaults.set(Array(hidden), forKey: defaultsKey)
    }

    // MARK: - Whole-account hiding

    func isAccountHidden(_ accountID: UUID) -> Bool {
        hiddenAccounts.contains(accountID.uuidString)
    }

    func hideAccount(_ accountID: UUID) {
        hiddenAccounts.insert(accountID.uuidString)
        persistAccounts()
    }

    func unhideAccount(_ accountID: UUID) {
        hiddenAccounts.remove(accountID.uuidString)
        persistAccounts()
    }

    func unhideAllAccounts() {
        hiddenAccounts.removeAll()
        persistAccounts()
    }

    private func persistAccounts() {
        defaults.set(Array(hiddenAccounts), forKey: hiddenAccountsKey)
    }
}
