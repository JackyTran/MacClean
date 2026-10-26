import Foundation

/// Scans standard application locations for .app bundles. (SRS FR-1, FR-2, FR-4)
public struct AppScanner: Sendable {
    /// Standard locations enumerated by the scanner. (SRS FR-1)
    public static let standardLocations: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: NSString(string: "~").expandingTildeInPath + "/Applications"),
    ]

    public init() {}

    /// Enumerates all .app bundles in the standard locations.
    public func scan(locations: [URL] = AppScanner.standardLocations) async -> [InstalledApp] {
        // Enumerate first (cheap), then build every app concurrently. Sizing an
        // app walks its entire bundle — ~480k files across the apps in
        // /Applications — so doing it one app at a time left the list empty for
        // ~20 s, long enough to look like a hang. The work is independent per
        // app and read-only, so it parallelises cleanly.
        let urls = locations.flatMap { appURLs(in: $0) }

        var result: [InstalledApp] = []
        await withTaskGroup(of: InstalledApp?.self) { group in
            for url in urls {
                group.addTask {
                    self.makeApp(at: url)
                }
            }
            for await app in group {
                if let app { result.append(app) }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The .app bundles directly inside `location`. Metadata only — cheap.
    func appURLs(in location: URL) -> [URL] {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: location, includingPropertiesForKeys: [
                .isDirectoryKey, .contentModificationDateKey,
            ]) else {
            return []
        }

        return contents.filter { $0.hasDirectoryPath && $0.pathExtension == "app" }
    }

    /// Scans a single location. Serial — used for one directory at a time.
    func scanLocation(_ location: URL) -> [InstalledApp] {
        appURLs(in: location).compactMap { url in makeApp(at: url) }
    }

    func makeApp(at url: URL) -> InstalledApp? {
        let bundle = Bundle(path: url.path)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let bundleID = bundle?.bundleIdentifier ?? ""

        let isAppleProtected = AppleAppClassifier.isProtected(path: url.path, bundleID: bundleID)
        let isHomebrewInstalled = HomebrewDetector.isInstalledByHomebrew(appPath: url.path)

        var size: Int64 = 0
        var modified: Date?
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    size += Int64(values?.fileSize ?? 0)
                }
            }
            modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }

        return InstalledApp(
            name: name,
            version: version,
            bundleID: bundleID,
            path: url,
            sizeBytes: size,
            lastModifiedDate: modified,
            isAppleProtected: isAppleProtected,
            isHomebrewInstalled: isHomebrewInstalled
        )
    }
}