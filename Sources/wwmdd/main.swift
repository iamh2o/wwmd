import Dispatch
import Foundation
import WWMDAgentRuntime
import WWMDCore
import WWMDStorage

@main
struct WWMDDAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let database = value(after: "--database", in: arguments) else {
            writeError(usage)
            return
        }

        do {
            let store = try TelemetryStore(path: database)
            let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
            if arguments == ["--database", database, "--health"] {
                let health = try await runtime.health()
                print("wwmdd database health: schema=\(health.schemaVersion) events=\(health.eventCount) quick_check=\(health.quickCheckPassed ? "ok" : "failed")")
                return
            }

            guard arguments.contains("--serve"),
                  let serviceName = value(after: "--mach-service", in: arguments),
                  let peerRequirement = value(after: "--peer-requirement", in: arguments),
                  arguments.count == 7
            else {
                writeError(usage)
                return
            }
            let server = try NativeXPCServer(
                machServiceName: serviceName,
                peerCodeSigningRequirement: peerRequirement,
                runtime: runtime
            )
            server.activate()
            dispatchMain()
        } catch {
            writeError(error.localizedDescription)
        }
    }

    private static let usage = """
    Usage:
      wwmdd --database <absolute-path> --health
      wwmdd --database <absolute-path> --mach-service <name> --peer-requirement <requirement> --serve

    Native XPC serving requires an explicit launchd/Mach service name and an
    explicit peer code-signing requirement. WWMD never supplies an unsigned
    fallback.
    """

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("wwmdd: \(message)\n".utf8))
    }
}
