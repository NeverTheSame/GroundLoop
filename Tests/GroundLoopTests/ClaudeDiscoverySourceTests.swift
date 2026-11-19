import Testing
@testable import GroundLoop
import Foundation

private func credentialJSON(accessToken: String, expiresAt: Date) -> String {
    let ms = Int(expiresAt.timeIntervalSince1970 * 1000)
    return #"{"claudeAiOauth":{"accessToken":"\#(accessToken)","refreshToken":"r-\#(accessToken)","expiresAt":\#(ms)}}"#
}

private func writeCredentialFile(_ contents: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent(".credentials.json").path
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

@Test func claudeDiscoveryFallsBackToKeychainWhenFileTokenExpired() async throws {
    // Claude Code on macOS keeps its live session in the Keychain; a leftover
    // .credentials.json can hold a long-expired token.
    let path = try writeCredentialFile(credentialJSON(accessToken: "stale", expiresAt: Date().addingTimeInterval(-3600)))
    let discovery = ClaudeDiscovery(credentialPath: path) { _ in
        credentialJSON(accessToken: "live", expiresAt: Date().addingTimeInterval(3600))
    }

    let result = try #require(try await discovery.discover())
    #expect(result.tokens.first?.accessToken == "live")
    #expect(result.source == "keychain")
}

@Test func claudeDiscoveryPrefersValidFileWithoutTouchingKeychain() async throws {
    let path = try writeCredentialFile(credentialJSON(accessToken: "fresh", expiresAt: Date().addingTimeInterval(3600)))
    let discovery = ClaudeDiscovery(credentialPath: path) { _ in
        Issue.record("Keychain must not be read when the file token is valid")
        return nil
    }

    let result = try #require(try await discovery.discover())
    #expect(result.tokens.first?.accessToken == "fresh")
}

@Test func claudeDiscoveryKeepsExpiredFileWhenKeychainHasNothing() async throws {
    let path = try writeCredentialFile(credentialJSON(accessToken: "stale", expiresAt: Date().addingTimeInterval(-3600)))
    let discovery = ClaudeDiscovery(credentialPath: path) { _ in nil }

    let result = try #require(try await discovery.discover())
    #expect(result.tokens.first?.accessToken == "stale")
}
