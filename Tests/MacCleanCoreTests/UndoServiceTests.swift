import XCTest
@testable import MacCleanCore

/// Best-effort Trash restore (SRS FR-20) — tests use an injected "Trash"
/// directory so they don't touch (or need TCC access to) the real ~/.Trash.
final class UndoServiceTests: XCTestCase {
    private var root: URL!
    private var fakeTrash: URL!
    private var logDir: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory() + "macclean-undo-\(UUID().uuidString)")
        fakeTrash = root.appendingPathComponent("trash")
        logDir = root.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// A uninstall record whose "deleted" items sit in the injected Trash dir.
    private func makeRecord(items: [(path: String, outcome: String)]) throws -> UninstallRecord {
        let app = InstalledApp(
            name: "MyApp", version: "1", bundleID: "com.example.myapp",
            path: URL(fileURLWithPath: "/Applications/MyApp.app"),
            sizeBytes: 100, lastModifiedDate: nil, isAppleProtected: false)
        let records = items.map {
            UninstallRecord.ItemRecord(path: $0.path, kind: "cache", sizeBytes: 1, outcome: $0.outcome)
        }
        return UninstallRecord(app: app, date: Date(), mode: "trash", items: records)
    }

    func testRestoreMovesTrashedItemsBackToOriginalPaths() throws {
        // Two deleted items currently "in the Trash", plus one failure (never
        // deleted, so not restorable) and one already restored (conflict).
        let prefs = root.appendingPathComponent("Library/Preferences/com.example.myapp.plist").path
        let cache = root.appendingPathComponent("Library/Caches/com.example.myapp").path

        for item in [prefs, cache] {
            let trashItem = fakeTrash.appendingPathComponent((item as NSString).lastPathComponent)
            try FileManager.default.createDirectory(
                at: trashItem, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: trashItem.appendingPathComponent("data"))
        }

        let record = try makeRecord(items: [
            (prefs, "deleted"), (cache, "deleted"),
            (root.appendingPathComponent("gone").path, "failed"),
        ])

        let results = UndoService.undo(record: record, trashDirectory: fakeTrash)

        XCTAssertEqual(results.count, 2, "only items with outcome 'deleted' are attempted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefs))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache))
        XCTAssertEqual(
            results.filter(\.restored).count, 2, "both trashed items should restore, got: \(results)")
    }

    func testRestoreReportsMissingTrashItemAsBestEffortFailure() throws {
        let missing = root.appendingPathComponent("Library/Caches/vanished").path
        let record = try makeRecord(items: [(missing, "deleted")])

        let results = UndoService.undo(record: record, trashDirectory: fakeTrash)
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].restored)
        XCTAssertFalse(results[0].message.isEmpty)
    }

    func testRestoreRecreatesMissingParentFolder() throws {
        let deep = root.appendingPathComponent("Library/Containers/com.example.myapp/Data").path
        try FileManager.default.createDirectory(
            at: fakeTrash.appendingPathComponent("Data"), withIntermediateDirectories: true)

        let record = try makeRecord(items: [(deep, "deleted")])
        let results = UndoService.undo(record: record, trashDirectory: fakeTrash)

        XCTAssertTrue(results[0].restored, results[0].message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: deep))
    }

    func testLatestRecordReturnsNewestLog() throws {
        XCTAssertNil(UndoService.latestRecord(in: logDir))

        let oldApp = InstalledApp(
            name: "Old", version: "1", bundleID: "com.old",
            path: URL(fileURLWithPath: "/Applications/Old.app"),
            sizeBytes: 0, lastModifiedDate: nil, isAppleProtected: false)
        let newApp = InstalledApp(
            name: "New", version: "1", bundleID: "com.new",
            path: URL(fileURLWithPath: "/Applications/New.app"),
            sizeBytes: 0, lastModifiedDate: nil, isAppleProtected: false)
        try UninstallLogger.write(
            UninstallRecord(app: oldApp, date: Date().addingTimeInterval(-60), mode: "trash", items: []),
            to: logDir)
        try UninstallLogger.write(
            UninstallRecord(app: newApp, date: Date(), mode: "trash", items: []),
            to: logDir)

        XCTAssertEqual(UndoService.latestRecord(in: logDir)?.bundleID, "com.new")
    }
}