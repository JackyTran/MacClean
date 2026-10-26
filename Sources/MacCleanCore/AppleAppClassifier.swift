import Foundation

/// Classifies apps that Apple ships and that must never be removable. (SRS FR-4)
public enum AppleAppClassifier {
    /// True if the app is Apple-provided and must be non-removable.
    ///
    /// Protects everything under `/System` (modern sealed-system location) and any
    /// app whose bundle id belongs to Apple, wherever it lives — deleting Apple
    /// components is out of scope for this tool by design.
    public static func isProtected(path: String, bundleID: String) -> Bool {
        if path.hasPrefix("/System/") || path == "/System" { return true }
        if bundleID.hasPrefix("com.apple.") { return true }
        return false
    }
}