import Foundation
import MacCleanCore

@MainActor
final class AppModel: ObservableObject {
    @Published var installedApps: [InstalledApp] = []
    @Published var isScanning = false
    @Published var selectedAppID: InstalledApp.ID?
    /// Summary of the last uninstall, shown in an alert. (FR-17)
    @Published var uninstallSummary: String?

    var selectedApp: InstalledApp? {
        installedApps.first { $0.id == selectedAppID }
    }

    func refreshInstalledApps() async {
        isScanning = true
        defer { isScanning = false }
        installedApps = await AppScanner().scan()
        // Keep selection valid if the app is still installed.
        if let id = selectedAppID, !installedApps.contains(where: { $0.id == id }) {
            selectedAppID = nil
        }
    }
}