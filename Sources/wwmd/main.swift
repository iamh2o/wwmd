import Foundation
import WWMDIPC

@main
struct WWMDCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "--version":
            print("wwmd XPC API \(APIVersion.v1.major).\(APIVersion.v1.minor)")
        case "--help", nil:
            print(usage)
        case "health":
            runHealth(arguments: Array(arguments.dropFirst()))
        case "summary":
            runSummary(arguments: Array(arguments.dropFirst()))
        case "evidence":
            runEvidence(arguments: Array(arguments.dropFirst()))
        case "recommendations":
            runRecommendations(arguments: Array(arguments.dropFirst()))
        default:
            writeError(usage)
        }
    }

    private static func runHealth(arguments: [String]) {
        guard arguments.count == 4,
              arguments[0] == "--mach-service",
              arguments[2] == "--agent-requirement"
        else {
            writeError(usage)
            return
        }
        do {
            let client = try NativeXPCClient(
                machServiceName: arguments[1],
                agentCodeSigningRequirement: arguments[3]
            )
            let health = try client.health()
            print(
                "schema=\(health.schemaVersion) events=\(health.eventCount) quick_check=\(health.quickCheckPassed ? "ok" : "failed") paused=\(health.globallyPaused)"
            )
        } catch {
            writeError(error.localizedDescription)
        }
    }

    private static func runSummary(arguments: [String]) {
        guard let request = scopedRequest(arguments: arguments) else {
            writeError(usage)
            return
        }
        do {
            let client = try NativeXPCClient(
                machServiceName: request.machServiceName,
                agentCodeSigningRequirement: request.agentRequirement
            )
            let response = try client.summary(
                SummaryQuery(from: request.scope.from, to: request.scope.to, metricNames: [])
            )
            try writeJSON(response)
        } catch {
            writeError(error.localizedDescription)
        }
    }

    private static func runEvidence(arguments: [String]) {
        guard arguments.count == 10,
              arguments[8] == "--limit",
              let limit = Int(arguments[9]),
              let request = scopedRequest(arguments: Array(arguments.prefix(8)))
        else {
            writeError(usage)
            return
        }
        do {
            let client = try NativeXPCClient(
                machServiceName: request.machServiceName,
                agentCodeSigningRequirement: request.agentRequirement
            )
            let response = try client.evidence(
                XPCEvidenceQuery(scope: request.scope, limit: limit)
            )
            try writeJSON(response)
        } catch {
            writeError(error.localizedDescription)
        }
    }

    private static func runRecommendations(arguments: [String]) {
        guard let request = scopedRequest(arguments: arguments) else {
            writeError(usage)
            return
        }
        do {
            let client = try NativeXPCClient(
                machServiceName: request.machServiceName,
                agentCodeSigningRequirement: request.agentRequirement
            )
            let response = try client.recommendations(request.scope)
            try writeJSON(response)
        } catch {
            writeError(error.localizedDescription)
        }
    }

    private static func scopedRequest(arguments: [String]) -> ScopedRequest? {
        guard arguments.count == 8,
              arguments[0] == "--mach-service",
              arguments[2] == "--agent-requirement",
              arguments[4] == "--from",
              arguments[6] == "--to",
              let from = parseRFC3339(arguments[5]),
              let to = parseRFC3339(arguments[7])
        else {
            return nil
        }
        return ScopedRequest(
            machServiceName: arguments[1],
            agentRequirement: arguments[3],
            scope: XPCScopedQuery(from: from, to: to)
        )
    }

    private static func parseRFC3339(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func writeJSON<Value: Encodable>(_ value: Value) throws {
        let data = try XPCCodec.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NativeXPCClientError.responseDecodingFailed
        }
        print(text)
    }

    private static let usage = """
    Usage:
      wwmd --version
      wwmd health --mach-service <name> --agent-requirement <requirement>
      wwmd summary --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339>
      wwmd evidence --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339> --limit <1-200>
      wwmd recommendations --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339>
      wwmd --help

    The CLI emits safe JSON for authenticated native-XPC read-only queries. It
    never scans for or opens the database, and it never supplies an unsigned
    fallback.
    """

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("wwmd: \(message)\n".utf8))
    }
}

private struct ScopedRequest {
    let machServiceName: String
    let agentRequirement: String
    let scope: XPCScopedQuery
}
