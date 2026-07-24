import AppKit
import SwiftUI

private enum WWMDWindowID {
    static let main = "wwmd-main"
}

@main
struct WWMDApp: App {
    var body: some Scene {
        MenuBarExtra("WWMD", systemImage: "hand.raised.circle") {
            WWMDMenuBarContents()
        }
        .menuBarExtraStyle(.window)

        Window("WWMD", id: WWMDWindowID.main) {
            WWMDViewer()
        }

        Settings {
            WWMDSettings()
        }
    }
}

private struct WWMDMenuBarContents: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agent configuration required")
                .font(.headline)
            Text("No source is enabled. Collection controls become available only after a signed WWMD agent is configured.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent("Global pause", value: "Agent unavailable")
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
        .frame(width: 330)
    }
}

private struct WWMDViewer: View {
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
            VStack(spacing: 12) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No collection is enabled")
                    .font(.title3)
                Text("Enable an explicit local adapter in Privacy settings. WWMD will not discover or collect content sources automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }
        }
    }
}

private struct WWMDSettings: View {
    var body: some View {
        Form {
            Section("Collection") {
                Text("Every adapter is opt-in. Global pause persists in the agent when the signed XPC service is configured.")
            }
            Section("Privacy") {
                Text("WWMD v0 excludes prompts, responses, source contents, window titles, shell arguments, logs, environment values, clipboard, screenshots, keylogging, and browser history.")
            }
            Section("Codex CSV") {
                Text("Import remains blocked until an actual CSV header and field contract is supplied.")
            }
        }
        .padding()
        .frame(width: 520)
    }
}
