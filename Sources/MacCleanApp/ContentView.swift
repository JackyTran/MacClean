import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            AppListView()
        } detail: {
            if let app = appModel.selectedApp {
                AppDetailView(app: app)
            } else {
                EmptyStateView(
                    title: "Select an app",
                    systemImage: "arrow.left",
                    message: "Choose an app on the left to see details."
                )
            }
        }
        .navigationTitle("MacClean")
        .frame(minWidth: 760, minHeight: 460)
        // The uninstall results live in the detail pane, which is replaced as
        // soon as the removed app leaves the list — so the summary is also
        // reported here, where it outlives the pane. (FR-17)
        .alert("Uninstall Finished", isPresented: Binding(
            get: { appModel.uninstallSummary != nil },
            set: { if !$0 { appModel.uninstallSummary = nil } }
        )) {
            Button("OK") { appModel.uninstallSummary = nil }
        } message: {
            Text(appModel.uninstallSummary ?? "")
        }
        .task {
            await appModel.refreshInstalledApps()
        }
    }
}