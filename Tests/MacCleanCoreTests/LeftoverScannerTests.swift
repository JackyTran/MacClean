import XCTest
@testable import MacCleanCore

final class LeftoverMatcherTests: XCTestCase {
    private var home: URL!
    private var locations: [ScanLocation] = []

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MatcherTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        func mk(_ sub: String, kind: LeftoverItem.Kind) -> ScanLocation {
            let url = home.appendingPathComponent(sub)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return ScanLocation(url: url, kind: kind, requiresRoot: false)
        }
        locations = [
            mk("Application Support", kind: .applicationSupport),
            mk("Caches", kind: .cache),
            mk("Preferences", kind: .preference),
            mk("Containers", kind: .container),
        ]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    private func writeFile(_ path: String, size: Int = 128) {
        let url = home.appendingPathComponent(path)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(repeating: 0x1F, count: size).write(to: url)
    }

    private func makeMatcher(bundleID: String = "com.example.myapp",
                            appName: String = "MyApp") -> LeftoverMatcher {
        LeftoverMatcher(query: .init(bundleID: bundleID, appName: appName))
    }

    func testMatchesByBundleID() async {
        writeFile("Caches/com.example.myapp")
        writeFile("Caches/com.example.myapp.plist")   // in Caches but fine to match
        writeFile("Preferences/com.example.myapp.plist")

        let items = await makeMatcher().scan(locations: locations)
        XCTAssertEqual(items.count, 3)
    }

    func testMatchesByAppNameWithSeparators() async {
        // De-spaced name: "Visual Studio Code" → "visualstudiocode"
        let matcher = LeftoverMatcher(query: .init(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code"))
        writeFile("Caches/visualstudiocode")
        writeFile("Caches/Visual Studio Code Helper")
        let items = await matcher.scan(locations: locations)
        XCTAssertEqual(items.count, 2)
    }

    func testNoFalsePositiveOnSimilarName() async {
        writeFile("Caches/myapplication")             // NOT "MyApp" + separator
        writeFile("Caches/com.example.myapplication") // NOT prefix + "."
        writeFile("Caches/com.example")               // vendor of another app
        let items = await makeMatcher().scan(locations: locations)
        XCTAssertEqual(items.count, 0)
    }

    func testVendorFolderNestedMatch() async {
        // vendor = "com.example" for bundle id "com.example.myapp"
        writeFile("Application Support/com.example/myapp/settings.db")
        let items = await makeMatcher().scan(locations: locations)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].url.path.hasSuffix("/Application Support/com.example/myapp"))
    }

    func testSizesAndDefaultSelection() async {
        writeFile("Caches/com.example.myapp", size: 256)
        writeFile("Application Support/com.example.myapp/data.db", size: 512)

        let items = await makeMatcher().scan(locations: locations)
        let cache = items.first { $0.kind == .cache }
        let support = items.first { $0.kind == .applicationSupport }

        XCTAssertEqual(cache?.sizeBytes, 256)
        XCTAssertEqual(support?.sizeBytes, 512)
        // FR-7: caches pre-selected, app support not
        XCTAssertEqual(cache?.isSelected, true)
        XCTAssertEqual(support?.isSelected, false)
    }

    func testScanIsCancellable() async {
        writeFile("Caches/com.example.myapp")
        let task = Task { await makeMatcher().scan(locations: locations) }
        task.cancel()
        // Must not hang or crash; any result (including partial) is acceptable.
        _ = await task.value
    }
}

final class LaunchItemsScannerTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    private func writeAgent(name: String, label: String, program: String) throws {
        let dir = home.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = ["Label": label, "Program": program]
        try (dict as NSDictionary).write(to: dir.appendingPathComponent(name))
    }

    func testDetectsAgentByProgramPathAndLabel() async throws {
        try writeAgent(
            name: "com.helper.updater.plist",
            label: "com.helper.updater",
            program: "/Applications/MyApp.app/Contents/MacOS/updater"
        )
        try writeAgent(
            name: "unrelated.agent.plist",
            label: "com.other.thing",
            program: "/usr/libexec/other"
        )

        let location = ScanLocation(url: home.appendingPathComponent("LaunchAgents"),
                                    kind: .launchAgent, requiresRoot: false)
        let scanner = LaunchItemsScanner(query: .init(bundleID: "com.example.myapp", appName: "MyApp"))
        let items = await scanner.scan(locations: [location])

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.url.lastPathComponent.hasSuffix("com.helper.updater.plist"))
        // FR-7: agents are NOT pre-selected
        XCTAssertEqual(item.isSelected, false)
    }
}

final class OrphanScannerTests: XCTestCase {
    private var home: URL!
    private var location: ScanLocation!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrphanTests-\(UUID().uuidString)")
        let dir = home.appendingPathComponent("Caches")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        location = ScanLocation(url: dir, kind: .cache, requiresRoot: false)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    private func mkdir(_ name: String, size: Int = 64) {
        let dir = location.url.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(repeating: 0x2B, count: size).write(to: dir.appendingPathComponent("f.bin"))
    }

    private let installedApp = InstalledApp(
        name: "MyApp", version: "1.0", bundleID: "com.example.myapp",
        path: URL(fileURLWithPath: "/Applications/MyApp.app"),
        sizeBytes: 1, lastModifiedDate: nil, isAppleProtected: false)

    func testOrphanDetectedWhenAppNotInstalled() async {
        mkdir("com.old.removedapp")
        let orphans = await OrphanScanner().scan(installedApps: [installedApp], locations: [location])
        XCTAssertEqual(orphans.count, 1)
        XCTAssertTrue(orphans[0].url.lastPathComponent.hasPrefix("com.old.removedapp"))
    }

    func testClaimedEntriesAreNotOrphans() async {
        mkdir("com.example.myapp")                 // installed app claims it
        mkdir("com.example.myapp.helper")          // prefix + "." also claimed
        let orphans = await OrphanScanner().scan(installedApps: [installedApp], locations: [location])
        XCTAssertEqual(orphans.count, 0)
    }

    func testAppleAndNonBundleIDEntriesIgnored() async {
        mkdir("com.apple.something")
        mkdir("randomfolder")
        let orphans = await OrphanScanner().scan(installedApps: [], locations: [location])
        XCTAssertEqual(orphans.count, 0)
    }
}