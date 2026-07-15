import Foundation

/// Z.AI GLM Coding Plan usage API client.
///
/// Endpoints (derived from the official zai-coding-plugins source):
///   - quota/limit  → 5-hour token usage %, monthly MCP usage
///   - model-usage  → per-model call breakdown (with time range)
///   - tool-usage   → MCP tool call breakdown (with time range)
public struct GLMClient: UsageClient {
    public let service = LLMService.glm

    private static let zaiBase = "https://api.z.ai"
    private static let zhipuBase = "https://open.bigmodel.cn"

    public var settingURL: URL? = URL(string: "https://z.ai/manage-apikey/subscription")

    public init() {}

    public func fetchUsage(account: LLMAccount) async throws -> UsageData {
        guard let token = account.primaryToken else {
            throw UsageClientError.noToken
        }

        let baseURL = resolveBaseURL(for: account)

        let quotaData = try await fetchQuotaLimit(baseURL: baseURL, token: token.accessToken)
        let metrics = parseQuota(quotaData)

        let plan = parsePlan(quotaData)

        return UsageData(account: account, plan: plan, metrics: metrics, settingURL: settingURL)
    }

    // MARK: - API Calls

    private func fetchQuotaLimit(baseURL: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/monitor/usage/quota/limit") else {
            throw UsageClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

    // MARK: - Parsing

    private func parseQuota(_ json: [String: Any]) -> [UsageMetric] {
        guard let payload = json["data"] as? [String: Any],
              let limits = payload["limits"] as? [[String: Any]] else {
            return []
        }

        var metrics: [UsageMetric] = []

        for limit in limits {
            guard let type = limit["type"] as? String,
                  let percentage = limit["percentage"] as? Double else {
                continue
            }

            let resetsAt = parseResetTime(limit["nextResetTime"])

            switch type {
            case "TOKENS_LIMIT":
                let durationHours = limit["number"] as? Int ?? 5
                let usedTokens = limit["currentValue"] as? Int
                let tokenCap = limit["usage"] as? Int
                let format: UsageFormat
                if let used = usedTokens, let cap = tokenCap, cap > 0 {
                    format = .count(used: used, limit: cap, suffix: "tokens")
                } else {
                    format = .percent
                }
                metrics.append(UsageMetric(
                    label: "Session",
                    usedPercent: percentage,
                    format: format,
                    period: UsagePeriod(
                        label: "\(durationHours) hours",
                        resetsAt: resetsAt,
                        durationMs: durationHours * 60 * 60 * 1000
                    )
                ))

            case "TIME_LIMIT":
                let currentValue = limit["currentValue"] as? Int
                let total = limit["usage"] as? Int
                let format: UsageFormat
                if let used = currentValue, let cap = total, cap > 0 {
                    format = .count(used: used, limit: cap, suffix: "calls")
                } else {
                    format = .percent
                }

                metrics.append(UsageMetric(
                    label: "MCP",
                    usedPercent: percentage,
                    format: format,
                    period: UsagePeriod(
                        label: "Monthly",
                        resetsAt: resetsAt,
                        durationMs: 30 * 24 * 60 * 60 * 1000
                    )
                ))

            case "WEEKLY_LIMIT":
                metrics.append(UsageMetric(
                    label: "Weekly",
                    usedPercent: percentage,
                    format: .percent,
                    period: UsagePeriod(
                        label: "7 days",
                        resetsAt: resetsAt,
                        durationMs: 7 * 24 * 60 * 60 * 1000
                    )
                ))

            default:
                metrics.append(UsageMetric(
                    label: type,
                    usedPercent: percentage,
                    format: .percent,
                    period: nil
                ))
            }
        }

        // The API returns `limits` in whatever order it feels like, which
        // puts "Session" (the metric users actually watch) behind longer,
        // less urgent quotas like the monthly MCP call budget. Claude and
        // Codex always report Session first; match that here too.
        let session = metrics.filter { $0.label == "Session" }
        let rest = metrics.filter { $0.label != "Session" }
        return session + rest
    }

    private func parsePlan(_ json: [String: Any]) -> PlanInfo? {
        guard let payload = json["data"] as? [String: Any] else { return nil }

        if let level = payload["level"] as? String {
            return PlanInfo(name: "GLM \(level.capitalized)")
        }
        if let planName = payload["planName"] as? String {
            return PlanInfo(name: "GLM \(planName)")
        }
        return PlanInfo(name: "GLM Coding Plan")
    }

    private func parseResetTime(_ value: Any?) -> Date? {
        guard let ms = value as? Double else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    // MARK: - Helpers

    /// The account label set during discovery tells us which platform to target.
    private func resolveBaseURL(for account: LLMAccount) -> String {
        switch account.label.lowercased() {
        case "zhipu":
            return Self.zhipuBase
        default:
            return Self.zaiBase
        }
    }
}
