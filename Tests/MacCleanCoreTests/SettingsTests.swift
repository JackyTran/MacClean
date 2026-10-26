import XCTest
@testable import MacCleanCore

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "macclean-settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsRoundTrip() {
        var settings = AppSettings()
        settings.secureDeleteEnabled = true
        settings.disabledLocationPaths = ["/Library/Logs"]
        settings.customScanFolders = ["/Users/admin/Extra"]
        settings.logRetentionDays = 7
        SettingsStore.save(settings, defaults: defaults)

        let loaded = SettingsStore.load(defaults: defaults)
        XCTAssertEqual(loaded, settings)
    }

    func testLoadReturnsDefaultsWhenEmpty() {
        XCTAssertEqual(SettingsStore.load(defaults: defaults), AppSettings())
    }

    func testLoadWithGarbageFallsBackToDefaults() throws {
        defaults.set(Data("not json".utf8), forKey: "com.macclean.settings.v1")
        XCTAssertEqual(SettingsStore.load(defaults: defaults), AppSettings())
    }

    func testScanLocationsRespectDisabledAndCustom() {
        var settings = AppSettings()
        let disabled = "/Library/Logs"
        settings.disabledLocationPaths = [disabled]
        settings.customScanFolders = ["/Users/admin/ExtraScan"]

        let locations = settings.scanLocations(home: "/Users/admin")

        XCTAssertFalse(locations.contains { $0.url.path == disabled }, "disabled location must be excluded")
        XCTAssertTrue(locations.contains { $0.url.path == "/Users/admin/ExtraScan" }, "custom folder must be included")
        XCTAssertTrue(locations.contains { $0.url.path.hasSuffix("/Library/Caches") }, "default user locations still present")
        XCTAssertFalse(locations.contains { $0.requiresRoot == false && $0.url.path == "/Library/Logs" })
    }

    func testPurgeOldLogsRemovesOnlyOldOnes() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "macclean-purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func makeRecord(named name: String, date: Date) -> UninstallRecord {
            let app = InstalledApp(
                name: name, version: "1.0", bundleID: "com.\(name.lowercased())",
                path: URL(fileURLWithPath: "/Applications/\(name).app"),
                sizeBytes: 10, lastModifiedDate: nil, isAppleProtected: false)
            return UninstallRecord(app: app, date: date, mode: "trash", items: [])
        }

        var settings = AppSettings()
        settings.logRetentionDays = 7
        // Write a record dated 30 days ago (old) and one dated now (fresh).
        let oldDate = Date().addingTimeInterval(-30 * 86_400)
        try UninstallLogger.write(makeRecord(named: "OldApp", date: oldDate), to: dir)
        try UninstallLogger.write(makeRecord(named: "NewApp", date: Date()), to: dir)

        let removed = SettingsStore.purgeOldLogs(settings, in: dir)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(UninstallLogger.recentLogs(limit: .max, in: dir).count, 1, "only the fresh log should remain")
    }

    func testPurgeKeepsAllWhenRetentionZero() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory() + "macclean-purge-keep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var settings = AppSettings()
        settings.logRetentionDays = 0
        let app = InstalledApp(
            name: "A", version: "1.0", bundleID: "com.a",
            path: URL(fileURLWithPath: "/x"), sizeBytes: 0, lastModifiedDate: nil, isAppleProtected: false)
        let record = UninstallRecord(app: app, date: Date().addingTimeInterval(-365 * 86_400), mode: "trash", items: [])
        try UninstallLogger.write(record, to: dir)

        XCTAssertEqual(SettingsStore.purgeOldLogs(settings, in: dir), 0)
        XCTAssertEqual(UninstallLogger.recentLogs(limit: .max, in: dir).count, 1)
    }
}