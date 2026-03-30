import Foundation

/// Cursor usage API client (Connect protocol)
public struct CursorClient: UsageClient {
    public let service = LLMService.cursor

    private let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private let planURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
    private let hardLimitURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetHardLimit")!
    public var settingURL: URL? = URL(string: "https://www.cursor.com/settings")

    public init() {}

    public func fetchUsage(account: LLMAccount) async throws -> UsageData {
        guard let token = account.primaryToken else {
            throw UsageClientError.noToken
        }

        let usageData = try await connectPost(url: usageURL, token: token.accessToken)

        guard let enabled = usageData["enabled"] as? Bool, enabled,
              let planUsage = usageData["planUsage"] as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        let planInfo: PlanInfo?
        if let planData = try? await connectPost(url: planURL, token: token.accessToken),
           let pi = planData["planInfo"] as? [String: Any],
           let planName = pi["planName"] as? String {
            let price = pi["price"] as? String
            planInfo = PlanInfo(name: planName, tier: price)
        } else {
            planInfo = nil
        }

        let hardLimit = try? await connectPost(url: hardLimitURL, token: token.accessToken)

        return parseUsage(
            usageData: usageData,
            planUsage: planUsage,
            plan: planInfo,
            hardLimit: hardLimit,
            account: account
        )
    }

    private func connectPost(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw UsageClientError.tokenExpired
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UsageClientError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        return json
    }

    private func parseUsage(
        usageData: [String: Any],
        planUsage: [String: Any],
        plan: PlanInfo?,
        hardLimit: [String: Any]?,
        account: LLMAccount
    ) -> UsageData {
        var metrics: [UsageMetric] = []

        let billingEnd = usageData["billingCycleEnd"] as? String
        let billingStart = usageData["billingCycleStart"] as? String
        let resetsAt = billingEnd.flatMap { parseTimestamp($0) }

        var periodMs = 30 * 24 * 60 * 60 * 1000
        if let start = billingStart.flatMap({ parseTimestamp($0) }),
           let end = resetsAt, end > start {
            periodMs = Int(end.timeIntervalSince(start) * 1000)
        }

        let billingPeriod = UsagePeriod(label: "Billing cycle", resetsAt: resetsAt, durationMs: periodMs)

        // Included plan spend (what counts against your plan allowance)
        let limitCents = planUsage["limit"] as? Double ?? 0
        let includedCents = planUsage["includedSpend"] as? Double ?? 0
        let bonusCents = planUsage["bonusSpend"] as? Double ?? 0
        let totalCents = planUsage["totalSpend"] as? Double ?? (includedCents + bonusCents)

        if limitCents > 0 {
            let includedPercent = (includedCents / limitCents) * 100
            metrics.append(UsageMetric(
                label: "Included",
                usedPercent: includedPercent,
                format: .dollars(used: includedCents / 100, limit: limitCents / 100),
                period: billingPeriod
            ))
        }

        // Bonus spend (free usage from model providers, beyond plan limit)
        if bonusCents > 0 {
            metrics.append(UsageMetric(
                label: "Bonus (free)",
                usedPercent: 0,
                format: .dollars(used: bonusCents / 100, limit: 0),
                period: billingPeriod
            ))
        }

        // API (named model) usage bucket
        if let apiPercent = planUsage["apiPercentUsed"] as? Double {
            metrics.append(UsageMetric(
                label: "API models",
                usedPercent: apiPercent,
                format: .percent,
                period: billingPeriod
            ))
        }

        // Auto-model usage bucket
        if let autoPercent = planUsage["autoPercentUsed"] as? Double {
            metrics.append(UsageMetric(
                label: "Auto models",
                usedPercent: autoPercent,
                format: .percent,
                period: billingPeriod
            ))
        }

        // Overall total capacity %
        if let totalPercent = planUsage["totalPercentUsed"] as? Double {
            metrics.append(UsageMetric(
                label: "Total capacity",
                usedPercent: totalPercent,
                format: .percent,
                period: billingPeriod
            ))
        }

        // Hard limit flag: usage-based billing blocked
        let usageBasedBlocked = hardLimit?["noUsageBasedAllowed"] as? Bool ?? false
        if usageBasedBlocked && limitCents > 0 && totalCents >= limitCents {
            metrics.append(UsageMetric(
                label: "Hard limit",
                usedPercent: 100,
                format: .percent,
                period: nil
            ))
        }

        return UsageData(account: account, plan: plan, metrics: metrics, settingURL: settingURL)
    }

    private func parseTimestamp(_ value: String) -> Date? {
        if let ms = Double(value) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return nil
    }
}
