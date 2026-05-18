import Foundation

/// OpenRouter usage API client.
///
/// Uses the public credits endpoint to read total credits and total usage
/// for the authenticated key. There is no per-period reset, so we expose
/// a single "Spend" metric whose percentage is `usage / total_credits`.
public struct OpenRouterClient: UsageClient {
    public let service = LLMService.openrouter

    private let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private let keyURL = URL(string: "https://openrouter.ai/api/v1/auth/key")!
    public var settingURL: URL? = URL(string: "https://openrouter.ai/activity")

    public init() {}

    public func fetchUsage(account: LLMAccount) async throws -> UsageData {
        guard let token = account.primaryToken, !token.accessToken.isEmpty else {
            throw UsageClientError.noToken
        }

        // /credits → { data: { total_credits, total_usage } } (in dollars)
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
            // Pay-as-you-go account: no preset cap, just show absolute spend.
            metrics.append(UsageMetric(
                label: "Spend",
                usedPercent: 0,
                format: .dollars(used: totalUsage, limit: 0),
                period: nil
            ))
        }

        // /auth/key adds rate-limit info and (sometimes) a configured limit.
        var planInfo: PlanInfo? = nil
        if let keyResp = try? await get(url: keyURL, token: token.accessToken),
           let keyData = keyResp["data"] as? [String: Any] {
            if let limit = keyData["limit"] as? Double,
               let usage = keyData["usage"] as? Double,
               limit > 0 {
                let pct = (usage / limit) * 100
                metrics.append(UsageMetric(
                    label: "Key limit",
                    usedPercent: pct,
                    format: .dollars(used: usage, limit: limit),
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
