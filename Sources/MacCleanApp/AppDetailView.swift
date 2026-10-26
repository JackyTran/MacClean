import SwiftUI
import MacCleanCore

struct AppDetailView: View {
    @EnvironmentObject private var settingsModel: AppSettingsModel
    let app: InstalledApp

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: app.name)
                LabeledContent("Version", value: app.version)
                LabeledContent("Bundle ID", value: app.bundleID.isEmpty ? "—" : app.bundleID)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                LabeledContent("Last Modified", value: app.lastModifiedDate.map(Self.dateFormatter.string(from:)) ?? "—")
                LabeledContent("Location", value: app.path.path)
                LabeledContent("Apple Protected", value: app.isAppleProtected ? "Yes — cannot be uninstalled" : "No")
                LabeledContent("Homebrew", value: app.isHomebrewInstalled ? "Installed via cask" : "—")
            } header: {
                Text("Application")
            }
            Section {
                if app.isAppleProtected {
                    Label("This is an Apple system app and cannot be uninstalled.", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                } else {
                    // Re-create the flow when the selection changes: @StateObject
                    // keeps the first app's flow otherwise, so switching apps would
                    // show (and rescan) the stale app's leftovers.
                    UninstallFlowView(app: app, settingsProvider: { [settingsModel] in settingsModel.settings })
                        .id(app.path)
                }
            } header: {
                Text("Uninstall")
            }
        }
        .formStyle(.grouped)
        .navigationSubtitle(app.name)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}