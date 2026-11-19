import Foundation

/// Locates a SwiftPM resource `.bundle` in both `swift run` layouts and
/// packaged macOS `.app`s, without crashing if it is missing.
///
/// SwiftPM's generated `Bundle.module` only checks:
/// 1. `Bundle.main.bundleURL/<name>.bundle` (the `.app` itself, not Resources)
/// 2. A hardcoded `.build/...` path from compile time
///
/// `bundle-menubar.sh` installs the bundle at
/// `GroundLoop.app/Contents/Resources/<name>.bundle`, so `Bundle.module`
/// fatalErrors the first time a service logo is loaded.
public enum PackageResourceBundle {
    public static func candidateURLs(
        named bundleName: String,
        mainBundle: Bundle = .main,
        executablePath: String = CommandLine.arguments[0]
    ) -> [URL] {
        let fileName = bundleName.hasSuffix(".bundle") ? bundleName : "\(bundleName).bundle"
        var urls: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                urls.append(url)
            }
        }

        if let resources = mainBundle.resourceURL {
            add(resources.appendingPathComponent(fileName))
        }
        add(mainBundle.bundleURL.appendingPathComponent(fileName))
        add(
            mainBundle.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(fileName)
        )
        add(
            URL(fileURLWithPath: executablePath)
                .deletingLastPathComponent()
                .appendingPathComponent(fileName)
        )

        return urls
    }

    public static func find(
        named bundleName: String,
        mainBundle: Bundle = .main,
        executablePath: String = CommandLine.arguments[0]
    ) -> Bundle? {
        for url in candidateURLs(
            named: bundleName,
            mainBundle: mainBundle,
            executablePath: executablePath
        ) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    public static func url(
        named bundleName: String,
        forResource resource: String,
        withExtension ext: String,
        subdirectory: String? = nil,
        mainBundle: Bundle = .main,
        executablePath: String = CommandLine.arguments[0]
    ) -> URL? {
        if let bundle = find(
            named: bundleName,
            mainBundle: mainBundle,
            executablePath: executablePath
        ) {
            if let url = bundle.url(
                forResource: resource,
                withExtension: ext,
                subdirectory: subdirectory
            ) {
                return url
            }
        }

        // Bundle(url:) can fail on a folder with no Info.plist; probe files directly.
        for bundleURL in candidateURLs(
            named: bundleName,
            mainBundle: mainBundle,
            executablePath: executablePath
        ) {
            var url = bundleURL
            if let subdirectory {
                url.appendPathComponent(subdirectory)
            }
            url.appendPathComponent("\(resource).\(ext)")
            if FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
