import Foundation

/// Discovers Cursor tokens from the SQLite state database.
///
/// Uses the `sqlite3` CLI tool to avoid WAL-mode locking issues that occur when
/// opening the database via the C API while Cursor is running.
public struct CursorDiscovery: TokenDiscoverer {
    public let service = LLMService.cursor

    private let dbPath = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    public init() {}

    public func discover() async throws -> DiscoveryResult? {
        let path = (dbPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        guard let accessToken = queryDB(path: path, key: "cursorAuth/accessToken"),
              !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = queryDB(path: path, key: "cursorAuth/refreshToken")
        let email = queryDB(path: path, key: "cursorAuth/cachedEmail")
        let expiresAt = decodeJWTExpiration(accessToken)

        let token = TokenInfo(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            source: .discovered
        )

        return DiscoveryResult(service: .cursor, tokens: [token], source: "sqlite", label: email)
    }

    /// Shell out to `sqlite3` which handles WAL-mode databases correctly even while Cursor is running.
    private func queryDB(path: String, key: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [path, "SELECT value FROM ItemTable WHERE key = '\(sanitize(key))' LIMIT 1;"]

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

    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "'", with: "''")
    }

    private func decodeJWTExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }
}
