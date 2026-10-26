import Foundation

/// A single on-disk location scanned for leftovers. (SRS FR-6, SRS FR-21)
public struct ScanLocation: Hashable, Sendable {
    /// The directory whose direct children are candidates for matching.
    public let url: URL
    /// What kind of leftover lives here.
    public let kind: LeftoverItem.Kind
    /// True if files here are typically owned by root and need the privileged helper. (SRS FR-14)
    public let requiresRoot: Bool
    /// True if this location is scanned by default; users can toggle locations in Settings (SRS FR-27).
    public let isEnabledByDefault: Bool

    public init(url: URL, kind: LeftoverItem.Kind, requiresRoot: Bool, isEnabledByDefault: Bool = true) {
        self.url = url
        self.kind = kind
        self.requiresRoot = requiresRoot
        self.isEnabledByDefault = isEnabledByDefault
    }
}

/// All standard scan locations from the SRS. (FR-6)
public enum ScanLocations {
    /// The current user's home Library.
    public static func user(home: String = NSString(string: "~").expandingTildeInPath) -> [ScanLocation] {
        let lib = home + "/Library"
        return [
            ScanLocation(url: URL(fileURLWithPath: lib + "/Application Support"), kind: .applicationSupport, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Caches"), kind: .cache, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Preferences"), kind: .preference, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Logs"), kind: .log, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Containers"), kind: .container, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Group Containers"), kind: .groupContainer, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/Saved Application State"), kind: .savedState, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/WebKit"), kind: .webKit, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/HTTPStorages"), kind: .httpStorage, requiresRoot: false),
            ScanLocation(url: URL(fileURLWithPath: lib + "/LaunchAgents"), kind: .launchAgent, requiresRoot: false),
        ]
    }

    /// System-wide Library locations (root-owned files; require the helper, SRS FR-14).
    public static var system: [ScanLocation] {
        [
            ScanLocation(url: URL(fileURLWithPath: "/Library/Application Support"), kind: .applicationSupport, requiresRoot: true),
            ScanLocation(url: URL(fileURLWithPath: "/Library/Caches"), kind: .cache, requiresRoot: true),
            ScanLocation(url: URL(fileURLWithPath: "/Library/Preferences"), kind: .preference, requiresRoot: true),
            ScanLocation(url: URL(fileURLWithPath: "/Library/Logs"), kind: .log, requiresRoot: true),
            ScanLocation(url: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .launchAgent, requiresRoot: true),
            ScanLocation(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .launchDaemon, requiresRoot: true),
        ]
    }

    /// User + system locations, user first.
    public static func all(home: String = NSString(string: "~").expandingTildeInPath) -> [ScanLocation] {
        user(home: home) + system
    }
}