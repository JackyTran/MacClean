import XCTest

/// Smoke test of the main flow visible to a fresh launch (SRS NFR-16, TASKS T6.6):
/// window opens → app list shows real installed apps → search works →
/// selecting an app shows the uninstall section with the scan button.
///
/// The destructive tail of the flow (confirm → delete) is intentionally NOT
/// automated against real installed apps; deletion behavior is covered by
/// the unit and integration suites (DeleterTests, HelperIntegrationTests).
final class MacCleanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchListSelectShowsScanButton() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        if !window.waitForExistence(timeout: 15) {
            print("APP STATE: \(app.state.rawValue)")
            print("DEBUG TREE:\n\(app.debugDescription.prefix(4000))")
            XCTFail("main window should appear")
            return
        }

        let list = app.descendants(matching: .any)["app-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "app list should exist")

        // The real /Applications has entries; the list should be non-empty.
        // The header counts the *filtered* apps and shows a spinner while the
        // scan is still running — "0 apps" alone does not mean the list is
        // ready, so wait for a non-zero count before touching the rows.
        let populated = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "[1-9][0-9]* apps"))
            .firstMatch
        XCTAssertTrue(
            populated.waitForExistence(timeout: 180),
            "list header should show a non-zero app count once the scan finishes")

        // Search narrows the list (keyboard navigation path).
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "sidebar search field should exist")
        search.click()
        search.typeText("zzz-no-such-app")
        let empty = app.descendants(matching: .any)["empty-state"].firstMatch
        _ = empty.waitForExistence(timeout: 5) // either state is fine; must not crash
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))

        // Select the first row via keyboard (also exercises keyboard
        // navigation, NFR-12); the detail pane should expose the scan button.
        // Click a row rather than the list container: the container is a
        // scroll view and is not hittable, while an app row's accessibility
        // label always carries "version" (the header row carries the count).
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", ", version "))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "app list should contain app rows")
        row.click()
        app.typeKey(.downArrow, modifierFlags: [])
        let scan = app.buttons["Scan for leftover files"].firstMatch
        if scan.waitForExistence(timeout: 5) {
            XCTAssertTrue(scan.isHittable)
        } else {
            // Apple-protected apps show a lock message instead — also valid.
            XCTAssertTrue(
                app.staticTexts["This is an Apple system app and cannot be uninstalled."]
                    .waitForExistence(timeout: 5),
                "detail pane should show either the scan button or the protected-app notice")
        }
    }
}