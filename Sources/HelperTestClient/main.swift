import Foundation
import MacCleanCore

// CLI client used by the M5 integration test (TASKS T5.5).
//
// Connects to the helper's mach service over XPC, issues one delete request, and
// prints one line per result: "<outcome> <path> [error]". Exits 0 when the
// helper replied at all (individual outcomes are judged by the test script).
//
// usage: HelperTestClient <appBundlePath> <path> [<path>…]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: HelperTestClient <appBundlePath> <path> [<path>…]\n       HelperTestClient --endpoint <file> <appBundlePath> <path> [<path>…]\n".data(using: .utf8)!)
    exit(2)
}

var appBundlePath: String
var paths: [String]
var connection: NSXPCConnection

if args[1] == "--endpoint" {
    // Test mode: connect via a shared listener endpoint file instead of launchd.
    guard args.count >= 4,
          let data = try? Data(contentsOf: URL(fileURLWithPath: args[2])),
          let endpoint = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSXPCListenerEndpoint.self, from: data) else {
        FileHandle.standardError.write("ERROR: could not read listener endpoint file\n".data(using: .utf8)!)
        exit(2)
    }
    appBundlePath = args[3]
    paths = Array(args.dropFirst(4))
    connection = NSXPCConnection(listenerEndpoint: endpoint)
} else {
    appBundlePath = args[1]
    paths = Array(args.dropFirst(2))
    connection = NSXPCConnection(machServiceName: "com.macclean.helper", options: [])
}

// Same allow-list the app's HelperClient sends; the helper re-validates anyway.
let home = NSString(string: "~").expandingTildeInPath
let allowedPrefixes = [
    "/Library", "/Applications", "/usr/local",
    home + "/Library", home + "/Applications",
]

// Fail-safe: never hang the test if the daemon is not registered.
DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
    FileHandle.standardError.write("ERROR: timed out waiting for the helper\n".data(using: .utf8)!)
    exit(1)
}

connection.remoteObjectInterface = NSXPCInterface(with: HelperDeleteProtocol.self)
connection.invalidationHandler = {
    FileHandle.standardError.write("DEBUG: connection invalidated\n".data(using: .utf8)!)
    exit(1)
}
connection.resume()
FileHandle.standardError.write("DEBUG: resumed\n".data(using: .utf8)!)

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    FileHandle.standardError.write("ERROR: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}

if let helperProxy = proxy as? HelperDeleteProtocol {
    FileHandle.standardError.write("DEBUG: proxy cast OK\n".data(using: .utf8)!)
    helperProxy.delete(
        paths, appBundlePath: appBundlePath, allowedPathPrefixes: allowedPrefixes
    ) { payload in
        for dict in payload {
            let path = dict["path"] as? String ?? "?"
            let outcome = dict["outcome"] as? String ?? "?"
            let error = dict["error"] as? String
            print("\(outcome) \(path)\(error.map { " (\($0))" } ?? "")")
        }
        exit(0)
    }
} else {
    FileHandle.standardError.write("ERROR: proxy cast failed\n".data(using: .utf8)!)
    exit(1)
}

RunLoop.main.run()