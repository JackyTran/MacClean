import XCTest
@testable import MacCleanCore

/// End-to-end integration test of the privileged helper's algorithm (TASKS T5.5).
///
/// This runs the *exact sequence the XPC handler performs* — helper-side
/// SafetyRules re-validation → RootFileDeleter (real Trash) → XPC payload
/// round trip — against real files in the user's real Library.
///
/// The parts this deliberately does NOT cover, and why:
///   - launchd/SMAppService daemon spawning and root privilege: these come from
///     launchd + Developer ID signing. On this OS the execution policy blocks
///     launchd-spawned ad-hoc binaries (dyld hangs on provenance validation),
///     so the signed-daemon flow is verified manually in M7 (see TASKS.md).
///   - The XPC wire itself: Apple's transport. Protocol + payload are covered
///     here via the serialize/parse round trip and by HelperValidatorTests.
final class HelperIntegrationTests: XCTestCase {
    private let appBundle = "/Applications/MacClean-IntegrationTest.app"
    private var cachesDir: String { NSString(string: "~").expandingTildeInPath + "/Library/Caches" }

    private func makeLeftover(_ name: String = "macclean-itest-\(UUID().uuidString)") throws -> String {
        let path = cachesDir + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Data("leftover".utf8).write(to: URL(fileURLWithPath: path + "/cache.db"))
        return path
    }

    func testFullHandlerSequenceDeletesAndRefusesUnsafePaths() throws {
        let leftover = try makeLeftover()

        let request = [leftover, "/System/Library/never.txt", appBundle]

        // --- HelperService.delete does exactly this (Sources/MacCleanHelper/main.swift) ---
        let (valid, rejected) = HelperRequestValidator.split(
            paths: request,
            appBundlePath: appBundle,
            allowedPathPrefixes: HelperClientAllowList.standard
        )
        var results: [DeletionResult] = valid.map { RootFileDeleter.delete($0) }
        results += rejected.map { DeletionResult(path: $0, outcome: .skippedUnsafe) }
        let parsed = HelperResultParsing.parse(HelperResultParsing.serialize(results))
        // ---------------------------------------------------------------------------------

        XCTAssertEqual(valid, [leftover], "the real Library leftover must be the only valid path")
        XCTAssertEqual(Set(rejected), ["/System/Library/never.txt", appBundle])

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed.first { $0.path == leftover }?.outcome, .deleted)
        XCTAssertEqual(parsed.first { $0.path == "/System/Library/never.txt" }?.outcome, .skippedUnsafe)
        XCTAssertEqual(parsed.first { $0.path == appBundle }?.outcome, .skippedUnsafe)

        // The leftover is really gone from disk…
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover))
        // …and /System was never touched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Library"))
    }

    /// Proves the Trash-first behavior against the real Trash: trashItem returns
    /// the resulting URL inside the Trash volume (FR-18) — no TCC-blocked
    /// directory listing needed.
    func testTrashFirstLandsInRealTrash() throws {
        let leftover = try makeLeftover()
        let trashedURL = try RootFileDeleter.trash(URL(fileURLWithPath: leftover))
        XCTAssertTrue(
            trashedURL.path.contains("/.Trash/") || trashedURL.path.contains("/Trash/"),
            "item should land in the Trash, got: \(trashedURL.path)"
        )
        // Best-effort cleanup of the trashed test item.
        try? FileManager.default.removeItem(at: trashedURL)
    }

    func testRootDeleterReportsFailuresPerItem() {
        let missing = NSTemporaryDirectory() + "macclean-missing-\(UUID().uuidString)/nope"
        let result = RootFileDeleter.delete(missing)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertNotNil(result.errorMessage)
    }
}

/// Mirrors MacCleanApp's HelperClient.allowedPrefixes (kept in Core so the test
/// exercises the same allow-list the app sends over XPC).
enum HelperClientAllowList {
    static var standard: [String] {
        let home = NSString(string: "~").expandingTildeInPath
        return ["/Library", "/Applications", "/usr/local", home + "/Library", home + "/Applications"]
    }
}