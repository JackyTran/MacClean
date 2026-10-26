import Foundation

/// Finds leftovers of apps that are already uninstalled. (SRS FR-10)
///
/// An entry in a scan location is an orphan candidate when it *looks like* it
/// belongs to some app (bundle-id-shaped or app-name-shaped) but no installed
/// app claims it. Apple-owned entries (com.apple.*) are always ignored.
public struct OrphanScanner: Sendable {
    public init() {}

    public func scan(
        installedApps: [InstalledApp],
        locations: [ScanLocation] = ScanLocations.all()
    ) async -> [LeftoverItem] {
        // Everything installed apps might claim: bundle ids and app names.
        var claimed = Set<String>()
        for app in installedApps {
            claimed.insert(app.bundleID.lowercased())
            claimed.insert(app.name.lowercased())
            claimed.insert(app.name.replacingOccurrences(of: " ", with: "").lowercased())
        }

        return await withTaskGroup(of: [LeftoverItem].self) { group in
            for location in locations where location.isEnabledByDefault {
                group.addTask { self.scanLocation(location, claimed: claimed) }
            }
            var result: [LeftoverItem] = []
            for await items in group {
                result.append(contentsOf: items)
            }
            return result.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    func scanLocation(_ location: ScanLocation, claimed: Set<String>) -> [LeftoverItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: location.url, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var items: [LeftoverItem] = []
        for entry in contents {
            if Task.isCancelled { return items }
            let name = entry.lastPathComponent

            // Only entries shaped like a bundle id (x.y.z with ≥ 2 dots) or with a
            // bundle-id filename are considered; plain folder names are too risky.
            guard Self.isBundleIDShaped(name) else { continue }
            // Apple's own files are everywhere and always stay.
            if name.lowercased().hasPrefix("com.apple.") { continue }
            // Claimed by an installed app? Not an orphan.
            if Self.isClaimed(name, claimed: claimed) { continue }

            items.append(LeftoverItem(
                url: entry, kind: location.kind, sizeBytes: DirectorySizer.size(of: entry)
            ))
        }
        return items
    }

    /// "com.example.app.plist" / "com.example.app" — reverse-DNS shaped.
    static func isBundleIDShaped(_ name: String) -> Bool {
        let base = name.hasSuffix(".plist") ? String(name.dropLast(6)) : name
        let parts = base.split(separator: ".")
        return parts.count >= 3
        && parts.allSatisfy { !$0.isEmpty && $0.range(of: "[^a-z0-9-]", options: .regularExpression) == nil }
    }

    /// Does any installed app's pattern prefix this name? (Conservative, like LeftoverMatcher.)
    static func isClaimed(_ name: String, claimed: Set<String>) -> Bool {
        let lower = name.lowercased()
        for pattern in claimed where !pattern.isEmpty {
            if lower == pattern || lower.hasPrefix(pattern + ".") { return true }
        }
        return false
    }
}