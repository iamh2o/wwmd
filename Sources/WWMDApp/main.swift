import AppKit
import Combine
import Foundation
import SwiftUI
import WWMDAgentRuntime
import WWMDCore
import WWMDIPC
import WWMDStorage

private enum WWMDWindowID {
    static let main = "wwmd-main"
}

private struct LocalHealth: Equatable, Sendable {
    let schemaVersion: Int
    let eventCount: Int
    let quickCheckPassed: Bool
    let globallyPaused: Bool
}

private struct OpenedLocalRuntime: @unchecked Sendable {
    let databasePath: String
    let lease: DatabaseLease
    let runtime: WWMDAgentRuntime
    let health: StoreHealth
    let collection: CollectionState
}

@MainActor
private final class LocalRuntimeModel: ObservableObject {
    private enum State: Equatable {
        case databaseRequired
        case opening
        case active
        case unavailable(String)
    }

    @Published private(set) var health: LocalHealth?
    @Published private(set) var summary: XPCSummaryResponse?
    @Published private(set) var recommendations: [XPCRecommendationItem] = []
    @Published private(set) var dashboardMessage: String?
    @Published private(set) var isLoadingDashboard = false
    @Published private(set) var isMutating = false
    @Published private var state: State = .databaseRequired

    private var runtime: WWMDAgentRuntime?
    private var lease: DatabaseLease?
    private var activeDatabasePath: String?
    private var operationID = UUID()
    private var dashboardOperationID = UUID()

    var statusTitle: String {
        switch state {
        case .databaseRequired:
            "Local database required"
        case .opening:
            "Opening local database"
        case .active:
            health?.globallyPaused == true ? "Collection paused" : "Local runtime active"
        case .unavailable:
            "Local runtime unavailable"
        }
    }

    var statusDetail: String {
        switch state {
        case .databaseRequired:
            return "Enter one absolute database file path, then explicitly open it. WWMD does not infer a path or start a separate service."
        case .opening:
            return "WWMD is acquiring the exclusive local runtime lease and checking the selected database."
        case .active:
            guard let health else { return "The local runtime returned no health state." }
            return "Schema \(health.schemaVersion), \(health.eventCount) events, database check \(health.quickCheckPassed ? "passed" : "failed")."
        case .unavailable(let message):
            return message
        }
    }

    var isOpening: Bool { state == .opening }
    var isActive: Bool { runtime != nil && health != nil && state == .active }
    var canControlCollection: Bool { isActive && !isMutating }
    var currentDatabasePath: String? { activeDatabasePath }

