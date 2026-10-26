import XCTest
@testable import MacCleanCore

final class LeftoverItemKindTests: XCTestCase {
    func testDefaultSelectionFollowsFR7() {
        // Caches and logs are pre-selected (SRS FR-7); everything else is opt-in.
        XCTAssertTrue(LeftoverItem.Kind.cache.isDefaultSelected)
        XCTAssertTrue(LeftoverItem.Kind.log.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.preference.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.applicationSupport.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.container.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.groupContainer.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.savedState.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.webKit.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.httpStorage.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.launchAgent.isDefaultSelected)
        XCTAssertFalse(LeftoverItem.Kind.launchDaemon.isDefaultSelected)
    }

    func testDisplayNames() {
        XCTAssertEqual(LeftoverItem.Kind.applicationSupport.displayName, "Application Support")
        XCTAssertEqual(LeftoverItem.Kind.groupContainer.displayName, "Group Container")
        XCTAssertEqual(LeftoverItem.Kind.launchDaemon.displayName, "Launch Daemon")
    }

    func testInitDefaultsSelectionFromKind() {
        let cache = LeftoverItem(url: URL(fileURLWithPath: "/tmp/x"), kind: .cache, sizeBytes: 1)
        let pref = LeftoverItem(url: URL(fileURLWithPath: "/tmp/y"), kind: .preference, sizeBytes: 1)
        XCTAssertTrue(cache.isSelected)
        XCTAssertFalse(pref.isSelected)

        let forced = LeftoverItem(url: URL(fileURLWithPath: "/tmp/z"), kind: .preference, sizeBytes: 1, isSelected: true)
        XCTAssertTrue(forced.isSelected)
    }

    func testIDAndHashableUsePath() {
        let a = LeftoverItem(url: URL(fileURLWithPath: "/tmp/same"), kind: .cache, sizeBytes: 1)
        let b = LeftoverItem(url: URL(fileURLWithPath: "/tmp/same"), kind: .log, sizeBytes: 2)
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(a, b) // different kind/size → not equal even with same id
    }
}

final class ScanLocationsTests: XCTestCase {
    func testUserLocationsCoverSRSList() {
        let home = "/Users/test"
        let paths = Set(ScanLocations.user(home: home).map { $0.url.path })
        for required in [
            "/Users/test/Library/Application Support", "/Users/test/Library/Caches",
            "/Users/test/Library/Preferences", "/Users/test/Library/Logs",
            "/Users/test/Library/Containers", "/Users/test/Library/Group Containers",
            "/Users/test/Library/Saved Application State", "/Users/test/Library/WebKit",
            "/Users/test/Library/HTTPStorages", "/Users/test/Library/LaunchAgents",
        ] {
            XCTAssertTrue(paths.contains(required), "missing scan location: \(required)")
        }
    }

    func testSystemLocationsCoverSRSListAndRequireRoot() {
        let paths = Set(ScanLocations.system.map(\.url.path))
        for required in [
            "/Library/Application Support", "/Library/Caches",
            "/Library/Preferences", "/Library/Logs",
        ] {
            XCTAssertTrue(paths.contains(required), "missing scan location: \(required)")
        }
        XCTAssertTrue(ScanLocations.system.allSatisfy(\.requiresRoot))
        XCTAssertTrue(ScanLocations.user(home: "/Users/test").allSatisfy { !$0.requiresRoot })
    }

    func testAllIsUserPlusSystem() {
        let all = ScanLocations.all(home: "/Users/test")
        XCTAssertEqual(all.count, ScanLocations.user(home: "/Users/test").count + ScanLocations.system.count)
    }
}