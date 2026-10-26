import XCTest
@testable import MacCleanCore

final class DeleterTests: XCTestCase {
    private var workDir: URL!
    private var sandboxRoot: String { workDir.path }
    private var sandboxRoot2: String { workDir.path }
    private var fakeTrash: URL!
    private var handlerCalls: [String] = []

    /// Handler that "trashes" files by moving them into a fake Trash dir,
    /// and throws for paths containing "locked" (simulates NFR-10).
    private var deleter: Deleter!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeleterTests-\(UUID().uuidString)")
        fakeTrash = workDir.appendingPathComponent("FakeTrash")
        try? FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        handlerCalls = []
        deleter = Deleter(removeHandler: { url, mode in
            self.handlerCalls.append(url.lastPathComponent)
            if url.lastPathComponent.contains("locked") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "locked"])
            }
            let dest = self.fakeTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            XCTAssertEqual(mode, .trash) // tests use trash mode only
        })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    private func makeFile(_ name: String, home: String) throws -> URL {
        let homeLib = URL(fileURLWithPath: home + "/Library/Caches")
        try FileManager.default.createDirectory(at: homeLib, withIntermediateDirectories: true)
        let url = homeLib.appendingPathComponent(name)
        try Data([0x1]).write(to: url)
        return url
    }

    func testDeletesDeletablePathsToTrash() async throws {
        let home = workDir.appendingPathComponent("home").path
        let a = try makeFile("com.example.app.a", home: home)
        let b = try makeFile("com.example.app.b", home: home)

        let results = await deleter.delete([a.path, b.path], mode: .trash, appBundlePath: "/Applications/X.app", allowedPathPrefixes: [self.sandboxRoot])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(\.isSuccess))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeTrash.appendingPathComponent("com.example.app.b").path))
    }

    func testUnsafePathsAreSkippedAndNeverTouched() async throws {
        let home = workDir.appendingPathComponent("home").path
        let safe = try makeFile("com.example.app.a", home: home)

        let results = await deleter.delete(
            ["/System/Library/file", "/usr/bin/ls", safe.path],
            mode: .trash, appBundlePath: "/Applications/X.app", allowedPathPrefixes: [self.sandboxRoot]
        )

        XCTAssertEqual(results[0].outcome, .skippedUnsafe)
        XCTAssertEqual(results[1].outcome, .skippedUnsafe)
        XCTAssertEqual(results[2].outcome, .deleted)
        // The unsafe paths were never passed to the remove handler. (SRS FR-21)
        XCTAssertEqual(handlerCalls, ["com.example.app.a"])
    }

    func testBatchResilienceOneFailureDoesNotAbortRest() async throws {
        let home = workDir.appendingPathComponent("home").path
        let ok = try makeFile("app.ok", home: home)
        let locked = try makeFile("app.locked", home: home)
        let ok2 = try makeFile("app.ok2", home: home)

        let results = await deleter.delete([ok.path, locked.path, ok2.path],
                                           mode: .trash, appBundlePath: "/Applications/X.app", allowedPathPrefixes: [self.sandboxRoot])

        XCTAssertEqual(results.map(\.outcome), [.deleted, .failed, .deleted]) // NFR-10
        XCTAssertNotNil(results[1].errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ok.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ok2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.path)) // untouched, recoverable
    }

    func testSecureModeBypassesTrashButKeepsSafetyGate() async throws {
        let secureDeleter = Deleter(removeHandler: { url, mode in
            XCTAssertEqual(mode, .secure)
            try FileManager.default.removeItem(at: url)
        })
        let home = workDir.appendingPathComponent("home2").path
        let file = try makeFile("com.example.app.secure", home: home)

        let results = await secureDeleter.delete([file.path, "/System/x"],
                                                 mode: .secure, appBundlePath: "/Applications/X.app", allowedPathPrefixes: [self.sandboxRoot2])
        XCTAssertEqual(results.map(\.outcome), [.deleted, .skippedUnsafe])
    }

    func testProgressCallbackFiresPerItem() async throws {
        let home = workDir.appendingPathComponent("home3").path
        let a = try makeFile("app.p1", home: home)
        let b = try makeFile("app.p2", home: home)

        var seen: [(Int, Int)] = []
        _ = await deleter.delete([a.path, b.path], mode: .trash, appBundlePath: "/Applications/X.app", allowedPathPrefixes: [self.sandboxRoot]) { done, total in
            seen.append((done, total))
        }
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen[0].0, 1); XCTAssertEqual(seen[0].1, 2)
        XCTAssertEqual(seen[1].0, 2); XCTAssertEqual(seen[1].1, 2)
    }
}

final class AppQuitterTests: XCTestCase {
    func testQuitReturnsTrueWhenNotRunning() async {
        // No real app runs with this impossible bundle id.
        let quit = await AppQuitter.quit(bundleID: "com.macclean.nonexistent.test")
        XCTAssertTrue(quit)
    }

    func testQuitWithEmptyBundleIDIsNoop() async {
        let quit = await AppQuitter.quit(bundleID: "")
        XCTAssertTrue(quit)
    }
}

final class UninstallLoggerTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggerTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private let app = InstalledApp(
        name: "MyApp", version: "1.0", bundleID: "com.example.myapp",
        path: URL(fileURLWithPath: "/Applications/MyApp.app"),
        sizeBytes: 1, lastModifiedDate: nil, isAppleProtected: false)

    func testWriteAndLoadRoundTrip() throws {
        let record = UninstallRecord(
            app: app, date: Date(), mode: "trash",
            items: [
                .init(path: "/Applications/MyApp.app", kind: "appBundle", sizeBytes: 100, outcome: "deleted"),
                .init(path: "/Users/x/Library/Caches/com.example.myapp", kind: "cache", sizeBytes: 40, outcome: "deleted"),
            ]
        )
        let url = try UninstallLogger.write(record, to: dir)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("uninstall-com.example.myapp-"))
        XCTAssertTrue(url.pathExtension == "json")

        let loaded = try UninstallLogger.load(from: url)
        XCTAssertEqual(loaded.bundleID, "com.example.myapp")
        XCTAssertEqual(loaded.items.count, 2)
        XCTAssertEqual(loaded.items.map(\.kind), ["appBundle", "cache"])
    }

    func testRecentLogsNewestFirst() throws {
        for minute in 0..<3 {
            let date = Calendar.current.date(byAdding: .minute, value: minute, to: Date())!
            try UninstallLogger.write(
                UninstallRecord(app: app, date: date, mode: "trash", items: []),
                to: dir
            )
        }
        let logs = UninstallLogger.recentLogs(in: dir)
        XCTAssertEqual(logs.count, 3)
        // Names encode yyyyMMdd-HHmmss → lexicographic order == time order.
        XCTAssertGreaterThan(logs[0].lastPathComponent, logs[2].lastPathComponent)
    }

    func testRecentLogsIgnoresForeignFiles() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("uninstall-x.json"))
        try Data("junk".utf8).write(to: dir.appendingPathComponent("unrelated.txt"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("uninstall-subdir.json"), withIntermediateDirectories: true)
        XCTAssertEqual(UninstallLogger.recentLogs(in: dir).count, 1)
    }

    func testWritesToDefaultDirectoryCreateIt() throws {
        let record = UninstallRecord(app: app, date: Date(), mode: "trash", items: [])
        // Custom path proves directory auto-creation; the real default dir is the user's Logs dir.
        let nested = dir.appendingPathComponent("a/b/c")
        XCTAssertNoThrow(try UninstallLogger.write(record, to: nested))
    }
}