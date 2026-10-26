import XCTest
import Darwin

/// End-to-end uninstall of a fixture app (SRS FR-2, FR-13, FR-17; TASKS T6.6).
///
/// The fixture is a throwaway `.app` bundle in `~/Applications` — one of the
/// scanner's standard locations, and harmless to delete. The test proves the
/// two things a real uninstall must do:
///
///   1. the app bundle actually leaves the disk, and
///   2. the app disappears from the sidebar list.
///
/// Both used to fail: the uninstall passed the *target* app's path as the
/// self-protection reference, so the bundle was refused as "skipped (unsafe
/// path)" and stayed in /Applications; and the sidebar list was a snapshot
/// taken at launch, so it kept showing the removed app.
final class MacCleanUninstallUITests: XCTestCase {
    private static let fixtureName = "MacCleanFixture"

    /// The *real* home directory. A UI-test runner has its HOME redirected to
    /// a sandbox container, but the app under test runs with the real one, so
    /// the fixture has to live in the real home to be visible to it.
    private static var realHome: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    private var fixtureURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureURL = URL(fileURLWithPath: Self.realHome)
            .appendingPathComponent("Applications/\(Self.fixtureName).app")
    }

    override func tearDownWithError() throws {
        // The uninstall moves the fixture to the Trash — remove it from there
        // too. Listing ~/.Trash is blocked for test runners, but removing a
        // known path directly is not.
        let home = URL(fileURLWithPath: Self.realHome)
        try? FileManager.default.removeItem(
            at: home.appendingPathComponent(".Trash/\(Self.fixtureName).app"))
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    func testUninstallRemovesAppFromDiskAndSidebar() throws {
        let app = XCUIApplication()
        // The app under test is not sandboxed, so it creates the fixture itself.
        app.launchEnvironment["MACCLEAN_UI_FIXTURE"] = fixtureURL.path
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "main window should appear")

        let list = app.descendants(matching: .any)["app-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "app list should exist")

        // Narrow the list to the fixture.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "sidebar search field should exist")
        search.click()
        search.typeText(Self.fixtureName)

        // The row's accessibility label is "<name>, version <v>, <size>".
        let row = list.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Self.fixtureName))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 120), "fixture app should appear in the list")
        row.click()

        // Scan → review → confirm → move to Trash.
        let scan = app.buttons["Scan for leftover files"].firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 10), "scan button should appear")
        scan.click()

        let uninstall = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Uninstall")
        ).firstMatch
        XCTAssertTrue(uninstall.waitForExistence(timeout: 30), "uninstall button should appear")
        uninstall.click()

        let confirm = app.buttons["confirm-delete-button"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "confirmation should appear")
        confirm.click()

        // The summary of the run is reported in an alert, which outlives the
        // detail pane the app was uninstalled from.
        let summary = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Moved", "Moved")
        ).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 60),
                      "the uninstall summary should be reported")

        // 1. The bundle is really gone from ~/Applications.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixtureURL.path),
            "the app bundle should be removed from ~/Applications")

        // 2. The sidebar list drops it (the list is refreshed after uninstall).
        let stillListed = list.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", Self.fixtureName))
            .firstMatch
        XCTAssertTrue(
            stillListed.waitForNonExistence(timeout: 60),
            "the uninstalled app should disappear from the sidebar list")
    }
}
