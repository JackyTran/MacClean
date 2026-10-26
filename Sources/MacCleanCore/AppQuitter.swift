import Foundation
import AppKit

/// Stops an app before uninstalling it. (SRS FR-15)
public enum AppQuitter {
    /// Politely quits the app with the given bundle id (SIGTERM via NSRunningApplication).
    /// Returns true if the app is not running, or quit within the timeout.
    public static func quit(bundleID: String, timeout: TimeInterval = 5) async -> Bool {
        guard !bundleID.isEmpty else { return true }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return true }

        running.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Force-quits (SIGKILL). Only called after the user explicitly confirms. (SRS FR-15)
    @discardableResult
    public static func forceQuit(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .forEach { $0.forceTerminate() }
        return true
    }
}