import AppKit
import Combine
import Foundation
import SwiftUI
import WWMDIPC

private enum WWMDWindowID {
    static let main = "wwmd-main"
}

private struct AgentConnectionConfiguration: Equatable, Sendable {
    let machServiceName: String
    let agentRequirement: String

    init(machServiceName: String, agentRequirement: String) {
        self.machServiceName = machServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.agentRequirement = agentRequirement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !machServiceName.isEmpty && !agentRequirement.isEmpty
    }
}

@MainActor
private final class AgentConnectionModel: ObservableObject {
    private enum State: Equatable {
        case setupRequired
        case ready
        case connecting
        case active
        case unavailable(String)
    }

    private enum HealthAttempt: Sendable {
        case success(XPCHealthResponse)
        case failure(String)
    }

    private enum PauseAttempt: Sendable {
        case success(XPCCollectionStateResponse)
        case failure(String)
    }

    private enum DashboardAttempt: Sendable {
        case success(XPCSummaryResponse, [XPCRecommendationItem])
        case failure(String)
    }

    @Published private(set) var health: XPCHealthResponse?
    @Published private(set) var summary: XPCSummaryResponse?
    @Published private(set) var recommendations: [XPCRecommendationItem] = []
    @Published private(set) var dashboardMessage: String?
    @Published private(set) var isLoadingDashboard = false
    @Published private(set) var isMutating = false
    @Published private var state: State = .setupRequired

    private var configuration = AgentConnectionConfiguration(machServiceName: "", agentRequirement: "")
    private var operationID = UUID()
    private var dashboardOperationID = UUID()

    var statusTitle: String {
        switch state {
        case .setupRequired:
            "Agent configuration required"
        case .ready:
            "Signed agent not checked"
        case .connecting:
            "Checking signed agent"
        case .active:
            health?.globallyPaused == true ? "Collection paused" : "Agent connected"
        case .unavailable:
            "Agent unavailable"
        }
    }

    var statusDetail: String {
        switch state {
        case .setupRequired:
            return "Enter an explicit Mach service name and agent code-signing requirement. WWMD will not infer either value."
        case .ready:
            return "The signed-agent configuration is stored locally. Test the authenticated XPC connection before collection controls appear."
        case .connecting:
            return "WWMD is checking the configured native XPC service."
        case .active:
            guard let health else { return "The agent returned no health state." }
            return "Schema \(health.schemaVersion), \(health.eventCount) events, database check \(health.quickCheckPassed ? "passed" : "failed")."
        case .unavailable(let message):
            return message
        }
    }

    var isConnecting: Bool {
        state == .connecting
    }

    var canControlCollection: Bool {
        health != nil && !isConnecting && !isMutating
    }

    func adopt(_ configuration: AgentConnectionConfiguration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        operationID = UUID()
        dashboardOperationID = UUID()
        health = nil
        summary = nil
        recommendations = []
        dashboardMessage = nil
        isLoadingDashboard = false
        isMutating = false
        state = configuration.isComplete ? .ready : .setupRequired
    }

