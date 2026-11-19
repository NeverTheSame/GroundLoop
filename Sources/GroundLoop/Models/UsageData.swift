import Foundation

/// Period for usage metrics
public struct UsagePeriod: Codable, Sendable {
    public let label: String           // "Session", "Weekly", "Monthly"
    public let resetsAt: Date?
    public let durationMs: Int?
    
    public init(label: String, resetsAt: Date? = nil, durationMs: Int? = nil) {
        self.label = label
        self.resetsAt = resetsAt
        self.durationMs = durationMs
    }
}

/// Format for displaying usage values
public enum UsageFormat: Codable, Sendable {
    case percent
    case dollars(used: Double, limit: Double)
    case count(used: Int, limit: Int, suffix: String)
}

/// A single usage metric line
public struct UsageMetric: Codable, Sendable {
    public let label: String
    public let usedPercent: Double     // 0-100
    public let format: UsageFormat
    public let period: UsagePeriod?
    
    public init(
        label: String,
        usedPercent: Double,
        format: UsageFormat,
        period: UsagePeriod? = nil
    ) {
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.format = format
        self.period = period
    }
}

// MARK: - Pace / limit projection

extension UsageMetric {
    private var windowDuration: TimeInterval? {
        guard let ms = period?.durationMs, ms > 0 else { return nil }
        return TimeInterval(ms) / 1000
    }

    /// Start of the current quota window (`resetsAt − duration`).
    public func windowStart() -> Date? {
        guard let resetsAt = period?.resetsAt, let duration = windowDuration else { return nil }
        return resetsAt.addingTimeInterval(-duration)
    }

    /// Fraction of the window that has elapsed (0…1): where usage would sit at an even pace.
    public func paceFraction(now: Date = Date()) -> Double? {
        guard let start = windowStart(), let duration = windowDuration else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }

    /// When the limit will be hit at the window-average rate, or nil if it
    /// will not be hit before the reset (or it is too early to tell).
    public func projectedLimitDate(now: Date = Date()) -> Date? {
        guard let start = windowStart(),
              let duration = windowDuration,
              let resetsAt = period?.resetsAt,
              usedPercent > 0, usedPercent < 100 else { return nil }

        let elapsed = now.timeIntervalSince(start)
        let minElapsed = max(10 * 60, duration * 0.02)
        guard elapsed >= minElapsed, now < resetsAt else { return nil }

        let ratePerSecond = usedPercent / elapsed
        let projected = now.addingTimeInterval((100 - usedPercent) / ratePerSecond)
        return projected < resetsAt ? projected : nil
    }
}

/// Plan information
public struct PlanInfo: Codable, Sendable {
    public let name: String?
    public let tier: String?
    
    public init(name: String? = nil, tier: String? = nil) {
        self.name = name
        self.tier = tier
    }
}

/// Complete usage data for an account
public struct UsageData: Codable, Sendable {
    public let account: LLMAccount
    public let plan: PlanInfo?
    public let metrics: [UsageMetric]
    public let settingURL: URL?
    public let fetchedAt: Date
    
    public init(
        account: LLMAccount,
        plan: PlanInfo? = nil,
        metrics: [UsageMetric],
        settingURL: URL? = nil,
        fetchedAt: Date = Date()
    ) {
        self.account = account
        self.plan = plan
        self.metrics = metrics
        self.settingURL = settingURL
        self.fetchedAt = fetchedAt
    }
}
