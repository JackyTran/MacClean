import SwiftUI
import Foundation
import MacCleanCore

/// Drives the full uninstall flow for one app: scan → review → confirm → delete → report. (SRS FR-9, FR-13, FR-17, FR-23)
@MainActor
final class UninstallFlow: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case review
        case confirming
        case deleting(progress: Int, total: Int)
        case done([DeletionResult])
    }

    @Published var phase: Phase = .idle
    @Published var items: [LeftoverItem] = []
    /// Selected paths (FR-9). Starts from each item's default selection.
    @Published var selected: Set<String> = []

    private let app: InstalledApp
    private let matcher: LeftoverMatcher
    private let launchScanner: LaunchItemsScanner
    private let deleter: Deleter
    /// Reads current settings at call time so preference changes apply immediately. (FR-27)
    private let settingsProvider: () -> AppSettings

    init(app: InstalledApp, settingsProvider: @escaping () -> AppSettings = { SettingsStore.load() }) {
        self.app = app
        self.matcher = LeftoverMatcher(app: app)
        self.launchScanner = LaunchItemsScanner(app: app)
        self.deleter = Deleter()
        self.settingsProvider = settingsProvider
    }

    var isSecureDelete: Bool { settingsProvider().secureDeleteEnabled }

    /// The bundle path of the *running* app (MacClean itself).
    ///
    /// This is the self-protection reference handed to `SafetyRules`: an app
    /// must never be able to delete its own bundle. It must NOT be the path of
    /// the app being uninstalled — doing so made the target bundle match the
    /// self-protection rule, so it was refused as "skipped (unsafe path)" and
    /// the app never actually left /Applications.
    private static var runningAppBundlePath: String { Bundle.main.bundlePath }

    /// True when the last run actually removed something.
    var didDeleteAnything: Bool {
        guard case .done(let results) = phase else { return false }
        return results.contains { $0.isSuccess }
    }

    /// One-line summary of the last run, for the confirmation alert. (FR-17)
    ///
    /// The results panel itself is torn down as soon as the app leaves the
    /// list (the selection clears), so the summary is also surfaced in an
    /// alert that outlives it.
    var lastRunSummary: String? {
        guard case .done(let results) = phase, !results.isEmpty else { return nil }
        let deleted = results.filter(\.isSuccess).count
        let failed = results.count - deleted
        if failed == 0 {
            return String(format: String(localized: "Moved %d of %d items to the Trash."),
                          deleted, results.count)
        }
        return String(format: String(localized: "Moved %d of %d items to the Trash; %d could not be removed."),
                      deleted, results.count, failed)
    }

    var selectedItems: [LeftoverItem] {
        items.filter { selected.contains($0.url.path) }
    }

    var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    func scan() async {
        phase = .scanning
        // Effective scan locations from settings (defaults − disabled + custom). (FR-27)
        let matched = await matcher.scan(locations: settingsProvider().scanLocations())
        let launch = await launchScanner.scan()
        items = matched + launch
        selected = Set(items.filter(\.isSelected).map(\.url.path))
        phase = .review
    }

    func confirm() {
        phase = .confirming
    }

    /// Runs the uninstall: quit app, delete bundle + selected leftovers to Trash, log everything. (SRS FR-13, FR-15, FR-19)
    func performDeletion() async {
        // Stop the app first (FR-15). If it won't quit, abort and tell the user.
        let quit = await AppQuitter.quit(bundleID: app.bundleID)
        guard quit else {
            phase = .done([])
            return
        }

        let mode: Deleter.Mode = settingsProvider().secureDeleteEnabled ? .secure : .trash
        let paths = [app.path.path] + selectedItems.map(\.url.path)
        let results = await deleter.delete(
            paths, mode: mode, appBundlePath: Self.runningAppBundlePath
        ) { done, total in
            Task { @MainActor in
                self.phase = .deleting(progress: done, total: total)
            }
        }

        // Uninstall log (FR-19): every path with its outcome.
        let kindByPath: [String: String] = {
            var map: [String: String] = [app.path.path: "appBundle"]
            for item in items { map[item.url.path] = item.kind.rawValue }
            return map
        }()
        let sizeByPath: [String: Int64] = {
            var map: [String: Int64] = [app.path.path: app.sizeBytes]
            for item in items { map[item.url.path] = item.sizeBytes }
            return map
        }()
        let itemRecords = zip(paths, results).map { path, result in
            UninstallRecord.ItemRecord(
                path: path,
                kind: kindByPath[path] ?? "other",
                sizeBytes: sizeByPath[path] ?? 0,
                outcome: result.outcome.rawValue
            )
        }
        let record = UninstallRecord(
            app: app, date: Date(), mode: mode == .secure ? "secure" : "trash", items: itemRecords
        )
        try? UninstallLogger.write(record)

        phase = .done(results)
    }

    /// Paths from the last run that failed for permission reasons (not unsafe skips).
    private var helperRetryPaths: [String] {
        guard case .done(let results) = phase else { return [] }
        return results.filter { $0.outcome == .failed }.map(\.path)
    }

    /// Retries permission-failed deletions via the privileged helper. (SRS FR-14)
    /// Registers the daemon first if needed (shows the system admin prompt).
    func retryWithHelper() async {
        let paths = helperRetryPaths
        guard !paths.isEmpty else { return }
        phase = .deleting(progress: 0, total: paths.count)

        do {
            if !HelperInstaller.isRegistered {
                try HelperInstaller.register()
            }
        } catch {
            phase = .done([]) // UI shows the "could not complete" state
            return
        }

        let client = HelperClient()
        let helperResults: [DeletionResult] = await withCheckedContinuation { continuation in
            client.delete(paths, appBundlePath: Self.runningAppBundlePath) { result in
                switch result {
                case .success(let results):
                    continuation.resume(returning: results)
                case .failure(let error):
                    let failed = paths.map {
                        DeletionResult(path: $0, outcome: .failed, errorMessage: error.localizedDescription)
                    }
                    continuation.resume(returning: failed)
                }
            }
        }

        // Merge: replace failed entries with helper outcomes, keep successes.
        guard case .done(let previous) = phase else { return }
        var byPath: [String: DeletionResult] = [:]
        for result in previous where result.isSuccess {
            byPath[result.path] = result
        }
        for result in helperResults {
            byPath[result.path] = result
        }

        // Log the helper pass too. (FR-19)
        let record = UninstallRecord(
            app: app,
            date: Date(),
            mode: "trash+helper",
            items: helperResults.map {
                UninstallRecord.ItemRecord(
                    path: $0.path, kind: "helper", sizeBytes: 0, outcome: $0.outcome.rawValue
                )
            }
        )
        try? UninstallLogger.write(record)

        phase = .done(Array(byPath.values))
    }

    func reset() {
        phase = .idle
        items = []
        selected = []
    }
}

