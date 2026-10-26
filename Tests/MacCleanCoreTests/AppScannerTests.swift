import XCTest
@testable import MacCleanCore

final class AppScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if tempDir != nil {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    private func makeFixtureApp(name: String, bundleID: String, sizeKB: Int = 10) throws -> URL {
        let appURL = tempDir.appendingPathComponent("\(name).app")
        let contentsDir = appURL.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let binary = contentsDir.appendingPathComponent(name)
        try Data(repeating: 0xAB, count: sizeKB * 1024).write(to: binary)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleExecutable": name,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist, format: .binary, options: 0
        )
        try plistData.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        return appURL
    }

    func testScanLocationFindsAppBundles() async throws {
        _ = try makeFixtureApp(name: "TestApp", bundleID: "com.example.testapp")
        _ = try makeFixtureApp(name: "OtherApp", bundleID: "com.example.other")

        let scanner = AppScanner()
        let apps = scanner.scanLocation(tempDir)

        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(Set(apps.map(\.name)), ["TestApp", "OtherApp"])
    }

    func testScannedAppHasMetadata() async throws {
        _ = try makeFixtureApp(name: "TestApp", bundleID: "com.example.testapp")

        let app = try XCTUnwrap(AppScanner().scanLocation(tempDir).first)
        XCTAssertEqual(app.bundleID, "com.example.testapp")
        XCTAssertEqual(app.version, "1.2.3")
        XCTAssertGreaterThan(app.sizeBytes, 0)
    }

    func testScanIgnoresNonAppBundleEntries() async throws {
        _ = try makeFixtureApp(name: "TestApp", bundleID: "com.example.testapp")
        try "plain file".write(to: tempDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("NotAnApp"), withIntermediateDirectories: true)

        let apps = AppScanner().scanLocation(tempDir)
        XCTAssertEqual(apps.count, 1)
    }

    func testFullScanSortsByName() async throws {
        _ = try makeFixtureApp(name: "Zeta", bundleID: "com.example.zeta")
        _ = try makeFixtureApp(name: "alpha", bundleID: "com.example.alpha")

        let apps = await AppScanner().scan(locations: [tempDir])
        XCTAssertEqual(apps.map(\.name), ["alpha", "Zeta"])
    }
}