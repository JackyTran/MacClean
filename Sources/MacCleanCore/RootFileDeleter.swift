import Foundation

/// Deletes a single path the way the privileged helper does: Trash first,
/// permanent delete as fallback. (SRS T5.4)
///
/// This lives in Core (not the helper target) so the exact code the XPC handler
/// runs is unit-testable; the helper's HelperService calls this directly.
public enum RootFileDeleter {
    /// Moves the URL to the current user's Trash and returns the resulting URL.
    /// Exposed for tests so they can prove Trash-first behavior (SRS FR-18)
    /// without listing ~/.Trash (blocked by TCC for test runners).
    @discardableResult
    public static func trash(_ url: URL) throws -> URL {
        var resultingItemURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingItemURL)
        return resultingItemURL.map { $0 as URL } ?? url
    }

    /// Trash where feasible, otherwise permanent delete — but only for paths that
    /// already passed the SafetyRules gate (the caller validates first).
    public static func delete(_ path: String) -> DeletionResult {
        let url = URL(fileURLWithPath: path)
        do {
            _ = try trash(url)
            return DeletionResult(path: path, outcome: .deleted)
        } catch {
            // Trash failed (e.g. cross-volume): permanent delete is the fallback,
            // acceptable only because the path passed the SafetyRules gate.
            do {
                try FileManager.default.removeItem(at: url)
                return DeletionResult(path: path, outcome: .deleted)
            } catch {
                return DeletionResult(
                    path: path, outcome: .failed, errorMessage: error.localizedDescription
                )
            }
        }
    }
}