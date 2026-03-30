import Foundation

/// Discovers Z.AI GLM Coding Plan tokens from Claude Code settings
/// or other tool configuration files that store ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL.
public struct GLMDiscovery: TokenDiscoverer {
    public let service = LLMService.glm

    private static let knownBaseURLFragments = ["api.z.ai", "open.bigmodel.cn", "dev.bigmodel.cn"]

    private static let settingsPaths = [
        "~/.claude/settings.json",
        "~/.claude/settings.local.json"
    ]

    public init() {}

    public func discover() async throws -> DiscoveryResult? {
        // Check process environment first (user might export these globally)
        if let result = discoverFromEnvironment() {
            return result
        }

        for path in Self.settingsPaths {
            if let result = try? discoverFromSettingsFile(path) {
                return result
            }
        }

        return nil
    }

    // MARK: - Environment

    private func discoverFromEnvironment() -> DiscoveryResult? {
        let env = ProcessInfo.processInfo.environment
        guard let baseURL = env["ANTHROPIC_BASE_URL"],
              Self.knownBaseURLFragments.contains(where: { baseURL.contains($0) }),
              let authToken = env["ANTHROPIC_AUTH_TOKEN"],
              !authToken.isEmpty else {
            return nil
        }

        let token = TokenInfo(accessToken: authToken, source: .discovered)
        return DiscoveryResult(service: .glm, tokens: [token], source: "env")
    }

    // MARK: - Settings File

    private func discoverFromSettingsFile(_ relativePath: String) throws -> DiscoveryResult? {
        let path = (relativePath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else {
            return nil
        }

        guard let baseURL = env["ANTHROPIC_BASE_URL"] as? String,
              Self.knownBaseURLFragments.contains(where: { baseURL.contains($0) }) else {
            return nil
        }

        guard let authToken = env["ANTHROPIC_AUTH_TOKEN"] as? String,
              !authToken.isEmpty else {
            return nil
        }

        let token = TokenInfo(accessToken: authToken, source: .discovered)
        return DiscoveryResult(service: .glm, tokens: [token], source: "file", label: platformLabel(for: baseURL))
    }

    private func platformLabel(for baseURL: String) -> String? {
        if baseURL.contains("api.z.ai") { return "Z.AI" }
        if baseURL.contains("open.bigmodel.cn") || baseURL.contains("dev.bigmodel.cn") { return "Zhipu" }
        return nil
    }
}
