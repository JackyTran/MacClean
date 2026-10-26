import Foundation

/// XPC protocol between the app and the privileged helper. (SRS FR-14)
///
/// Plain property-list types only (XPC/objc bridging). Results are dictionaries
/// of {path, outcome, error}, parsed back into `DeletionResult` on the app side.
@objc public protocol HelperDeleteProtocol {
    /// Deletes the given paths as root. The helper re-validates every path against
    /// SafetyRules *itself* before touching anything. (SRS NFR-7)
    func delete(_ paths: [String],
                appBundlePath: String,
                allowedPathPrefixes: [String],
                reply: @escaping ([[String: Any]]) -> Void)

    /// Helper version, for handshake/debugging.
    func version(reply: @escaping (String) -> Void)
}

/// Splits requested paths into valid / rejected using SafetyRules. (SRS NFR-7, T5.2)
/// Runs helper-side — the app's say-so is never trusted on its own.
public enum HelperRequestValidator {
    public static func split(
        paths: [String],
        appBundlePath: String,
        allowedPathPrefixes: [String]
    ) -> (valid: [String], rejected: [String]) {
        var valid: [String] = []
        var rejected: [String] = []
        for path in paths {
            if SafetyRules.isDeletable(
                path, appBundlePath: appBundlePath, allowedPrefixes: allowedPathPrefixes
            ) {
                valid.append(path)
            } else {
                rejected.append(path)
            }
        }
        return (valid, rejected)
    }
}

/// Converts helper XPC payload dictionaries back into typed results.
public enum HelperResultParsing {
    public static func parse(_ payload: [[String: Any]]) -> [DeletionResult] {
        payload.compactMap { dict in
            guard let path = dict["path"] as? String,
                  let outcomeRaw = dict["outcome"] as? String,
                  let outcome = DeletionResult.Outcome(rawValue: outcomeRaw) else { return nil }
            let errorMessage = dict["error"] as? String
            return DeletionResult(path: path, outcome: outcome, errorMessage: errorMessage)
        }
    }

    /// Serializes results into the XPC payload shape (helper → app direction uses
    /// this only in tests; the helper builds the dictionaries itself).
    public static func serialize(_ results: [DeletionResult]) -> [[String: Any]] {
        results.map { result in
            var dict: [String: Any] = [
                "path": result.path,
                "outcome": result.outcome.rawValue,
            ]
            if let errorMessage = result.errorMessage {
                dict["error"] = errorMessage
            }
            return dict
        }
    }
}