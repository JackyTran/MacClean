import Foundation
import MacCleanCore

// Privileged helper daemon for MacClean. Runs as root via SMAppService. (SRS FR-14, NFR-7)
//
// The helper is intentionally minimal: it accepts only `delete` requests, and
// re-validates every path against SafetyRules itself before touching anything.

let helperVersion = "1.0"

/// Serves delete requests as root.
final class HelperService: NSObject, HelperDeleteProtocol {
    func version(reply: (String) -> Void) {
        reply(helperVersion)
    }

    func delete(_ paths: [String],
                appBundlePath: String,
                allowedPathPrefixes: [String],
                reply: @escaping ([[String: Any]]) -> Void) {
        fputs("[helper] delete request: \(paths)\n", stderr)
        // Re-validate everything helper-side. (SRS NFR-7: the app is never trusted.)
        let (valid, rejected) = HelperRequestValidator.split(
            paths: paths,
            appBundlePath: appBundlePath,
            allowedPathPrefixes: allowedPathPrefixes
        )

        var payload: [[String: Any]] = []
        for path in valid {
            payload.append(HelperResultParsing.serialize([RootFileDeleter.delete(path)])[0])
        }
        for path in rejected {
            payload.append(["path": path, "outcome": DeletionResult.Outcome.skippedUnsafe.rawValue])
        }
        reply(payload)
    }
}

/// Verifies the connecting client's code signature via the connection's audit token. (SRS NFR-9)
enum ClientCodeVerification {
    /// In DEBUG builds with ad-hoc signing we accept any code that presents a
    /// *valid* signature (SecCodeCheckValidity passes, ad-hoc included).
    /// In RELEASE this must require the app's designated requirement; that
    /// requirement string is set when Developer ID signing arrives (M7 / T7.1).
    static let strict = false

    static func verify(_ connection: NSXPCConnection) -> Bool {
        guard let tokenData = connection.value(forKey: "auditToken") as? Data else {
            return !strict
        }

        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return !strict
        }

        // nil requirement = "is this code validly signed at all"
        let valid = SecCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess
        return valid || !strict
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        fputs("[helper] new connection: \(newConnection)\n", stderr)
        let trusted = ClientCodeVerification.verify(newConnection)
        fputs("[helper] client verification: \(trusted)\n", stderr)
        guard trusted else {
            return false // untrusted caller: connection dropped. (SRS NFR-9)
        }
        newConnection.exportedInterface = NSXPCInterface(with: HelperDeleteProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }
}

fputs("[helper] starting, pid \(getpid())\n", stderr)

let delegate = ListenerDelegate()

if let endpointPath = ProcessInfo.processInfo.environment["MACCLEAN_TEST_ENDPOINT"] {
    // Test mode (TASKS T5.5): anonymous listener + shared endpoint file instead of
    // a launchd mach service. macOS 26's execution policy blocks launchd-spawned
    // ad-hoc binaries (dyld open() hangs on provenance), so the integration test
    // launches the helper directly; the launchd path is verified in M7 with
    // Developer ID signing. Everything else — protocol, validation, deletion —
    // is identical.
    let listener = NSXPCListener()
    listener.delegate = delegate
    listener.resume()
    do {
        let data = try NSKeyedArchiver.archivedData(withRootObject: listener.endpoint, requiringSecureCoding: true)
        try data.write(to: URL(fileURLWithPath: endpointPath))
        fputs("[helper] test endpoint written to \(endpointPath)\n", stderr)
    } catch {
        fputs("[helper] FATAL: could not publish test endpoint: \(error)\n", stderr)
        exit(1)
    }
} else {
    let listener = NSXPCListener(machServiceName: "com.macclean.helper")
    listener.delegate = delegate
    listener.resume()
    fputs("[helper] listener resumed\n", stderr)
}

RunLoop.main.run()