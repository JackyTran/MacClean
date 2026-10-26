import Foundation

/// Writes one JSON log per uninstall. (SRS FR-19)
///
/// The log lists every path that was deleted so that Undo (M6 / FR-20) and
/// post-mortem inspection are possible. Lives in ~/Library/Logs/MacClean/.
public struct UninstallRecord: Codable, Sendable {
    public struct ItemRecord: Codable, Sendable {
        public let path: String
        public let kind: String       // LeftoverItem.Kind raw value or "appBundle"
        public let sizeBytes: Int64
        public let outcome: String    // deleted / failed / skippedUnsafe

        public init(path: String, kind: String, sizeBytes: Int64, outcome: String) {
            self.path = path
            self.kind = kind
            self.sizeBytes = sizeBytes
            self.outcome = outcome
        }
    }

    public let appName: String
    public let bundleID: String
    public let appPath: String
    public let date: Date
    public let mode: String          // trash / secure
    public let items: [ItemRecord]

    public init(app: InstalledApp, date: Date, mode: String, items: [ItemRecord]) {
        self.appName = app.name
        self.bundleID = app.bundleID
        self.appPath = app.path.path
        self.date = date
        self.mode = mode
        self.items = items
    }
}

public enum UninstallLogger {
    /// ~/Library/Logs/MacClean/ (SRS FR-19)
    public static func logsDirectory(home: String = NSString(string: "~").expandingTildeInPath) -> URL {
        URL(fileURLWithPath: home + "/Library/Logs/MacClean")
    }

    /// Writes the record as JSON, returns its file URL.
    @discardableResult
    public static func write(
        _ record: UninstallRecord,
        to directory: URL = UninstallLogger.logsDirectory()
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeID = record.bundleID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = directory.appendingPathComponent(
            "uninstall-\(safeID)-\(formatter.string(from: record.date)).json"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Loads one record (used by Undo in M6).
    public static func load(from url: URL) throws -> UninstallRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UninstallRecord.self, from: try Data(contentsOf: url))
    }

    /// Lists uninstall logs, newest first. The file name encodes a sortable
    /// `yyyyMMdd-HHmmss` timestamp as its last 15 characters before ".json",
    /// which is what the sort uses — the bundle-ID portion of the name must
    /// not influence ordering.
    public static func recentLogs(
        limit: Int = 20,
        in directory: URL = UninstallLogger.logsDirectory()
    ) -> [URL] {
        func timestamp(_ url: URL) -> String {
            let name = url.lastPathComponent
            let base = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
            return String(base.suffix(15))
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "json"
                && $0.lastPathComponent.hasPrefix("uninstall-")
                && !((try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) }
            .sorted { timestamp($0) > timestamp($1) }
            .prefix(limit)
            .map { $0 }
    }
}