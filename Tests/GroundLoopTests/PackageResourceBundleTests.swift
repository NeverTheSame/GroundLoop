import Foundation
import Testing
@testable import GroundLoop

@Test func findsResourceBundleInsideAppContentsResources() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("gl-bundle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let app = tmp.appendingPathComponent("GroundLoop.app", isDirectory: true)
    let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
    let logos = resources
        .appendingPathComponent("GroundLoop_groundloop-menubar.bundle/ServiceLogos", isDirectory: true)
    try FileManager.default.createDirectory(at: logos, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("<svg/>".utf8).write(to: logos.appendingPathComponent("claude.svg"))
    try Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.groundloop.test</string>
        <key>CFBundleExecutable</key><string>groundloop-menubar</string>
        <key>CFBundlePackageType</key><string>APPL</string>
    </dict></plist>
    """.utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

    let main = try #require(Bundle(url: app))
    let executablePath = app.appendingPathComponent("Contents/MacOS/groundloop-menubar").path

    // SwiftPM's generated Bundle.module only looks next to the .app — that
    // path is empty in a real install, which is what crashed GroundLoop.
    let swiftPMPath = main.bundleURL.appendingPathComponent("GroundLoop_groundloop-menubar.bundle")
    #expect(FileManager.default.fileExists(atPath: swiftPMPath.path) == false)

    let candidates = PackageResourceBundle.candidateURLs(
        named: "GroundLoop_groundloop-menubar",
        mainBundle: main,
        executablePath: executablePath
    )
    #expect(candidates.contains { $0.path.contains("Contents/Resources") })

    let url = PackageResourceBundle.url(
        named: "GroundLoop_groundloop-menubar",
        forResource: "claude",
        withExtension: "svg",
        subdirectory: "ServiceLogos",
        mainBundle: main,
        executablePath: executablePath
    )
    #expect(url?.lastPathComponent == "claude.svg")
    #expect(url?.path.contains("Contents/Resources") == true)
}

@Test func missingResourceBundleReturnsNilInsteadOfCrashing() {
    let url = PackageResourceBundle.url(
        named: "DefinitelyMissing-\(UUID().uuidString)",
        forResource: "claude",
        withExtension: "svg",
        subdirectory: "ServiceLogos"
    )
    #expect(url == nil)
    #expect(PackageResourceBundle.find(named: "DefinitelyMissing-\(UUID().uuidString)") == nil)
}
