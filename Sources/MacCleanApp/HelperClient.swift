import Foundation
import MacCleanCore

/// XPC client for the privileged helper. (SRS FR-14, T5.2)
final class HelperClient {
    private let machServiceName = "com.macclean.helper"

    /// The path prefixes the helper is allowed to delete within. Mirrors
    /// SafetyRules' default allow-list; the helper validates against it again.
    static var allowedPrefixes: [String] {
        let home = NSString(string: "~").expandingTildeInPath
        return [
            "/Library", "/Applications", "/usr/local",
            home + "/Library", home + "/Applications",
        ]
    }

    /// Deletes paths as root via the helper, delivering typed results.
    func delete(
        _ paths: [String],
        appBundlePath: String,
        completion: @escaping (Result<[DeletionResult], Error>) -> Void
    ) {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperDeleteProtocol.self)

        connection.resume()
        defer { connection.invalidate() }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            completion(.failure(error))
        }) as? HelperDeleteProtocol else {
            completion(.failure(HelperError.connectionFailed))
            return
        }

        proxy.delete(paths, appBundlePath: appBundlePath, allowedPathPrefixes: Self.allowedPrefixes) { payload in
            completion(.success(HelperResultParsing.parse(payload)))
        }
    }

    enum HelperError: LocalizedError {
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .connectionFailed:
                return "Could not connect to the privileged helper."
            }
        }
    }
}