    func open(databasePath rawPath: String) {
        let path = URL(fileURLWithPath: rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL.path
        guard path.hasPrefix("/"), path != "/" else {
            becomeUnavailable("The database path must be an absolute file path.")
            return
        }

        closeRuntime()
        let currentOperationID = UUID()
        operationID = currentOperationID
        state = .opening

        Task { [currentOperationID, path] in
            do {
                let opened = try await Task.detached(priority: .userInitiated) { () throws -> OpenedLocalRuntime in
                    let lease = try DatabaseLease(databasePath: path)
                    let store = try TelemetryStore(path: lease.databasePath)
                    let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
                    let health = try await runtime.health()
                    let collection = try await runtime.collectionState()
                    return OpenedLocalRuntime(
                        databasePath: lease.databasePath,
                        lease: lease,
                        runtime: runtime,
                        health: health,
                        collection: collection
                    )
                }.value
                guard self.operationID == currentOperationID else { return }
                self.runtime = opened.runtime
                self.lease = opened.lease
                self.activeDatabasePath = opened.databasePath
                self.health = Self.localHealth(opened.health, collection: opened.collection)
                self.state = .active
            } catch {
                guard self.operationID == currentOperationID else { return }
                self.becomeUnavailable(error.localizedDescription)
            }
        }
    }

    func close() {
        operationID = UUID()
        dashboardOperationID = UUID()
        closeRuntime()
        state = .databaseRequired
    }

    func refresh() {
        guard let runtime else {
            state = .databaseRequired
            return
        }
        let currentOperationID = UUID()
        operationID = currentOperationID
        state = .opening
        Task { [currentOperationID, runtime] in
            do {
                let result = try await Self.readHealth(runtime: runtime)
                guard self.operationID == currentOperationID else { return }
                self.health = result
                self.state = .active
            } catch {
                guard self.operationID == currentOperationID else { return }
                self.becomeUnavailable(error.localizedDescription)
            }
        }
    }

    func setCollectionPaused(_ paused: Bool) {
        guard let runtime, health != nil else {
            state = .databaseRequired
            return
        }
        let currentOperationID = UUID()
        operationID = currentOperationID
        isMutating = true
        Task { [currentOperationID, runtime] in
            do {
                _ = try await runtime.setCollectionState(paused)
                let refreshed = try await Self.readHealth(runtime: runtime)
                guard self.operationID == currentOperationID else { return }
                self.health = refreshed
                self.isMutating = false
                self.state = .active
            } catch {
                guard self.operationID == currentOperationID else { return }
                self.isMutating = false
                self.becomeUnavailable(error.localizedDescription)
            }
        }
    }

    func loadDashboard(from: Date, to: Date) {
        guard let runtime, health != nil else {
            dashboardMessage = "Open the selected local database before loading a summary."
            return
        }
        let query = SummaryQuery(from: from, to: to, metricNames: [])
        let recommendationScope = XPCScopedQuery(from: from, to: to)
        do {
            try XPCContractValidator.validate(query)
            try XPCContractValidator.validateScope(recommendationScope)
        } catch {
            dashboardMessage = error.localizedDescription
            return
        }
        let currentOperationID = UUID()
        dashboardOperationID = currentOperationID
        isLoadingDashboard = true
        dashboardMessage = nil
        Task { [currentOperationID, runtime, query, recommendationScope] in
            do {
                async let summary = runtime.summary(query: query)
                async let recommendations = runtime.recommendations(query: recommendationScope)
                let result = try await (summary, recommendations)
                guard self.dashboardOperationID == currentOperationID else { return }
                self.summary = result.0
                self.recommendations = result.1.items
                self.isLoadingDashboard = false
            } catch {
                guard self.dashboardOperationID == currentOperationID else { return }
                self.summary = nil
                self.recommendations = []
                self.dashboardMessage = error.localizedDescription
                self.isLoadingDashboard = false
            }
        }
    }

    private func closeRuntime() {
        runtime = nil
        lease = nil
        activeDatabasePath = nil
        health = nil
        summary = nil
        recommendations = []
        dashboardMessage = nil
        isLoadingDashboard = false
        isMutating = false
    }

    private func becomeUnavailable(_ message: String) {
        closeRuntime()
        state = .unavailable(message)
        dashboardMessage = message
    }

    private static func readHealth(runtime: WWMDAgentRuntime) async throws -> LocalHealth {
        let health = try await runtime.health()
        let collection = try await runtime.collectionState()
        return localHealth(health, collection: collection)
    }

    private static func localHealth(_ health: StoreHealth, collection: CollectionState) -> LocalHealth {
        LocalHealth(
            schemaVersion: health.schemaVersion,
            eventCount: health.eventCount,
            quickCheckPassed: health.quickCheckPassed,
            globallyPaused: collection.globallyPaused
        )
    }
}

@main
struct WWMDApp: App {
    @AppStorage("wwmd.local.databasePath") private var databasePath = ""
    @StateObject private var model = LocalRuntimeModel()

    var body: some Scene {
        MenuBarExtra("WWMD", systemImage: "waveform.path.ecg") {
            MenuContent(databasePath: $databasePath, model: model)
        }
        .menuBarExtraStyle(.window)

        Window("WWMD", id: WWMDWindowID.main) {
            ViewerContent(databasePath: $databasePath, model: model)
                .frame(minWidth: 760, minHeight: 650)
        }
        .defaultSize(width: 880, height: 760)
    }
}

private struct MenuContent: View {
    @Binding var databasePath: String
    @ObservedObject var model: LocalRuntimeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.statusTitle).font(.headline)
            Text(model.statusDetail).font(.subheadline).foregroundStyle(.secondary)

