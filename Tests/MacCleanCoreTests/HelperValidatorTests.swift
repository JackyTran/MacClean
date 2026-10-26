import XCTest
@testable import MacCleanCore

final class HelperRequestValidatorTests: XCTestCase {
    private let appBundle = "/Applications/MyApp.app"

    func testHelperRevalidatesPathsAgainstAllowedPrefixes() {
        let (valid, rejected) = HelperRequestValidator.split(
            paths: [
                "/Library/Application Support/MyApp/data.db",   // root-owned, allowed
                "/Library/Preferences/com.example.myapp.plist",  // allowed
                "/System/Library/whatever",                     // forbidden
                "/Users/x/Documents/secret.doc",               // outside allow-list
                "/Applications/MyApp.app",                      // the app bundle itself
            ],
            appBundlePath: appBundle,
            allowedPathPrefixes: ["/Library", "/Applications", "/Users/x/Library"]
        )

        XCTAssertEqual(valid, [
            "/Library/Application Support/MyApp/data.db",
            "/Library/Preferences/com.example.myapp.plist",
        ])
        XCTAssertEqual(Set(rejected), [
            "/System/Library/whatever",
            "/Users/x/Documents/secret.doc",
            "/Applications/MyApp.app",
        ])
    }

    func testRejectsEverythingWithEmptyAllowList() {
        let (valid, rejected) = HelperRequestValidator.split(
            paths: ["/Library/Caches/x"],
            appBundlePath: appBundle,
            allowedPathPrefixes: []
        )
        XCTAssertTrue(valid.isEmpty)
        XCTAssertEqual(rejected, ["/Library/Caches/x"])
    }

    func testResultParsingRoundTrip() {
        let original = [
            DeletionResult(path: "/Library/Caches/a", outcome: .deleted),
            DeletionResult(path: "/Library/b", outcome: .failed, errorMessage: "nope"),
            DeletionResult(path: "/System/c", outcome: .skippedUnsafe),
        ]
        let payload = HelperResultParsing.serialize(original)
        let parsed = HelperResultParsing.parse(payload)

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed.map(\.path), original.map(\.path))
        XCTAssertEqual(parsed.map(\.outcome), original.map(\.outcome))
        XCTAssertEqual(parsed[1].errorMessage, "nope")
    }

    func testParsingIgnoresMalformedEntries() {
        let payload: [[String: Any]] = [
            ["path": "/ok", "outcome": "deleted"],
            ["path": "/bad-outcome", "outcome": "nonsense"],   // unknown outcome → dropped
            ["outcome": "deleted"],                            // missing path → dropped
        ]
        let parsed = HelperResultParsing.parse(payload)
        XCTAssertEqual(parsed.map(\.path), ["/ok"])
    }
}