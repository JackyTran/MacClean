import Foundation
import AppKit

/// Outcome of deleting a single path. (SRS FR-17, NFR-10)
public struct DeletionResult: Sendable, Hashable, Codable {
    public enum Outcome: String, Sendable, Codable {
        case deleted
        case failed
        case skippedUnsafe   // failed the SafetyRules gate — never touched
    }

    public let path: String
    public let outcome: Outcome
    public let errorMessage: String?

    public var isSuccess: Bool { outcome == .deleted }

    public init(path: String, outcome: Outcome, errorMessage: String? = nil) {
        self.path = path
        self.outcome = outcome
        self.errorMessage = errorMessage
    }
}

/// Deletes paths to the Trash (default) or permanently, per-item. (SRS FR-13, FR-16, FR-18, FR-21, NFR-10)
///
/// Every path is validated against `SafetyRules` **here**, immediately before the
/// delete — no caller can bypass the gate. One failing item never aborts the batch.
public struct Deleter: Sendable {
    public enum Mode: String, Sendable {
        case trash       // recoverable (SRS FR-18)
        case secure      // permanent; UI must double-confirm (SRS FR-16)
    }

    /// Performs the actual removal for one path. Injectable for tests.
    /// Real implementation: Trash via NSWorkspace, or `FileManager.removeItem`.
    public typealias RemoveHandler = @Sendable (URL, Mode) throws -> Void

    private let remove: RemoveHandler

    public init() {
        self.remove = { url, mode in
            switch mode {
            case .trash:
                try Self.recycleToTrash(url)
            case .secure:
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Test initializer with an injectable handler.
    public init(removeHandler: @escaping RemoveHandler) {
        self.remove = removeHandler
    }

    public func delete(
        _ paths: [String],
        mode: Mode,
        appBundlePath: String,
        allowedPathPrefixes: [String]? = nil,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [DeletionResult] {
        var results: [DeletionResult] = []
        for (index, path) in paths.enumerated() {
            if Task.isCancelled { break }

            // When a custom allow-list is given (tests, helper), it replaces the
            // default one; the forbidden prefixes and self-protection still apply.
            let isDeletable: Bool
            if let allowedPathPrefixes {
                isDeletable = SafetyRules.isDeletable(
                    path, appBundlePath: appBundlePath, allowedPrefixes: allowedPathPrefixes
                )
            } else {
                isDeletable = SafetyRules.isDeletable(path, appBundlePath: appBundlePath)
            }
            guard isDeletable else {
                results.append(DeletionResult(path: path, outcome: .skippedUnsafe))
                progress?(index + 1, paths.count)
                continue
            }

            do {
                try remove(URL(fileURLWithPath: path), mode)
                results.append(DeletionResult(path: path, outcome: .deleted))
            } catch {
                results.append(DeletionResult(path: path, outcome: .failed, errorMessage: error.localizedDescription))
            }
            progress?(index + 1, paths.count)
        }
        return results
    }

    /// Moves one URL to the user's Trash via NSWorkspace. (SRS FR-18)
    static func recycleToTrash(_ url: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var thrown: Error?
        NSWorkspace.shared.recycle([url]) { _, error in
            thrown = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        if let thrown { throw thrown }
    }
}