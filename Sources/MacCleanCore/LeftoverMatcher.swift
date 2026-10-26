import Foundation

/// Finds leftover files belonging to an app across the scan locations. (SRS FR-6, FR-7, NFR-4, NFR-5)
///
/// Matching is deliberately conservative: an entry matches only if its name is
/// the bundle id / app name (case-insensitive), optionally followed by a
/// separator (".", "-", "_" or space). This avoids false positives such as
/// "MyApp" matching "MyApplication".
public struct LeftoverMatcher: Sendable {
    public struct Query: Sendable {
        public let bundleID: String
        public let appName: String
        /// Lowercased match patterns (bundle id, app name, de-spaced app name).
        public let patterns: [String]
        /// Reverse-DNS vendor prefix of the bundle id, e.g. "com.example" — used
        /// to look one level into vendor folders (e.g. Application Support/Google/Chrome).
        public let vendorPattern: String?

        public init(bundleID: String, appName: String) {
            self.bundleID = bundleID
            self.appName = appName
            var set = Set<String>()
            if !bundleID.isEmpty { set.insert(bundleID.lowercased()) }
            set.insert(appName.lowercased())
            // "Visual Studio Code" → "visualstudiocode" (folder names often drop spaces)
            set.insert(appName.replacingOccurrences(of: " ", with: "").lowercased())
            if set.contains("") { set.remove("") }
            self.patterns = Array(set)

            let parts = bundleID.lowercased().split(separator: ".").map(String.init)
            self.vendorPattern = parts.count > 2 ? parts.dropLast().joined(separator: ".") : nil
        }

        public init(app: InstalledApp) {
            self.init(bundleID: app.bundleID, appName: app.name)
        }

        /// Does a directory-entry name match this query?
        public func matches(entryName: String) -> Bool {
            let name = entryName.lowercased()
            for pattern in patterns where !pattern.isEmpty {
                if name == pattern { return true }
                // Exact pattern followed by a separator: "com.example.app.plist", "MyApp Helper"
                for separator in [".", "-", "_", " "] {
                    if name.hasPrefix(pattern + separator) { return true }
                }
                // Preference files keep the bundle id and append e.g. ".plist" already covered above.
                if name.hasSuffix("." + pattern) { return true }
            }
            return false
        }

        /// Does the entry look like the vendor folder (one level above real leftovers)?
        public func matchesVendor(entryName: String) -> Bool {
            guard let vendorPattern, !vendorPattern.isEmpty else { return false }
            return entryName.lowercased() == vendorPattern
        }
    }

    public let query: Query

    public init(query: Query) {
        self.query = query
    }

    public init(app: InstalledApp) {
        self.init(query: Query(app: app))
    }

    /// Scans the given locations for leftovers of this query's app.
    /// Runs concurrently across locations; cooperatively cancellable. (NFR-5)
    public func scan(locations: [ScanLocation] = ScanLocations.all()) async -> [LeftoverItem] {
        await withTaskGroup(of: [LeftoverItem].self) { group in
            for location in locations where location.isEnabledByDefault {
                group.addTask { self.scanLocation(location) }
            }
            var result: [LeftoverItem] = []
            for await items in group {
                result.append(contentsOf: items)
            }
            return result.sorted { $0.url.path < $1.url.path }
        }
    }

    func scanLocation(_ location: ScanLocation) -> [LeftoverItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: location.url, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var items: [LeftoverItem] = []
        for entry in contents {
            if Task.isCancelled { return items }
            let name = entry.lastPathComponent

            if query.matches(entryName: name) {
                items.append(makeItem(entry, kind: location.kind))
                continue
            }
            // Vendor folder: look one level deeper for the app's folder,
            // e.g. Application Support/Google/Chrome
            if query.matchesVendor(entryName: name),
               entry.hasDirectoryPath,
               let children = try? FileManager.default.contentsOfDirectory(
                   at: entry, includingPropertiesForKeys: [.isDirectoryKey]
               ) {
                for child in children where query.matches(entryName: child.lastPathComponent) {
                    items.append(makeItem(child, kind: location.kind))
                }
            }
        }
        return items
    }

    private func makeItem(_ url: URL, kind: LeftoverItem.Kind) -> LeftoverItem {
        LeftoverItem(url: url, kind: kind, sizeBytes: DirectorySizer.size(of: url))
    }
}