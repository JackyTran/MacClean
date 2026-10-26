import Foundation

/// Best-effort restore of an uninstalled app's items from the Trash. (SRS FR-20)
///
/// "Best effort" is the contract: the Trash may have been emptied, items may
/// have been renamed on name collisions, or the parent folder may no longer
/// exist. Every item reports its own outcome.
public enum UndoService {
    public struct UndoResult: Equatable, Sendable {
        public let originalPath: String
        public let restored: Bool
        public let message: String
    }

    /// Restores the deleted items of one uninstall record.
    /// `trashDirectory` is injectable for tests.
    @discardableResult
    public static func undo(
        record: UninstallRecord,
        trashDirectory: URL = URL(fileURLWithPath: NSString(string: "~").expandingTildeInPath + "/.Trash")
    ) -> [UndoResult] {
        record.items
            .filter { $0.outcome == DeletionResult.Outcome.deleted.rawValue }
            .map { restore(item: $0, trashDirectory: trashDirectory) }
    }

    static func restore(item: UninstallRecord.ItemRecord, trashDirectory: URL) -> UndoResult {
        // The Trash item keeps the file name of the deleted path.
        let fileName = (item.path as NSString).lastPathComponent
        let trashURL = trashDirectory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: trashURL.path) else {
            return UndoResult(
                originalPath: item.path, restored: false,
                message: String(localized: "Not found in the Trash (it may have been emptied).")
            )
        }

        let destination = URL(fileURLWithPath: item.path)
        do {
            // Recreate the original parent folder if it went with the item.
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: trashURL, to: destination)
            return UndoResult(originalPath: item.path, restored: true, message: String(localized: "Restored."))
        } catch {
            return UndoResult(
                originalPath: item.path, restored: false,
                message: error.localizedDescription
            )
        }
    }

    /// The most recent uninstall record, if any. (SRS FR-19, FR-20)
    public static func latestRecord(
        in directory: URL = UninstallLogger.logsDirectory()
    ) -> UninstallRecord? {
        UninstallLogger.recentLogs(limit: 1, in: directory).first.flatMap { try? UninstallLogger.load(from: $0) }
    }
}