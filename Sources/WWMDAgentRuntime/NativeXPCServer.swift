import Darwin
import Foundation
import WWMDIPC

public enum NativeXPCServerError: Error, Equatable, Sendable, LocalizedError {
    case emptyMachServiceName
    case emptyCodeSigningRequirement

    public var errorDescription: String? {
        switch self {
        case .emptyMachServiceName:
            "A native XPC Mach service name is required."
        case .emptyCodeSigningRequirement:
            "An explicit native XPC code-signing requirement is required."
        }
    }
}

public final class WWMDAgentXPCService: NSObject, WWMDXPCService {
    private let runtime: WWMDAgentRuntime

    public init(runtime: WWMDAgentRuntime) {
        self.runtime = runtime
    }

    public func getHealth(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try XPCCodec.decode(XPCRequestEnvelope.self, from: requestData)
            try XPCContractValidator.validate(request)
            guard request.kind == .health, request.capability == .query else {
                reply(nil, Self.protocolError(code: 2))
                return
            }
            XPCHealthBridge.dispatch(runtime: runtime, reply: reply)
        } catch {
            reply(nil, Self.protocolError(code: 1))
        }
    }

    public func querySummary(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try XPCCodec.decode(XPCSummaryRequest.self, from: requestData)
            try XPCContractValidator.validate(request.envelope)
            try XPCContractValidator.validate(request.query)
            guard request.envelope.kind == .querySummary, request.envelope.capability == .query else {
                reply(nil, Self.protocolError(code: 2))
                return
            }
            XPCServiceBridge.dispatch(runtime: runtime, reply: reply) { runtime in
                try await runtime.summary(query: request.query)
            }
        } catch {
            reply(nil, Self.protocolError(code: 1))
        }
    }

    public func queryEvidence(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try XPCCodec.decode(XPCEvidenceRequest.self, from: requestData)
            try XPCContractValidator.validate(request.envelope)
            try XPCContractValidator.validate(request.query)
            guard request.envelope.kind == .queryEvidence, request.envelope.capability == .query else {
                reply(nil, Self.protocolError(code: 2))
                return
            }
            XPCServiceBridge.dispatch(runtime: runtime, reply: reply) { runtime in
                try await runtime.evidence(query: request.query)
            }
        } catch {
            reply(nil, Self.protocolError(code: 1))
        }
    }

    public func queryRecommendations(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try XPCCodec.decode(XPCRecommendationRequest.self, from: requestData)
            try XPCContractValidator.validate(request.envelope)
            try XPCContractValidator.validateScope(request.query)
            guard request.envelope.kind == .queryRecommendations, request.envelope.capability == .query else {
                reply(nil, Self.protocolError(code: 2))
                return
            }
            XPCServiceBridge.dispatch(runtime: runtime, reply: reply) { runtime in
                try await runtime.recommendations(query: request.query)
            }
        } catch {
            reply(nil, Self.protocolError(code: 1))
        }
    }

    public func setCollectionState(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try XPCCodec.decode(XPCCollectionStateRequest.self, from: requestData)
            try XPCContractValidator.validate(request.envelope)
            guard request.envelope.kind == .setCollectionState, request.envelope.capability == .control else {
                reply(nil, Self.protocolError(code: 2))
                return
            }
            XPCServiceBridge.dispatch(runtime: runtime, reply: reply) { runtime in
                try await runtime.setCollectionState(request.globallyPaused)
            }
        } catch {
            reply(nil, Self.protocolError(code: 1))
        }
    }

    public func applyAnnotation(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, Self.protocolError(code: 4))
    }

    public func startExport(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, Self.protocolError(code: 4))
    }

    public func requestDeletion(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, Self.protocolError(code: 4))
    }

    private static func protocolError(code: Int) -> NSError {
        NSError(
            domain: "WWMDXPC",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "WWMD XPC request is unavailable or invalid."]
        )
    }
}

public final class NativeXPCServer: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let service: WWMDAgentXPCService

    public init(
        machServiceName: String,
        peerCodeSigningRequirement: String,
        runtime: WWMDAgentRuntime
    ) throws {
        guard !machServiceName.isEmpty else {
            throw NativeXPCServerError.emptyMachServiceName
        }
        guard !peerCodeSigningRequirement.isEmpty else {
            throw NativeXPCServerError.emptyCodeSigningRequirement
        }
        listener = NSXPCListener(machServiceName: machServiceName)
        service = WWMDAgentXPCService(runtime: runtime)
        super.init()
        listener.delegate = self
        listener.setConnectionCodeSigningRequirement(peerCodeSigningRequirement)
    }

    public func activate() {
        listener.activate()
    }

    public func invalidate() {
        listener.invalidate()
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: WWMDXPCService.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}
