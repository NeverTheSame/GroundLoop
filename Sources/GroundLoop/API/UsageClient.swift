import Foundation

/// Protocol for fetching usage data from LLM services
public protocol UsageClient: Sendable {
    var service: LLMService { get }
    func fetchUsage(account: LLMAccount) async throws -> UsageData
    var settingURL: URL? { get }
    /// Renew an expiring/expired token using its own refresh token, without
    /// re-reading the originating app's keychain item. Returns nil if this
    /// client can't refresh (no refresh token, or the grant was rejected).
    func refreshToken(_ token: TokenInfo) async throws -> TokenInfo?
}

public extension UsageClient {
    func refreshToken(_ token: TokenInfo) async throws -> TokenInfo? { nil }
}

/// Errors from usage API calls
public enum UsageClientError: Error {
    case noToken
    case tokenExpired
    case unauthorized
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    /// The service rate-limited this request (HTTP 429). `retryAfter` is the
    /// server-advised cooldown in seconds, when the response provided one.
    case rateLimited(retryAfter: TimeInterval?)
}
