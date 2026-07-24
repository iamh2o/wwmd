import Foundation

public enum NativeXPCClientError: Error, Equatable, Sendable, LocalizedError {
    case emptyMachServiceName
    case emptyCodeSigningRequirement
    case requestEncodingFailed
    case responseDecodingFailed
    case connectionFailed
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .emptyMachServiceName:
            "A native XPC Mach service name is required."
        case .emptyCodeSigningRequirement:
            "An explicit native XPC agent code-signing requirement is required."
        case .requestEncodingFailed:
            "WWMD could not encode the XPC request."
        case .responseDecodingFailed:
            "WWMD received an invalid XPC response."
        case .connectionFailed:
            "WWMD could not establish the authenticated XPC connection."
        case .timedOut:
            "WWMD XPC request timed out."
        }
    }
}

public struct NativeXPCClient {
    private let machServiceName: String
    private let agentCodeSigningRequirement: String

    public init(machServiceName: String, agentCodeSigningRequirement: String) throws {
        guard !machServiceName.isEmpty else {
            throw NativeXPCClientError.emptyMachServiceName
        }
        guard !agentCodeSigningRequirement.isEmpty else {
            throw NativeXPCClientError.emptyCodeSigningRequirement
        }
        self.machServiceName = machServiceName
        self.agentCodeSigningRequirement = agentCodeSigningRequirement
    }

    public func health(timeout: TimeInterval = 5) throws -> XPCHealthResponse {
        try call(
            request: XPCRequestEnvelope(kind: .health, capability: .query),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.getHealth(data, withReply: reply)
        }
    }

    public func summary(_ query: SummaryQuery, timeout: TimeInterval = 5) throws -> XPCSummaryResponse {
        try call(
            request: XPCSummaryRequest(
                envelope: XPCRequestEnvelope(kind: .querySummary, capability: .query),
                query: query
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.querySummary(data, withReply: reply)
        }
    }

    public func evidence(_ query: XPCEvidenceQuery, timeout: TimeInterval = 5) throws -> XPCEvidenceResponse {
        try call(
            request: XPCEvidenceRequest(
                envelope: XPCRequestEnvelope(kind: .queryEvidence, capability: .query),
                query: query
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.queryEvidence(data, withReply: reply)
        }
    }

    public func recommendations(_ query: XPCScopedQuery, timeout: TimeInterval = 5) throws -> XPCRecommendationsResponse {
        try call(
            request: XPCRecommendationRequest(
                envelope: XPCRequestEnvelope(kind: .queryRecommendations, capability: .query),
                query: query
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.queryRecommendations(data, withReply: reply)
        }
    }

    public func setCollectionState(_ paused: Bool, timeout: TimeInterval = 5) throws -> XPCCollectionStateResponse {
        try call(
            request: XPCCollectionStateRequest(
                envelope: XPCRequestEnvelope(kind: .setCollectionState, capability: .control),
                globallyPaused: paused
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.setCollectionState(data, withReply: reply)
        }
    }

    public func previewDeletion(
        _ scope: XPCDeletionScope,
        timeout: TimeInterval = 5
    ) throws -> XPCDeletionPreviewResponse {
        try call(
            request: XPCDeletionRequest(
                envelope: XPCRequestEnvelope(kind: .requestDeletion, capability: .destructiveDelete),
                phase: .preview,
                scope: scope
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.requestDeletion(data, withReply: reply)
        }
    }

    public func confirmDeletion(
        nonce: UUID,
        timeout: TimeInterval = 5
    ) throws -> XPCDeletionReceiptResponse {
        try call(
            request: XPCDeletionRequest(
                envelope: XPCRequestEnvelope(kind: .requestDeletion, capability: .destructiveDelete),
                phase: .confirm,
                confirmationNonce: nonce
            ),
            timeout: timeout
        ) { proxy, data, reply in
            proxy.requestDeletion(data, withReply: reply)
        }
    }

    private func call<Request: Encodable, Response: Decodable>(
        request: Request,
        timeout: TimeInterval,
        invocation: @escaping (WWMDXPCService, Data, @escaping (Data?, NSError?) -> Void) -> Void
    ) throws -> Response {
        guard timeout > 0, timeout <= 30 else {
            throw NativeXPCClientError.timedOut
        }
        let requestData: Data
        do {
            requestData = try XPCCodec.encode(request)
        } catch {
            throw NativeXPCClientError.requestEncodingFailed
        }

        let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.setCodeSigningRequirement(agentCodeSigningRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: WWMDXPCService.self)
        let semaphore = DispatchSemaphore(value: 0)
        let box = ClientResultBox<Response>()
        connection.invalidationHandler = {
            box.setIfEmpty(.failure(.connectionFailed))
            semaphore.signal()
        }
        connection.activate()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            box.setIfEmpty(.failure(.connectionFailed))
            semaphore.signal()
        }) as? WWMDXPCService else {
            connection.invalidate()
            throw NativeXPCClientError.connectionFailed
        }
        invocation(proxy, requestData) { data, error in
            if error != nil {
                box.setIfEmpty(.failure(.connectionFailed))
            } else if let data {
                do {
                    box.setIfEmpty(.success(try XPCCodec.decode(Response.self, from: data)))
                } catch {
                    box.setIfEmpty(.failure(.responseDecodingFailed))
                }
            } else {
                box.setIfEmpty(.failure(.responseDecodingFailed))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            connection.invalidate()
            throw NativeXPCClientError.timedOut
        }
        connection.invalidate()
        guard let outcome = box.value else {
            throw NativeXPCClientError.connectionFailed
        }
        return try outcome.get()
    }
}

private final class ClientResultBox<Response>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Response, NativeXPCClientError>?

    func setIfEmpty(_ result: Result<Response, NativeXPCClientError>) {
        lock.lock()
        defer { lock.unlock() }
        if self.result == nil {
            self.result = result
        }
    }

    var value: Result<Response, NativeXPCClientError>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
