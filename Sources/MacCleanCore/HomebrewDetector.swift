import Foundation

/// Detects apps installed via Homebrew. (SRS FR-5)
public enum HomebrewDetector {
    /// Known Caskroom locations on both architectures.
    static let caskroomPaths = [
        "/opt/homebrew/Caskroom",   // Apple Silicon
        "/usr/local/Caskroom",      // Intel
    ]

    /// True if the app bundle lives inside a Homebrew Caskroom.
    public static func isInstalledByHomebrew(appPath: String) -> Bool {
        caskroomPaths.contains { appPath.hasPrefix($0 + "/") }
    }

    /// Returns the list of installed casks from `brew` if available (async, ~100 ms).
    /// Empty when brew is not installed — never throws, never blocks long.
    public static func installedCasks() async -> Set<String> {
        let brew = "/opt/homebrew/bin/brew"
        let brewIntel = "/usr/local/bin/brew"
        let path = FileManager.default.fileExists(atPath: brew) ? brew
            : (FileManager.default.fileExists(atPath: brewIntel) ? brewIntel : nil)
        guard let path else { return [] }

        let data = await runCommand(path, ["list", "--cask", "-1"])
        guard let data, let output = String(data: data, encoding: .utf8) else { return [] }
        return Set(output.split(separator: "\n").map(String.init))
    }

    private static func runCommand(_ launchPath: String, _ arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                process.standardError = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // Never hang on brew: terminate after 10 s.
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning { process.terminate() }
                }

                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? nil
                process.waitUntilExit()
                continuation.resume(returning: data)
            }
        }
    }
}