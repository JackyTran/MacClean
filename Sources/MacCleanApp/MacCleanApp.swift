import SwiftUI
import MacCleanCore

@main
struct MacCleanApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var settingsModel = AppSettingsModel()
    @State private var undoSummary: String?

    init() {
        #if DEBUG
        // UI-test hook (TASKS T6.6): the sandboxed test runner cannot create
        // a fixture app in the real ~/Applications, so the app makes its own.
        if let path = ProcessInfo.processInfo.environment[UITestFixture.pathKey] {
            UITestFixture.createAppBundle(at: URL(fileURLWithPath: path))
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(settingsModel)
                .alert("Undo Last Uninstall", isPresented: Binding(
                    get: { undoSummary != nil },
                    set: { if !$0 { undoSummary = nil } }
                )) {
                    Button("OK") { undoSummary = nil }
                } message: {
                    Text(undoSummary ?? "")
                }
                .task {
                    // Purge logs older than the retention setting on launch. (SRS FR-27)
                    SettingsStore.purgeOldLogs(settingsModel.settings)
                }
        }
        .windowToolbarStyle(.unified)
        // Best-effort restore of the most recent uninstall. (SRS FR-20)
        // (CommandMenu is no longer a Scene in the macOS 26 SDK, so it lives
        // in the commands modifier — still works on macOS 13 via WindowGroup.)
        .commands {
            CommandMenu("Uninstall Log") {
                Button("Undo Last Uninstall") { undoLast() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsModel)
        }
    }

    private func undoLast() {
        guard let record = UndoService.latestRecord() else { return }
        let results = UndoService.undo(record: record)
        let restored = results.filter(\.restored).count
        undoSummary = String(format: String(localized: "Restored %d of %d items from “%@”."), restored, results.count, record.appName)
    }
}