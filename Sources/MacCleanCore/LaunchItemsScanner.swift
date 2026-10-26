import Foundation

/// Finds LaunchAgents/LaunchDaemons belonging to an app by reading their plists. (SRS FR-11)
///
/// A LaunchAgent plist may be named after the agent binary rather than the app,
/// so we load each plist and match its Label / program paths against the query
/// instead of relying on the file name alone.
public struct LaunchItemsScanner: Sendable {
    public let query: LeftoverMatcher.Query

    public init(query: LeftoverMatcher.Query) {
        self.query = query
    }

    public init(app: InstalledApp) {
        self.init(query: .init(app: app))
    }

    public func scan(locations: [ScanLocation] = ScanLocations.all()) async -> [LeftoverItem] {
        locations
            .filter { $0.kind == .launchAgent || $0.kind == .launchDaemon }
            .flatMap { scanLocation($0) }
            .sorted { $0.url.path < $1.url.path }
    }

    func scanLocation(_ location: ScanLocation) -> [LeftoverItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: location.url, includingPropertiesForKeys: nil
        ) else { return [] }

        var items: [LeftoverItem] = []
        for entry in contents where entry.pathExtension == "plist" {
            guard let dict = NSDictionary(contentsOf: entry) else { continue }
            if Self.plist(dict, belongsTo: query) {
                items.append(LeftoverItem(
                    url: entry, kind: location.kind, sizeBytes: DirectorySizer.size(of: entry)
                ))
            }
        }
        return items
    }

    /// True if any string value in the plist references the app's bundle id or name.
    static func plist(_ dict: NSDictionary, belongsTo query: LeftoverMatcher.Query) -> Bool {
        for (key, value) in dict {
            guard let string = value as? String else { continue }
            let valueLower = string.lowercased()
            for pattern in query.patterns {
                if valueLower == pattern
                    || valueLower.hasPrefix(pattern + ".")
                    || valueLower.hasPrefix(pattern + "/")
                    || valueLower.hasSuffix("/" + pattern)
                    || valueLower.contains("/" + pattern + "/")
                    // Program paths reference the bundle: /Applications/MyApp.app/...
                    || valueLower.contains(pattern + ".app") {
                    return true
                }
            }
        }
        return false
    }
}