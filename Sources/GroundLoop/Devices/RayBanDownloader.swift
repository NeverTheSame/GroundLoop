import Foundation

/// Downloads videos from Meta Ray-Ban smart glasses connected via USB.
/// Glasses mount as a standard USB storage device; this scans /Volumes for the device
/// and copies new video files to a local destination folder.
public struct RayBanDownloader: Sendable {

    // Volume name substrings that indicate Ray-Ban glasses (case-insensitive)
    static let knownVolumeKeywords = ["ray-ban", "rayban", "ray_ban"]
    static let videoExtensions: Set<String> = ["mp4", "mov"]

    public init() {}

    /// Returns the mounted Ray-Ban volume URL, or nil if not connected.
    public func findDevice() -> URL? {
        let volumes = URL(fileURLWithPath: "/Volumes")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: volumes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        // Prefer exact name match
        for url in entries {
            let name = url.lastPathComponent.lowercased()
            if Self.knownVolumeKeywords.contains(where: { name.contains($0) }) {
                return url
            }
        }

        // Fallback: any external volume with a DCIM folder (camera convention)
        for url in entries {
            guard url.path != "/" else { continue }
            let dcim = url.appendingPathComponent("DCIM")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }

        return nil
    }

    /// Returns all video files on the device, sorted by name.
    public func findVideos(on device: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: device,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var videos: [URL] = []
        for case let url as URL in enumerator {
            if Self.videoExtensions.contains(url.pathExtension.lowercased()) {
                videos.append(url)
            }
        }
        return videos.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies new videos from glasses to `destination`. Skips files that already exist.
    /// - Parameter onProgress: Called with a status string for each file.
    /// - Returns: A `DownloadResult` with counts of copied and skipped files.
    @discardableResult
    public func download(
        to destination: URL,
        onProgress: @Sendable (String) -> Void = { _ in }
    ) async throws -> DownloadResult {
        guard let device = findDevice() else {
            throw RayBanError.deviceNotFound
        }
        onProgress("Device: \(device.lastPathComponent)")

        let videos = findVideos(on: device)
        guard !videos.isEmpty else {
            throw RayBanError.noVideosFound
        }
        onProgress("Videos found: \(videos.count)")

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var copied = 0
        var skipped = 0

        for video in videos {
            let dest = destination.appendingPathComponent(video.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                skipped += 1
                continue
            }
            try FileManager.default.copyItem(at: video, to: dest)
            copied += 1
            onProgress("  ✅ \(video.lastPathComponent)")
        }

        return DownloadResult(copied: copied, skipped: skipped, destination: destination)
    }
}

public struct DownloadResult: Sendable {
    public let copied: Int
    public let skipped: Int
    public let destination: URL
}

public enum RayBanError: Error, LocalizedError, Sendable {
    case deviceNotFound
    case noVideosFound

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Ray-Ban glasses not found. Connect them via USB and try again."
        case .noVideosFound:
            return "No video files found on the device."
        }
    }
}
