import Foundation

/// User-configurable settings for MacClean. (SRS FR-27, FR-28)
public struct AppSettings: Codable, Equatable, Sendable {
    /// Secure (permanent) deletion instead of Trash-first. (SRS FR-16)
    public var secureDeleteEnabled: Bool = false
    /// Scan locations (by path) the user turned off.
    public var disabledLocationPaths: Set<String> = []
    /// Extra folders the user wants scanned for leftovers.
    public var customScanFolders: [String] = []
    /// Days to keep uninstall logs; older logs are purged. (SRS FR-27)
    public var logRetentionDays: Int = 30

    public init() {}

    /// The effective scan locations: defaults minus disabled, plus custom folders.
    public func scanLocations(home: String = NSString(string: "~").expandingTildeInPath) -> [ScanLocation] {
        var locations = ScanLocations.all(home: home)
            .filter { !disabledLocationPaths.contains($0.url.path) }
        locations += customScanFolders
            .filter { !$0.isEmpty }
            .map { ScanLocation(url: URL(fileURLWithPath: $0), kind: .other, requiresRoot: false) }
        return locations
    }
}

/// Loads/saves settings from UserDefaults. (SRS FR-28)
public enum SettingsStore {
    static let key = "com.macclean.settings.v1"

    public static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    /// Purges uninstall logs older than `settings.logRetentionDays`. (SRS FR-27)
    @discardableResult
    public static func purgeOldLogs(
        _ settings: AppSettings,
        in directory: URL = UninstallLogger.logsDirectory(),
        now: Date = Date()
    ) -> Int {
        guard settings.logRetentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(settings.logRetentionDays) * 86_400)
        var removed = 0
        for url in UninstallLogger.recentLogs(limit: .max, in: directory) {
            guard let record = try? UninstallLogger.load(from: url),
                  record.date < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }
}