import Foundation

/// Information about an installed application bundle. (SRS FR-2)
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let id: String        // bundle identifier, or path if missing
    public let name: String
    public let version: String
    public let bundleID: String
    public let path: URL
    public let sizeBytes: Int64
    public let lastModifiedDate: Date?
    public let isAppleProtected: Bool   // Apple system app — never removable (SRS FR-4)
    public let isHomebrewInstalled: Bool // Installed via Homebrew cask (SRS FR-5)

    public init(id: String = "",
                name: String,
                version: String,
                bundleID: String,
                path: URL,
                sizeBytes: Int64,
                lastModifiedDate: Date?,
                isAppleProtected: Bool,
                isHomebrewInstalled: Bool = false) {
        self.id = bundleID.isEmpty ? path.path : bundleID
        self.name = name
        self.version = version
        self.bundleID = bundleID
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastModifiedDate = lastModifiedDate
        self.isAppleProtected = isAppleProtected
        self.isHomebrewInstalled = isHomebrewInstalled
    }
}