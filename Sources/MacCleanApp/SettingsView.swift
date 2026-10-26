import SwiftUI
import MacCleanCore

/// Settings pane (⌘,): deletion mode, scan locations, custom folders, log retention. (SRS FR-27)
struct SettingsView: View {
    @EnvironmentObject private var settingsModel: AppSettingsModel

    var body: some View {
        Form {
            deletionSection
            scanLocationsSection
            customFoldersSection
            logRetentionSection
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }

    private var deletionSection: some View {
        Section {
            Toggle("Delete permanently instead of moving to Trash", isOn: Binding(
                get: { settingsModel.settings.secureDeleteEnabled },
                set: { value in settingsModel.update { $0.secureDeleteEnabled = value } }
            ))
            .accessibilityIdentifier("setting-secure-delete")
            if settingsModel.settings.secureDeleteEnabled {
                Label(
                    "Permanent deletion cannot be undone. Every uninstall will ask twice.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Deletion")
        } footer: {
            Text("By default, uninstalled items go to the Trash and can be restored with Undo Last Uninstall.")
        }
    }

    private var scanLocationsSection: some View {
        Section("Scan locations") {
            ForEach(ScanLocations.all(), id: \.url) { location in
                Toggle(location.url.path, isOn: Binding(
                    get: { settingsModel.isLocationEnabled(location) },
                    set: { settingsModel.setLocation(location, enabled: $0) }
                ))
                .font(.system(.body, design: .monospaced))
                .help(location.kind.displayName)
            }
        }
    }

    private var customFoldersSection: some View {
        Section {
            ForEach(settingsModel.settings.customScanFolders, id: \.self) { folder in
                HStack {
                    Text(folder)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        settingsModel.removeCustomFolder(folder)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove custom folder \(folder)")
                }
            }
            AddFolderRow { path in
                settingsModel.addCustomFolder(path)
            }
        } header: {
            Text("Custom scan folders")
        } footer: {
            Text("Additional folders scanned for leftover files. They are subject to the same safety rules.")
        }
    }

    private var logRetentionSection: some View {
        Section("Uninstall logs") {
            Stepper(
                "Keep logs for \(settingsModel.settings.logRetentionDays) days",
                value: Binding(
                    get: { settingsModel.settings.logRetentionDays },
                    set: { days in settingsModel.update { $0.logRetentionDays = max(1, min(365, days)) } }
                ),
                in: 1...365
            )
            .accessibilityIdentifier("setting-log-retention")
        }
    }
}

/// A path field with an Add button; commits on Return or Add.
private struct AddFolderRow: View {
    let onAdd: (String) -> Void
    @State private var path = ""

    var body: some View {
        HStack {
            TextField("/path/to/folder", text: $path)
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("setting-custom-folder-field")
            Button("Add") {
                onAdd(path)
                path = ""
            }
            .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}