#if DEBUG
import Foundation

/// Test-only support for the XCUITest suite. (SRS FR-13, TASKS T6.6)
///
/// The UI-test runner is sandboxed: it cannot create files in the real
/// `~/Applications`, so it cannot plant a fixture app for the app under test
/// to find. The app itself is not sandboxed, so it creates its own throwaway
/// fixture bundle when launched with `MACCLEAN_UI_FIXTURE` set to a path.
///
/// This keeps the end-to-end uninstall test from having to touch a real
/// installed app.
enum UITestFixture {
    /// Environment variable holding the path of the fixture bundle to create.
    static let pathKey = "MACCLEAN_UI_FIXTURE"

    /// Creates a minimal but valid `.app` bundle at `url`.
    static func createAppBundle(at url: URL) {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents")
        try? fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let name = url.deletingPathExtension().lastPathComponent
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.macclean.fixture",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": name,
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0) else { return }
        try? data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }
}
#endif