            if let activePath = model.currentDatabasePath {
                Text(activePath).font(.caption).textSelection(.enabled)
            }

            HStack {
                Button(model.isOpening ? "Opening…" : "Open selected database") {
                    model.open(databasePath: databasePath)
                }
                .disabled(databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isOpening)

                if model.isActive {
                    Button("Refresh") { model.refresh() }
                    Button(model.health?.globallyPaused == true ? "Resume collection" : "Pause collection") {
                        model.setCollectionPaused(model.health?.globallyPaused != true)
                    }
                    .disabled(!model.canControlCollection)
                    Button("Close database") { model.close() }
                }
            }

            Divider()

            Button("Open WWMD") { openMainWindow() }
            Button("Quit WWMD") { NSApplication.shared.terminate(nil) }

            Divider()
            Text("Privacy: metadata only; no prompt, response, title, source, or shell content.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text("Single-process local mode. No socket, daemon, or XPC listener is started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 470)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == WWMDWindowID.main }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct ViewerContent: View {
    @Binding var databasePath: String
    @ObservedObject var model: LocalRuntimeModel
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var to = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("WWMD").font(.largeTitle.bold())
                Text("Private local work metadata, reviewed only in an explicit date range.")
                    .foregroundStyle(.secondary)

                GroupBox("Local database") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Absolute database file path", text: $databasePath)
                            .textFieldStyle(.roundedBorder)
                        Text("Enter one exact absolute file path. Opening it creates the parent folder if needed and acquires WWMD’s exclusive runtime lease. WWMD never scans for or infers a database path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(model.isOpening ? "Opening…" : "Open selected database") {
                                model.open(databasePath: databasePath)
                            }
                            .disabled(databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isOpening)
                            if model.isActive {
                                Button("Refresh health") { model.refresh() }
                                Button("Close database") { model.close() }
                            }
                        }
                        if let activePath = model.currentDatabasePath {
                            LabeledContent("Active database") {
                                Text(activePath).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox(model.statusTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.statusDetail)
                        if let health = model.health {
                            HStack(spacing: 28) {
                                HealthValue(label: "Schema", value: "\(health.schemaVersion)")
                                HealthValue(label: "Events", value: "\(health.eventCount)")
                                HealthValue(label: "Database", value: health.quickCheckPassed ? "Healthy" : "Check failed")
                                HealthValue(label: "Collection", value: health.globallyPaused ? "Paused" : "Running")
                            }
                            Button(health.globallyPaused ? "Resume collection" : "Pause collection") {
                                model.setCollectionPaused(!health.globallyPaused)
                            }
                            .disabled(!model.canControlCollection)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Explicit date-range dashboard") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            DatePicker("From", selection: $from, displayedComponents: [.date, .hourAndMinute])
                            DatePicker("To", selection: $to, displayedComponents: [.date, .hourAndMinute])
                        }
                        Button(model.isLoadingDashboard ? "Loading…" : "Load dashboard") {
                            model.loadDashboard(from: from, to: to)
                        }
                        .disabled(model.isLoadingDashboard || !model.isActive)

                        if let message = model.dashboardMessage {
                            Text(message).foregroundStyle(.red)
                        }
                        if let summary = model.summary {
                            SummaryView(summary: summary)
                        }
                        if !model.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recommendations").font(.headline)
                                ForEach(model.recommendations) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.subheadline.bold())
                                        Text(item.explanation).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                Text("Privacy: metadata only; no prompt, response, title, source, or shell content. The app owns the selected database while it is open and starts no socket, daemon, or XPC listener.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }
}

private struct HealthValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }
}

private struct SummaryView: View {
    let summary: XPCSummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").font(.headline)
            HStack(spacing: 28) {
                HealthValue(label: "Events", value: "\(summary.eventCount)")
                HealthValue(label: "Metrics", value: "\(summary.metrics.count)")
                HealthValue(label: "Through sequence", value: "\(summary.processedThroughSequence)")
            }
        }
    }
}
