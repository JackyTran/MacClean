import XCTest
@testable import MacCleanCore

final class SafetyRulesTests: XCTestCase {
    private let appBundle = "/Applications/MyApp.app"
    private let home = NSString(string: "~").expandingTildeInPath

    func testSystemPathsAreForbidden() {
        for path in ["/System/Applications", "/usr/bin", "/bin", "/sbin", "/private/etc", "/System"] {
            XCTAssertFalse(SafetyRules.isDeletable(path, appBundlePath: appBundle), "\(path) must not be deletable")
        }
    }

    func testRunningAppBundleIsForbidden() {
        XCTAssertFalse(SafetyRules.isDeletable("/Applications/MyApp.app", appBundlePath: "/Applications/MyApp.app"))
    }

    /// `appBundlePath` is the *running* app's bundle — the self-protection
    /// reference. A different app's bundle must stay deletable, otherwise
    /// uninstalling can never actually remove the app from /Applications.
    func testOtherAppBundleStaysDeletable() {
        XCTAssertTrue(SafetyRules.isDeletable(
            "/Applications/Other.app", appBundlePath: "/Applications/MacClean.app"))
        XCTAssertTrue(SafetyRules.isDeletable(
            "\(home)/Applications/Other.app", appBundlePath: "/Applications/MacClean.app"))
    }

    func testLibraryPathsAreAllowed() {
        XCTAssertTrue(SafetyRules.isDeletable("\(home)/Library/Caches/com.example.app", appBundlePath: appBundle))
        XCTAssertTrue(SafetyRules.isDeletable("\(home)/Library/Preferences/com.example.app.plist", appBundlePath: appBundle))
        XCTAssertTrue(SafetyRules.isDeletable("/Library/Application Support/SomeApp", appBundlePath: appBundle))
    }

    func testRandomUserPathsAreForbidden() {
        XCTAssertFalse(SafetyRules.isDeletable("\(home)/Documents/important.doc", appBundlePath: appBundle))
        XCTAssertFalse(SafetyRules.isDeletable("/Users", appBundlePath: appBundle))
    }

    func testTraversalAndRelativePathsRejected() {
        // Standardizing must resolve ".." before the prefix check (SRS NFR-11)
        XCTAssertFalse(SafetyRules.isDeletable("/Applications/../../System/x", appBundlePath: appBundle))
    }
}