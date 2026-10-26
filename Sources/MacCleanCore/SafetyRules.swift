import Foundation

/// Hard safety rules that every deletion path must pass. (SRS FR-21)
public enum SafetyRules {
    /// Paths that must never be deleted by the app, under any circumstances.
    public static let forbiddenPathPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private",
    ]

    /// A path is deletable only if it lives inside one of these locations. (SRS FR-6, FR-21)
    public static let allowedPathPrefixes: [String] = [
        "/Applications", "/Library", "/usr/local",  // Homebrew caskroom etc.
        NSString(string: "~").expandingTildeInPath + "/Library",
        NSString(string: "~").expandingTildeInPath + "/Applications",
    ]

    /// Returns true if the path may be deleted. The single gate for all deletions.
    /// `allowedPrefixes` is injectable so tests can run inside sandboxed temp dirs.
    public static func isDeletable(
        _ path: String,
        appBundlePath: String,
        allowedPrefixes: [String] = allowedPathPrefixes
    ) -> Bool {
        let standardized = (path as NSString).standardizingPath

        // Never touch the running app itself or anything inside an app bundle's own contents
        if standardized == appBundlePath { return false }

        guard forbiddenPathPrefixes.allSatisfy({ !standardized.hasPrefix($0 + "/") && standardized != $0 })
        else { return false }

        // /usr/local is allowed; the other /usr paths are forbidden — check allowed prefixes explicitly
        return allowedPrefixes.contains { prefix in
            standardized == prefix || standardized.hasPrefix(prefix + "/")
        }
    }
}