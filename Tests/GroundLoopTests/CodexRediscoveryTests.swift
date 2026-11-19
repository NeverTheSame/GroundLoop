import XCTest
@testable import GroundLoop

final class CodexRediscoveryTests: XCTestCase {
    func testRejectedCodexTokenIsRediscoveredAndRetried() async throws {
        let storage = MockStorage()
        let usage = GroundLoop(storage: storage)
        try await usage.setup()

        let account = LLMAccount(
            service: .codex,
            label: "Default",
            tokens: [TokenInfo(accessToken: "stale-token", source: .discovered)]
        )
        try await usage.saveAccount(account)
        await usage.registerDiscoverer(
            FixedCodexDiscoverer(replacementToken: "current-token")
        )

        let client = CodexRetryClient()
        await usage.registerClient(client, for: .codex)

        let result = try await usage.fetchUsage(account: account)
        let attempts = await client.callCount()

        XCTAssertEqual(result.account.primaryToken?.accessToken, "current-token")
        XCTAssertEqual(result.account.tokens.count, 1)
        XCTAssertEqual(attempts, 2)
    }
}

private struct FixedCodexDiscoverer: TokenDiscoverer {
    let service = LLMService.codex
    let replacementToken: String

    func discover() async throws -> DiscoveryResult? {
        DiscoveryResult(
            service: .codex,
            tokens: [TokenInfo(accessToken: replacementToken, source: .discovered)],
            source: "test"
        )
    }
}

private actor CodexRetryClient: UsageClient {
    let service = LLMService.codex
    let settingURL: URL? = nil
    private var attempts = 0

    func fetchUsage(account: LLMAccount) async throws -> UsageData {
        attempts += 1
        guard account.primaryToken?.accessToken == "current-token" else {
            throw UsageClientError.tokenExpired
        }
        return UsageData(account: account, metrics: [])
    }

    func callCount() -> Int { attempts }
}
