import Foundation
import WWMDIPC

enum XPCHealthBridge {
    static func dispatch(
        runtime: WWMDAgentRuntime,
        reply: @escaping (Data?, NSError?) -> Void
    ) {
        let replyBox = XPCHealthReplyBox(reply)
        Task {
            do {
                let health = try await runtime.health()
                let collectionState = try await runtime.collectionState()
                let response = XPCHealthResponse(
                    schemaVersion: health.schemaVersion,
                    eventCount: health.eventCount,
                    quickCheckPassed: health.quickCheckPassed,
                    globallyPaused: collectionState.globallyPaused
                )
                replyBox.send(try XPCCodec.encode(response), nil)
            } catch {
                replyBox.send(nil, xpcHealthError())
            }
        }
    }

    private static func xpcHealthError() -> NSError {
        NSError(
            domain: "WWMDXPC",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "WWMD XPC request is unavailable or invalid."]
        )
    }
}

enum XPCServiceBridge {
    static func dispatch<Response: Encodable & Sendable>(
        runtime: WWMDAgentRuntime,
        reply: @escaping (Data?, NSError?) -> Void,
        operation: @escaping @Sendable (WWMDAgentRuntime) async throws -> Response
    ) {
        let replyBox = XPCHealthReplyBox(reply)
        Task {
            do {
                replyBox.send(try XPCCodec.encode(try await operation(runtime)), nil)
            } catch {
                replyBox.send(nil, xpcServiceError())
            }
        }
    }

    private static func xpcServiceError() -> NSError {
        NSError(
            domain: "WWMDXPC",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "WWMD XPC request is unavailable or invalid."]
        )
    }
}

private final class XPCHealthReplyBox: @unchecked Sendable {
    private let reply: (Data?, NSError?) -> Void

    init(_ reply: @escaping (Data?, NSError?) -> Void) {
        self.reply = reply
    }

    func send(_ data: Data?, _ error: NSError?) {
        reply(data, error)
    }
}
