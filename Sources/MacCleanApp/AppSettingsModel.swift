import SwiftUI
import MacCleanCore

/// Observable wrapper over Core's persisted AppSettings. (SRS FR-27, FR-28)
@MainActor
final class AppSettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings

    init() {
        self.settings = SettingsStore.load()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        SettingsStore.save(next)
        objectWillChange.send()
    }

    var isLocationEnabled: (ScanLocation) -> Bool {
        { [settings] location in !settings.disabledLocationPaths.contains(location.url.path) }
    }

    func setLocation(_ location: ScanLocation, enabled: Bool) {
        update { s in
            if enabled {
                s.disabledLocationPaths.remove(location.url.path)
            } else {
                s.disabledLocationPaths.insert(location.url.path)
            }
        }
    }

    func addCustomFolder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { s in
            guard !s.customScanFolders.contains(trimmed) else { return }
            s.customScanFolders.append(trimmed)
        }
    }

    func removeCustomFolder(_ path: String) {
        update { s in
            s.customScanFolders.removeAll { $0 == path }
        }
    }
}