    func refresh(using configuration: AgentConnectionConfiguration) {
        adopt(configuration)
        guard configuration.isComplete else {
            state = .setupRequired
            return
        }
        let currentOperationID = UUID()
        operationID = currentOperationID
        dashboardOperationID = UUID()
        health = nil
        summary = nil
        recommendations = []
        dashboardMessage = nil
        isLoadingDashboard = false
        isMutating = false
        state = .connecting

        Task { [configuration, currentOperationID] in
            let result = await Task.detached(priority: .userInitiated) { () -> HealthAttempt in
                do {
                    let client = try NativeXPCClient(
                        machServiceName: configuration.machServiceName,
                        agentCodeSigningRequirement: configuration.agentRequirement
                    )
                    return .success(try client.health())
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            guard self.operationID == currentOperationID else { return }
            switch result {
            case .success(let health):
                self.health = health
                self.state = .active
            case .failure(let message):
                self.health = nil
                self.dashboardOperationID = UUID()
                self.summary = nil
                self.recommendations = []
                self.isLoadingDashboard = false
                self.state = .unavailable(message)
                self.dashboardMessage = message
            }
        }
    }

    func setCollectionPaused(_ paused: Bool, using configuration: AgentConnectionConfiguration) {
        adopt(configuration)
        guard configuration.isComplete, health != nil else {
            state = configuration.isComplete ? .ready : .setupRequired
            return
        }
        let currentOperationID = UUID()
        operationID = currentOperationID
        isMutating = true

        Task { [configuration, currentOperationID] in
            let result = await Task.detached(priority: .userInitiated) { () -> PauseAttempt in
                do {
                    let client = try NativeXPCClient(
                        machServiceName: configuration.machServiceName,
                        agentCodeSigningRequirement: configuration.agentRequirement
                    )
                    return .success(try client.setCollectionState(paused))
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            guard self.operationID == currentOperationID else { return }
            self.isMutating = false
            switch result {
            case .success(let response):
                if let health = self.health {
                    self.health = XPCHealthResponse(
                        schemaVersion: health.schemaVersion,
                        eventCount: health.eventCount,
                        quickCheckPassed: health.quickCheckPassed,
                        globallyPaused: response.globallyPaused
                    )
                }
                self.state = .active
            case .failure(let message):
                self.health = nil
                self.dashboardOperationID = UUID()
                self.summary = nil
                self.recommendations = []
                self.isLoadingDashboard = false
                self.state = .unavailable(message)
                self.dashboardMessage = message
            }
        }
    }

    func loadDashboard(
        from: Date,
        to: Date,
        using configuration: AgentConnectionConfiguration
    ) {
        adopt(configuration)
        guard configuration.isComplete, health != nil else {
            dashboardMessage = "Connect to the configured signed agent before loading a summary."
            return
        }
        let summaryQuery = SummaryQuery(from: from, to: to, metricNames: [])
        let recommendationScope = XPCScopedQuery(from: from, to: to)
        do {
            try XPCContractValidator.validate(summaryQuery)
            try XPCContractValidator.validateScope(recommendationScope)
        } catch {
            summary = nil
            recommendations = []
            dashboardMessage = error.localizedDescription
            return
        }

        let currentDashboardOperationID = UUID()
        dashboardOperationID = currentDashboardOperationID
        summary = nil
        recommendations = []
        dashboardMessage = nil
        isLoadingDashboard = true

        Task { [configuration, currentDashboardOperationID] in
            let result = await Task.detached(priority: .userInitiated) { () -> DashboardAttempt in
                do {
                    let client = try NativeXPCClient(
                        machServiceName: configuration.machServiceName,
                        agentCodeSigningRequirement: configuration.agentRequirement
                    )
                    let summary = try client.summary(summaryQuery)
                    let recommendations = try client.recommendations(recommendationScope)
                    return .success(summary, recommendations.items)
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            guard self.dashboardOperationID == currentDashboardOperationID else { return }
            self.isLoadingDashboard = false
            switch result {
            case .success(let summary, let recommendations):
                self.summary = summary
                self.recommendations = recommendations
            case .failure(let message):
                self.health = nil
                self.dashboardOperationID = UUID()
                self.summary = nil
                self.recommendations = []
                self.isLoadingDashboard = false
                self.state = .unavailable(message)
                self.dashboardMessage = message
            }
        }
    }
}

@main
struct WWMDApp: App {
    @AppStorage("wwmd.agent.machServiceName") private var machServiceName = ""
    @AppStorage("wwmd.agent.codeSigningRequirement") private var agentRequirement = ""
    @StateObject private var agentConnection = AgentConnectionModel()

    private var configuration: AgentConnectionConfiguration {
        AgentConnectionConfiguration(
            machServiceName: machServiceName,
            agentRequirement: agentRequirement
        )
    }

    var body: some Scene {
        MenuBarExtra("WWMD", systemImage: "hand.raised.circle") {
            WWMDMenuBarContents(configuration: configuration)
                .environmentObject(agentConnection)
        }
        .menuBarExtraStyle(.window)

        Window("WWMD", id: WWMDWindowID.main) {
            WWMDViewer(
                machServiceName: $machServiceName,
                agentRequirement: $agentRequirement
            )
            .environmentObject(agentConnection)
        }

        Settings {
            WWMDSettings(
                machServiceName: $machServiceName,
                agentRequirement: $agentRequirement
            )
            .environmentObject(agentConnection)
        }
    }
}

private struct WWMDMenuBarContents: View {
    let configuration: AgentConnectionConfiguration

    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var agentConnection: AgentConnectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(agentConnection.statusTitle)
                .font(.headline)
            Text(agentConnection.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let health = agentConnection.health {
                Divider()
                LabeledContent("Events", value: "\(health.eventCount)")
                LabeledContent("Global pause", value: health.globallyPaused ? "Paused" : "Active")
                Button(health.globallyPaused ? "Resume collection" : "Pause collection") {
                    agentConnection.setCollectionPaused(!health.globallyPaused, using: configuration)
                }
                .disabled(!agentConnection.canControlCollection)
            }
            Divider()
            Button(agentConnection.isConnecting ? "Checking agent…" : "Refresh signed agent") {
                agentConnection.refresh(using: configuration)
            }
            .disabled(!configuration.isComplete || agentConnection.isConnecting || agentConnection.isMutating)
            Button("Open WWMD") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WWMDWindowID.main)
            }
            Divider()
            Text("Privacy: metadata only; no prompt, response, title, source, or shell content.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit WWMD") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear {
            agentConnection.adopt(configuration)
        }
        .onChange(of: configuration) { newValue in
            agentConnection.adopt(newValue)
        }
    }
}

private struct WWMDViewer: View {
    @Binding var machServiceName: String
    @Binding var agentRequirement: String

    @EnvironmentObject private var agentConnection: AgentConnectionModel
    @State private var summaryFrom = Calendar.current.startOfDay(for: Date())
    @State private var summaryTo = Date()

    private var configuration: AgentConnectionConfiguration {
        AgentConnectionConfiguration(
            machServiceName: machServiceName,
            agentRequirement: agentRequirement
        )
    }

    var body: some View {
        NavigationSplitView {
            List {
                Label("Today", systemImage: "calendar")
                Label("Current Session", systemImage: "clock")
                Label("Recommendations", systemImage: "lightbulb")
                Label("Data Quality", systemImage: "checkmark.shield")
                Label("Privacy", systemImage: "hand.raised")
            }
            .navigationTitle("WWMD")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(agentConnection.statusTitle, systemImage: agentConnection.health == nil ? "xmark.shield" : "checkmark.shield")
                            .font(.title3)
                        Text(agentConnection.statusDetail)
                            .foregroundStyle(.secondary)
                    }

                    if let health = agentConnection.health {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            GridRow {
                                Text("Database")
                                    .foregroundStyle(.secondary)
                                Text(health.quickCheckPassed ? "Integrity check passed" : "Integrity check failed")
                            }
                            GridRow {
                                Text("Ledger")
                                    .foregroundStyle(.secondary)
                                Text("\(health.eventCount) events; schema \(health.schemaVersion)")
                            }
                            GridRow {
                                Text("Collection")
                                    .foregroundStyle(.secondary)
                                Text(health.globallyPaused ? "Globally paused" : "Not globally paused")
                            }
                        }
                        HStack {
                            Button(health.globallyPaused ? "Resume collection" : "Pause collection") {
                                agentConnection.setCollectionPaused(!health.globallyPaused, using: configuration)
                            }
                            .disabled(!agentConnection.canControlCollection)
                            Button("Refresh") {
                                agentConnection.refresh(using: configuration)
                            }
                            .disabled(agentConnection.isConnecting || agentConnection.isMutating)
                        }
                    }

                    GroupBox("Safe summary and recommendations") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                DatePicker("From", selection: $summaryFrom, displayedComponents: [.date, .hourAndMinute])
                                DatePicker("To", selection: $summaryTo, displayedComponents: [.date, .hourAndMinute])
                            }
                            Button(agentConnection.isLoadingDashboard ? "Loading…" : "Load selected range") {
                                agentConnection.loadDashboard(
                                    from: summaryFrom,
                                    to: summaryTo,
                                    using: configuration
                                )
                            }
                            .disabled(
                                agentConnection.health == nil ||
                                agentConnection.isConnecting ||
                                agentConnection.isMutating ||
                                agentConnection.isLoadingDashboard
                            )

                            if let message = agentConnection.dashboardMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let summary = agentConnection.summary {
                                Text("\(summary.eventCount) safe events through ledger sequence \(summary.processedThroughSequence)")
                                    .font(.subheadline)
                                ForEach(summary.metrics, id: \.name) { metric in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(metric.name)
                                        Spacer()
                                        Text(metricDisplayValue(metric))
                                            .monospacedDigit()
                                        Text(metric.unit)
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }

                            if agentConnection.summary != nil {
                                Divider()
                                Text("Recommendations")
                                    .font(.subheadline)
                                if agentConnection.recommendations.isEmpty {
                                    Text("No evidence-backed recommendations are active in this selected range.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(agentConnection.recommendations) { recommendation in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(recommendation.title)
                                                .font(.headline)
                                            Text(recommendation.explanation)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("Rule \(recommendation.ruleID) v\(recommendation.ruleVersion) · evidence grade \(recommendation.evidenceGrade)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("Signed agent configuration") {
                        VStack(alignment: .leading, spacing: 10) {
                            AgentConfigurationFields(
                                machServiceName: $machServiceName,
                                agentRequirement: $agentRequirement
                            )
                            HStack {
                                Button(agentConnection.isConnecting ? "Checking…" : "Test signed agent connection") {
                                    agentConnection.refresh(using: configuration)
                                }
                                .disabled(!configuration.isComplete || agentConnection.isConnecting || agentConnection.isMutating)
                                if !configuration.isComplete {
                                    Text("Both values are required. WWMD will not discover or invent them.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    Text("WWMD does not open the database from the app. Health and pause state above are available only after the configured native XPC connection accepts the exact signing requirement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 650, alignment: .leading)
            }
        }
        .onAppear {
            agentConnection.adopt(configuration)
        }
        .onChange(of: machServiceName) { _ in
            agentConnection.adopt(configuration)
        }
        .onChange(of: agentRequirement) { _ in
            agentConnection.adopt(configuration)
        }
    }

    private func metricDisplayValue(_ metric: XPCMetricResponse) -> String {
        guard let value = metric.value else {
            return metric.availability.replacingOccurrences(of: "_", with: " ")
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct AgentConfigurationFields: View {
    @Binding var machServiceName: String
    @Binding var agentRequirement: String

    var body: some View {
        TextField("Mach service name", text: $machServiceName)
            .textFieldStyle(.roundedBorder)
        TextField("Agent code-signing requirement", text: $agentRequirement)
            .textFieldStyle(.roundedBorder)
        Text("These local settings contain a service identifier and a designated code-signing requirement, not a database path or a source permission.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct WWMDSettings: View {
    @Binding var machServiceName: String
    @Binding var agentRequirement: String

    @EnvironmentObject private var agentConnection: AgentConnectionModel

    private var configuration: AgentConnectionConfiguration {
        AgentConnectionConfiguration(
            machServiceName: machServiceName,
            agentRequirement: agentRequirement
        )
    }

    var body: some View {
        Form {
            Section("Signed agent") {
                AgentConfigurationFields(
                    machServiceName: $machServiceName,
                    agentRequirement: $agentRequirement
                )
                Button(agentConnection.isConnecting ? "Checking…" : "Test signed agent connection") {
                    agentConnection.refresh(using: configuration)
                }
                .disabled(!configuration.isComplete || agentConnection.isConnecting || agentConnection.isMutating)
                Text(agentConnection.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Collection") {
                Text("Every adapter is opt-in. Global pause persists only in the configured signed agent.")
            }
            Section("Privacy") {
                Text("WWMD v0 excludes prompts, responses, source contents, window titles, shell arguments, logs, environment values, clipboard, screenshots, keylogging, and browser history.")
            }
            Section("Codex CSV") {
                Text("Import remains blocked until an actual CSV header and field contract is supplied.")
            }
        }
        .padding()
        .frame(width: 620)
        .onAppear {
            agentConnection.adopt(configuration)
        }
        .onChange(of: machServiceName) { _ in
            agentConnection.adopt(configuration)
        }
        .onChange(of: agentRequirement) { _ in
            agentConnection.adopt(configuration)
        }
    }
}
