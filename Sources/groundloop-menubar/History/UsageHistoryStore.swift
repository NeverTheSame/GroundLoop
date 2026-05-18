import Foundation
import GroundLoop

/// One persisted observation of a single usage metric at a point in time.
public struct HistorySnapshot: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let accountID: UUID
    public let service: LLMService
    public let accountLabel: String
    public let metricLabel: String
    public let usedPercent: Double
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        service: LLMService,
        accountLabel: String,
        metricLabel: String,
        usedPercent: Double,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.service = service
        self.accountLabel = accountLabel
        self.metricLabel = metricLabel
        self.usedPercent = usedPercent
        self.capturedAt = capturedAt
    }
}

/// Persists per-metric usage snapshots locally so the menu bar app can show
/// a 6-month history chart. Throttles writes to at most one snapshot per
/// (account, metric) per hour to keep the file small, and prunes anything
/// older than 180 days on load.
actor UsageHistoryStore {
    static let shared = UsageHistoryStore()

    private let retention: TimeInterval = 60 * 60 * 24 * 180   // 180 days
    private let minSampleInterval: TimeInterval = 5 * 60       // 5 minutes

    private var snapshots: [HistorySnapshot] = []
    private var loaded = false

    private var fileURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("GroundLoop", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder().decode([HistorySnapshot].self, from: data) else {
            snapshots = []
            return
        }
        let cutoff = Date().addingTimeInterval(-retention)
        snapshots = decoded.filter { $0.capturedAt >= cutoff }
    }

    private func persist() {
        guard let data = try? Self.encoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Append snapshots for every metric, but at most once per hour per
    /// (account, metricLabel) pair to keep storage bounded.
    func record(_ usages: [UsageData], accounts: [LLMAccount]) {
        loadIfNeeded()
        let labelByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.label) })
        let now = Date()
        let cutoff = now.addingTimeInterval(-minSampleInterval)

        var changed = false
        for usage in usages {
            let accountID = usage.account.id
            let accountLabel = labelByID[accountID] ?? usage.account.label
            for metric in usage.metrics {
                let recent = snapshots.last { $0.accountID == accountID && $0.metricLabel == metric.label }
                if let recent, recent.capturedAt > cutoff { continue }
                snapshots.append(HistorySnapshot(
                    accountID: accountID,
                    service: usage.account.service,
                    accountLabel: accountLabel,
                    metricLabel: metric.label,
                    usedPercent: metric.usedPercent,
                    capturedAt: usage.fetchedAt
                ))
                changed = true
            }
        }

        // Prune anything beyond retention so the file does not grow unbounded.
        let oldestAllowed = now.addingTimeInterval(-retention)
        let originalCount = snapshots.count
        snapshots.removeAll { $0.capturedAt < oldestAllowed }
        if snapshots.count != originalCount { changed = true }

        if changed { persist() }
    }

    func allSnapshots() -> [HistorySnapshot] {
        loadIfNeeded()
        return snapshots
    }

    func snapshots(forAccount accountID: UUID) -> [HistorySnapshot] {
        loadIfNeeded()
        return snapshots.filter { $0.accountID == accountID }
    }

    func clearAll() {
        snapshots = []
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
