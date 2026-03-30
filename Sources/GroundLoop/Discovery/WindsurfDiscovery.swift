import Foundation

/// Discovers Windsurf tokens from the SQLite state database.
public struct WindsurfDiscovery: TokenDiscoverer {
    public let service = LLMService.windsurf

    private let dbPath = "~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb"

    public init() {}

    public func discover() async throws -> DiscoveryResult? {
        let path = (dbPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        guard let jsonString = queryDB(path: path, key: "windsurfAuthStatus"),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["apiKey"] as? String, !apiKey.isEmpty else {
            return nil
        }

        let token = TokenInfo(
            accessToken: apiKey,
            refreshToken: nil,
            expiresAt: nil,
            source: .discovered
        )

        return DiscoveryResult(service: .windsurf, tokens: [token], source: "sqlite")
    }

    private func queryDB(path: String, key: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [path, "SELECT value FROM ItemTable WHERE key = '\(key.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }
}
