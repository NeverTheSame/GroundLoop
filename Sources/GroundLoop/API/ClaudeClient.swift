import Foundation

/// Claude usage API client
public struct ClaudeClient: UsageClient {
    public let service = LLMService.claude
    
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
    public var settingURL: URL? = URL(string: "https://claude.ai/settings/usage")
    
    
    public init() {}
    
    public func fetchUsage(account: LLMAccount) async throws -> UsageData {
        guard let token = account.primaryToken else {
            throw UsageClientError.noToken
        }
        
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("GroundLoop", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw UsageClientError.tokenExpired
        }

        if httpResponse.statusCode == 429 {
            throw UsageClientError.rateLimited(retryAfter: retryAfterSeconds(from: httpResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UsageClientError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        return parseUsage(json: json, account: account)
    }
    
    private func parseUsage(json: [String: Any], account: LLMAccount) -> UsageData {
        var metrics: [UsageMetric] = []
        
        // Session (5 hour)
        if let fiveHour = json["five_hour"] as? [String: Any],
           let utilization = fiveHour["utilization"] as? Double {
            let resetsAt = parseDate(fiveHour["resets_at"])
            metrics.append(UsageMetric(
                label: "Session",
                usedPercent: utilization,
                format: .percent,
                period: UsagePeriod(label: "5 hours", resetsAt: resetsAt, durationMs: 5 * 60 * 60 * 1000)
            ))
        }
        
        // Weekly (7 day)
        if let sevenDay = json["seven_day"] as? [String: Any],
           let utilization = sevenDay["utilization"] as? Double {
            let resetsAt = parseDate(sevenDay["resets_at"])
            metrics.append(UsageMetric(
                label: "Weekly",
                usedPercent: utilization,
                format: .percent,
                period: UsagePeriod(label: "7 days", resetsAt: resetsAt, durationMs: 7 * 24 * 60 * 60 * 1000)
            ))
        }
        
        // Per-model weekly quotas (e.g. "Fable") aren't in fixed-name fields
        // like `seven_day_sonnet` — those are always null. The API reports
        // them through the generic `limits` array as `weekly_scoped` entries.
        if let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                guard limit["kind"] as? String == "weekly_scoped",
                      let percent = limit["percent"] as? Double,
                      let scope = limit["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any],
                      let displayName = model["display_name"] as? String else {
                    continue
                }
                let resetsAt = parseDate(limit["resets_at"])
                metrics.append(UsageMetric(
                    label: displayName,
                    usedPercent: percent,
                    format: .percent,
                    period: UsagePeriod(label: "7 days", resetsAt: resetsAt, durationMs: 7 * 24 * 60 * 60 * 1000)
                ))
            }
        }

        return UsageData(account: account, plan: nil, metrics: metrics, settingURL: settingURL)
    }

    /// Parses the `Retry-After` header (either delta-seconds or an HTTP-date,
    /// per RFC 9110 §10.2.3) into a cooldown duration from now.
    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }

        if let seconds = TimeInterval(value) { return seconds }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        // Anthropic returns timestamps both with and without fractional seconds
        // (e.g. "2025-05-18T03:00:00Z" and "2025-05-18T03:00:00.123456Z").
        // The default ISO8601DateFormatter rejects fractional seconds, so try
        // both option sets before giving up.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: str) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: str)
    }
    
    /// Refresh an expired token
    public func refreshToken(_ token: TokenInfo) async throws -> TokenInfo? {
        guard let refreshToken = token.refreshToken else { return nil }
        
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            return nil
        }
        
        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = json["expires_in"] as? Double
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
        
        return TokenInfo(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            source: token.source
        )
    }
}
