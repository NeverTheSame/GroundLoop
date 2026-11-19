import Foundation

/// Discovers Claude tokens from credential file or keychain
public struct ClaudeDiscovery: TokenDiscoverer {
    public let service = LLMService.claude
    
    private let credentialPath: String
    private let keychainService = "Claude Code-credentials"
    private let readKeychain: @Sendable (String) -> String?
    
    public init() {
        self.init(credentialPath: "~/.claude/.credentials.json") {
            KeychainStorage.readGenericPassword(service: $0)
        }
    }

    internal init(credentialPath: String, readKeychain: @escaping @Sendable (String) -> String?) {
        self.credentialPath = credentialPath
        self.readKeychain = readKeychain
    }
    
    public func discover() async throws -> DiscoveryResult? {
        // Try credential file first
        let fileResult = try? discoverFromFile()
        if let fileResult, fileResult.tokens.first?.isExpired != true {
            return fileResult
        }
        
        // Fallback to keychain. On macOS Claude Code keeps its live session
        // there, so a leftover credentials file can hold a long-expired token.
        return discoverFromKeychain() ?? fileResult
    }
    
    private func discoverFromFile() throws -> DiscoveryResult? {
        let path = (credentialPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
            return nil
        }
        
        let refreshToken = oauth["refreshToken"] as? String
        let expiresAt: Date? = {
            guard let ms = oauth["expiresAt"] as? Double else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }()
        
        let token = TokenInfo(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            source: .discovered
        )
        
        return DiscoveryResult(service: .claude, tokens: [token], source: "file")
    }
    
    private func discoverFromKeychain() -> DiscoveryResult? {
        guard let raw = readKeychain(keychainService) else {
            return nil
        }
        
        // May be hex-encoded UTF-8
        let jsonString = decodeHexIfNeeded(raw)
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
            return nil
        }
        
        let refreshToken = oauth["refreshToken"] as? String
        let expiresAt: Date? = {
            guard let ms = oauth["expiresAt"] as? Double else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }()
        
        let token = TokenInfo(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            source: .discovered
        )
        
        return DiscoveryResult(service: .claude, tokens: [token], source: "keychain")
    }
    
    /// Decode hex-encoded UTF-8 (macOS keychain sometimes returns this)
    private func decodeHexIfNeeded(_ input: String) -> String {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex = String(hex.dropFirst(2))
        }
        
        guard hex.count % 2 == 0,
              hex.allSatisfy({ $0.isHexDigit }) else {
            return input
        }
        
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        
        return String(decoding: bytes, as: UTF8.self)
    }
}