struct UninstallFlowView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var flow: UninstallFlow
    @State private var secureAcknowledged = false

    init(app: InstalledApp, settingsProvider: @escaping () -> AppSettings = { SettingsStore.load() }) {
        _flow = StateObject(wrappedValue: UninstallFlow(app: app, settingsProvider: settingsProvider))
    }

    var body: some View {
        Group {
            switch flow.phase {
            case .idle:
                scanButton
            case .scanning:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Scanning for leftovers…")
                        .foregroundStyle(.secondary)
                }
            case .review:
                reviewList
            case .confirming:
                confirmation
            case .deleting(let done, let total):
                VStack(spacing: 8) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                    Text("Deleting \(done) of \(total)…")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding()
            case .done(let results):
                resultsView(results)
            }
        }
    }

    private var scanButton: some View {
        Button {
            Task { await flow.scan() }
        } label: {
            Label("Scan for leftover files", systemImage: "magnifyingglass")
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    private var reviewList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if flow.items.isEmpty {
                Text("No leftover files found.")
                    .foregroundStyle(.secondary)
            } else {
                Table(flow.items) {
                    TableColumn("") { item in
                        Toggle("", isOn: Binding(
                            get: { flow.selected.contains(item.url.path) },
                            set: { on in
                                if on { flow.selected.insert(item.url.path) }
                                else { flow.selected.remove(item.url.path) }
                            }
                        ))
                        .labelsHidden()
                    }
                    TableColumn("Kind") { item in
                        Text(item.kind.displayName)
                            .foregroundStyle(item.isSelected ? .primary : .secondary)
                    }
                    TableColumn("File") { item in
                        Text(item.url.path)
                            .font(.system(.body, design: .monospaced))
                            .truncationMode(.middle)
                            .help(item.url.path)
                    }
                    TableColumn("Size") { item in
                        Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                            .monospacedDigit()
                    }
                }
                .tableStyle(.inset)
            }

            HStack {
                Text("Recoverable: \(ByteCountFormatter.string(fromByteCount: flow.selectedSize, countStyle: .file))")
                    .monospacedDigit()
                Spacer()
                Button("Rescan") { Task { await flow.scan() } }
                Button("Uninstall…", action: flow.confirm)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 12) {
            Label(
                flow.isSecureDelete
                    ? "Delete these items permanently?"
                    : "Move these items to the Trash?",
                systemImage: flow.isSecureDelete ? "flame" : "trash"
            )
            .font(.title3.weight(.semibold))

            let allPaths = [flow.selectedItems.map(\.url.path)].flatMap { $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allPaths, id: \.self) { path in
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)

            if flow.isSecureDelete {
                // Extra confirmation required for permanent deletion. (FR-16)
                Toggle("I understand this permanently deletes the items", isOn: $secureAcknowledged)
                    .accessibilityIdentifier("confirm-secure-acknowledge")
                Text("Total: \(ByteCountFormatter.string(fromByteCount: flow.selectedSize, countStyle: .file)) — NOT recoverable.")
                    .foregroundStyle(.orange)
            } else {
                Text("Total: \(ByteCountFormatter.string(fromByteCount: flow.selectedSize, countStyle: .file)) — recoverable from the Trash.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", role: .cancel) { flow.phase = .review }
                Button(flow.isSecureDelete ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                    Task {
                        await flow.performDeletion()
                        // The sidebar list is a snapshot taken when the window
                        // opened, so the app we just removed would sit in it
                        // until the next launch. Rescan so it disappears. (FR-2)
                        if flow.didDeleteAnything {
                            appModel.uninstallSummary = flow.lastRunSummary
                            await appModel.refreshInstalledApps()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(flow.isSecureDelete && !secureAcknowledged)
                .accessibilityIdentifier("confirm-delete-button")
            }
        }
        .padding()
        .onAppear { secureAcknowledged = false }
    }

    @ViewBuilder
    private func resultsView(_ results: [DeletionResult]) -> some View {
        VStack(spacing: 10) {
            if results.isEmpty {
                Label("The app could not be quit — nothing was deleted.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Back") { flow.reset() }
            } else {
                let deleted = results.filter(\.isSuccess)
                let failed = results.filter { !$0.isSuccess }
                Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(failed.isEmpty ? .green : .orange)
                Text("\(deleted.count) of \(results.count) items moved to Trash")
                    .font(.title3.weight(.semibold))

                if !failed.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failed, id: \.path) { result in
                            Text("• \(result.path): \(result.outcome == .skippedUnsafe ? "skipped (unsafe path)" : result.errorMessage ?? "failed")")
                                .font(.system(.caption, design: .monospaced))
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Permission failures can be retried as root via the helper. (FR-14)
                    if failed.contains(where: { $0.outcome == .failed }) {
                        Button {
                            Task { await flow.retryWithHelper() }
                        } label: {
                            Label("Retry with privileged helper…", systemImage: "key.horizontal")
                        }
                        .help("Installs the signed helper daemon and retries the failed deletions as root (admin password required).")
                    }
                }

                Button("Done") { flow.reset() }
            }
        }
        .padding()
    }
}