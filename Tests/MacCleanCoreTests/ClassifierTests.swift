import XCTest
@testable import MacCleanCore

final class AppleAppClassifierTests: XCTestCase {
    func testSystemAppsAreProtected() {
        XCTAssertTrue(AppleAppClassifier.isProtected(
            path: "/System/Applications/Safari.app", bundleID: "com.apple.Safari"))
        XCTAssertTrue(AppleAppClassifier.isProtected(
            path: "/System/Applications/Utilities/Terminal.app", bundleID: "com.apple.Terminal"))
    }

    func testAppleBundleIDsAreProtectedAnywhere() {
        XCTAssertTrue(AppleAppClassifier.isProtected(
            path: "/Applications/SomeAppleApp.app", bundleID: "com.apple.something"))
    }

    func testThirdPartyAppsAreNotProtected() {
        XCTAssertFalse(AppleAppClassifier.isProtected(
            path: "/Applications/MyApp.app", bundleID: "com.example.myapp"))
        XCTAssertFalse(AppleAppClassifier.isProtected(
            path: "/Applications/Bare.app", bundleID: ""))
    }
}

final class HomebrewDetectorTests: XCTestCase {
    func testCaskroomPathsDetected() {
        XCTAssertTrue(HomebrewDetector.isInstalledByHomebrew(
            appPath: "/opt/homebrew/Caskroom/firefox/129.0/Firefox.app"))
        XCTAssertTrue(HomebrewDetector.isInstalledByHomebrew(
            appPath: "/usr/local/Caskroom/visual-studio-code/1.9/Visual Studio Code.app"))
    }

    func testNonCaskroomPathsNotDetected() {
        XCTAssertFalse(HomebrewDetector.isInstalledByHomebrew(
            appPath: "/Applications/Firefox.app"))
        XCTAssertFalse(HomebrewDetector.isInstalledByHomebrew(
            appPath: "/opt/homebrew/Cellar/something/1.0/foo")) // formula, not cask app
    }

    func testPrefixStringIsNotDirectoryPrefix() {
        // "Caskroom2" must not match
        XCTAssertFalse(HomebrewDetector.isInstalledByHomebrew(
            appPath: "/opt/homebrew/Caskroom2/foo.app"))
    }
}
final class HomebrewDetectorProcessTests: XCTestCase {
    func testInstalledCasksRunsBrewSafely() async {
        // Exercises the full Process path: real brew when available,
        // graceful [] when not. Must never hang or crash. (SRS NFR-11)
        let casks = await HomebrewDetector.installedCasks()
        // Any result is valid; the guarantee is completion + well-typed output.
        XCTAssertTrue(casks.allSatisfy { !$0.isEmpty })
    }
}
