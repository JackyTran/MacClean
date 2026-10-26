import Foundation

/// One leftover file/folder found on disk. (SRS FR-7)
public struct LeftoverItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case cache, log, preference, applicationSupport
        case container, groupContainer, savedState, webKit, httpStorage
        case launchAgent, launchDaemon
        case other

        /// Pre-selected by default: caches and logs (SRS FR-7); everything else
        /// the user must opt in to.
        public var isDefaultSelected: Bool {
            switch self {
            case .cache, .log: return true
            default: return false
            }
        }

        public var displayName: String {
            switch self {
            case .cache: return "Cache"
            case .log: return "Log"
            case .preference: return "Preference"
            case .applicationSupport: return "Application Support"
            case .container: return "Container"
            case .groupContainer: return "Group Container"
            case .savedState: return "Saved State"
            case .webKit: return "WebKit Data"
            case .httpStorage: return "HTTP Storage"
            case .launchAgent: return "Launch Agent"
            case .launchDaemon: return "Launch Daemon"
            case .other: return "Other"
            }
        }
    }

    public var id: String { url.path }
    public let url: URL
    public let kind: Kind
    public let sizeBytes: Int64
    public let isSelected: Bool   // default selection state (SRS FR-9 initial state)

    public init(url: URL, kind: Kind, sizeBytes: Int64, isSelected: Bool? = nil) {
        self.url = url
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected ?? kind.isDefaultSelected
    }
}