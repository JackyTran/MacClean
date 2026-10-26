import SwiftUI
import MacCleanCore

struct AppListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    enum SortOrder: String, CaseIterable, Identifiable { // FR-25
        case name, size, lastModified
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return String(localized: "Name")
            case .size: return String(localized: "Size")
            case .lastModified: return String(localized: "Last Modified")
            }
        }
    }

    private var filteredApps: [InstalledApp] {
        let apps = appModel.installedApps
        let matching = searchText.isEmpty
            ? apps
            : apps.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleID.localizedCaseInsensitiveContains(searchText)
            }
        switch sortOrder {
        case .name: return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: return matching.sorted { $0.sizeBytes > $1.sizeBytes }
        case .lastModified: return matching.sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .accessibilityIdentifier("app-sort-picker")

            List(selection: $appModel.selectedAppID) {
                Section {
                    ForEach(filteredApps) { app in
                        AppRowView(app: app)
                            .tag(app)
                    }
                } header: {
                    HStack {
                        Text("\(filteredApps.count) apps")
                        if appModel.isScanning {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .accessibilityIdentifier("app-list")
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search apps")
        }
        .overlay {
            if appModel.installedApps.isEmpty && !appModel.isScanning {
                EmptyStateView(
                    title: "No apps found",
                    systemImage: "square.grid.2x2",
                    message: "Add apps to /Applications and refresh."
                )
            }
        }
    }
}

private struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .lineLimit(1)
                    if app.isAppleProtected {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .help("Apple system app — cannot be uninstalled (SRS FR-4)")
                            .accessibilityLabel("Protected system app")
                    }
                    if app.isHomebrewInstalled {
                        Text("brew")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                            .help("Installed via Homebrew — prefer 'brew uninstall' (SRS FR-5)")
                            .accessibilityLabel("Installed via Homebrew")
                    }
                }
                Text(app.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                    .monospacedDigit()
                Text("v\(app.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.name), version \(app.version), \(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))\(app.isAppleProtected ? ", protected system app" : "")\(app.isHomebrewInstalled ? ", installed via Homebrew" : "")")
    }
}