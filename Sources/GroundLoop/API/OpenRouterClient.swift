import Foundation

/// OpenRouter usage API client.
///
/// Uses the public credits endpoint to read total credits and total usage
/// for the authenticated key. There is no per-period reset, so we expose
/// a single "Spend" metric whose percentage is `usage / total_credits`.
public struct OpenRouterClient: UsageClient {
    public let service = LLMService.openrouter

    private let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!
    public var settingURL: URL? = URL(string: "https://openrouter.ai/activity")

    public init() {}

    public func fetchUsage(account: LLMAccount) async throws -> UsageData {
        guard let token = account.primaryToken, !token.accessToken.isEmpty else {
            throw UsageClientError.noToken
        }

        // /credits → { data: { total_credits, total_usage } }   (account-wide, dollars)
        let credits = try await get(url: creditsURL, token: token.accessToken)
        let creditsData = credits["data"] as? [String: Any] ?? [:]
        let totalCredits = creditsData["total_credits"] as? Double ?? 0
        let totalUsage = creditsData["total_usage"] as? Double ?? 0

        var metrics: [UsageMetric] = []

        if totalCredits > 0 {
            let pct = (totalUsage / totalCredits) * 100
            metrics.append(UsageMetric(
                label: "Credits",
                usedPercent: pct,
                format: .dollars(used: totalUsage, limit: totalCredits),
                period: nil
            ))
        } else {
            // Pay-as-you-go: no preset cap, expose absolute account-wide spend.
            metrics.append(UsageMetric(
                label: "Total spend",
                usedPercent: 0,
                format: .dollars(used: totalUsage, limit: 0),
                period: nil
            ))
        }

        // /key gives per-key time-windowed usage + optional key limit.
        var planInfo: PlanInfo? = nil
        if let keyResp = try? await get(url: keyURL, token: token.accessToken),
           let keyData = keyResp["data"] as? [String: Any] {

            if let monthly = keyData["usage_monthly"] as? Double {
                metrics.append(UsageMetric(
                    label: "This month",
                    usedPercent: 0,
                    format: .dollars(used: monthly, limit: 0),
                    period: nil
                ))
            }
            if let weekly = keyData["usage_weekly"] as? Double {
                metrics.append(UsageMetric(
                    label: "This week",
                    usedPercent: 0,
                    format: .dollars(used: weekly, limit: 0),
                    period: nil
                ))
            }
            if let daily = keyData["usage_daily"] as? Double {
                metrics.append(UsageMetric(
                    label: "Today",
                    usedPercent: 0,
                    format: .dollars(used: daily, limit: 0),
                    period: nil
                ))
            }

            // Per-key configured limit (separate from account credits).
            if let limit = keyData["limit"] as? Double,
               let remaining = keyData["limit_remaining"] as? Double,
               limit > 0 {
                let used = max(0, limit - remaining)
                let pct = (used / limit) * 100
                metrics.append(UsageMetric(
                    label: "Key limit",
                    usedPercent: pct,
                    format: .dollars(used: used, limit: limit),
                    period: nil
                ))
            }

            let isFree = keyData["is_free_tier"] as? Bool ?? false
            planInfo = PlanInfo(name: isFree ? "Free tier" : "Pay as you go", tier: nil)
        }

        return UsageData(account: account, plan: planInfo, metrics: metrics, settingURL: settingURL)
    }

    private func get(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GroundLoop", forHTTPHeaderField: "User-Agent")

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
}
