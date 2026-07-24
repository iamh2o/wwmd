import Foundation
import WWMDCore

public struct APIVersion: Codable, Equatable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let v1 = APIVersion(major: 1, minor: 0)
}

public enum XPCRequestKind: String, Codable, CaseIterable, Sendable {
    case health
    case querySummary = "query_summary"
    case queryEvidence = "query_evidence"
    case queryRecommendations = "query_recommendations"
    case setCollectionState = "set_collection_state"
    case applyAnnotation = "apply_annotation"
    case startExport = "start_export"
    case requestDeletion = "request_deletion"
}

public enum XPCCapability: String, Codable, CaseIterable, Sendable {
    case query
    case control
    case export
    case destructiveDelete = "destructive_delete"
}

public struct XPCRequestEnvelope: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let apiVersion: APIVersion
    public let kind: XPCRequestKind
    public let capability: XPCCapability

    public init(
        requestID: UUID = UUID(),
        apiVersion: APIVersion = .v1,
        kind: XPCRequestKind,
        capability: XPCCapability
    ) {
        self.requestID = requestID
        self.apiVersion = apiVersion
        self.kind = kind
        self.capability = capability
    }
}

public struct SummaryQuery: Codable, Equatable, Sendable {
    public let from: Date
    public let to: Date
    public let repositoryID: String?
    public let workUnitID: String?
    public let metricNames: [String]
    public let cursor: String?

    public init(
        from: Date,
        to: Date,
        repositoryID: String? = nil,
        workUnitID: String? = nil,
        metricNames: [String],
        cursor: String? = nil
    ) {
        self.from = from
        self.to = to
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
        self.metricNames = metricNames
        self.cursor = cursor
    }
}

public struct XPCScopedQuery: Codable, Equatable, Sendable {
    public let from: Date
    public let to: Date
    public let repositoryID: String?
    public let workUnitID: String?

    public init(
        from: Date,
        to: Date,
        repositoryID: String? = nil,
        workUnitID: String? = nil
    ) {
        self.from = from
        self.to = to
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
    }
}

public struct XPCEvidenceQuery: Codable, Equatable, Sendable {
    public let scope: XPCScopedQuery
    public let limit: Int

    public init(scope: XPCScopedQuery, limit: Int) {
        self.scope = scope
        self.limit = limit
    }
}

public struct XPCSummaryRequest: Codable, Equatable, Sendable {
    public let envelope: XPCRequestEnvelope
    public let query: SummaryQuery

    public init(envelope: XPCRequestEnvelope, query: SummaryQuery) {
        self.envelope = envelope
        self.query = query
    }
}

public struct XPCEvidenceRequest: Codable, Equatable, Sendable {
    public let envelope: XPCRequestEnvelope
    public let query: XPCEvidenceQuery

    public init(envelope: XPCRequestEnvelope, query: XPCEvidenceQuery) {
        self.envelope = envelope
        self.query = query
    }
}

public struct XPCRecommendationRequest: Codable, Equatable, Sendable {
    public let envelope: XPCRequestEnvelope
    public let query: XPCScopedQuery

    public init(envelope: XPCRequestEnvelope, query: XPCScopedQuery) {
        self.envelope = envelope
        self.query = query
    }
}

public struct XPCCollectionStateRequest: Codable, Equatable, Sendable {
    public let envelope: XPCRequestEnvelope
    public let globallyPaused: Bool

    public init(envelope: XPCRequestEnvelope, globallyPaused: Bool) {
        self.envelope = envelope
        self.globallyPaused = globallyPaused
    }
}

public enum XPCContractError: Error, Equatable, Sendable, LocalizedError {
    case incompatibleMajorVersion
    case capabilityDoesNotPermitKind
    case invalidTimeRange
    case tooManyMetrics
    case pageLimitExceeded
    case invalidScope

    public var errorDescription: String? {
        switch self {
        case .incompatibleMajorVersion:
            "The client and agent XPC major versions are incompatible."
        case .capabilityDoesNotPermitKind:
            "The XPC capability does not permit this request."
        case .invalidTimeRange:
            "The query time range is invalid or exceeds the allowed span."
        case .tooManyMetrics:
            "The request asks for too many metrics."
        case .pageLimitExceeded:
            "The request exceeds the fixed response page limit."
        case .invalidScope:
            "The request scope is invalid."
        }
    }
}

public enum XPCContractValidator {
    public static let maximumSummaryMetrics = 50
    public static let maximumQueryDays = 366
    public static let maximumEvidenceRecords = 200

    public static func validate(_ envelope: XPCRequestEnvelope) throws {
        guard envelope.apiVersion.major == APIVersion.v1.major else {
            throw XPCContractError.incompatibleMajorVersion
        }
        let allowed: Set<XPCRequestKind>
        switch envelope.capability {
        case .query:
            allowed = [.health, .querySummary, .queryEvidence, .queryRecommendations]
        case .control:
            allowed = [.setCollectionState, .applyAnnotation]
        case .export:
            allowed = [.startExport]
        case .destructiveDelete:
            allowed = [.requestDeletion]
        }
        guard allowed.contains(envelope.kind) else {
            throw XPCContractError.capabilityDoesNotPermitKind
        }
    }

    public static func validate(_ query: SummaryQuery) throws {
        try validateScope(
            XPCScopedQuery(
                from: query.from,
                to: query.to,
                repositoryID: query.repositoryID,
                workUnitID: query.workUnitID
            )
        )
        guard query.metricNames.count <= maximumSummaryMetrics else {
            throw XPCContractError.tooManyMetrics
        }
    }

    public static func validate(_ query: XPCEvidenceQuery) throws {
        try validateScope(query.scope)
        guard (1...maximumEvidenceRecords).contains(query.limit) else {
            throw XPCContractError.pageLimitExceeded
        }
    }

    public static func validateScope(_ query: XPCScopedQuery) throws {
        guard query.to >= query.from,
              query.to.timeIntervalSince(query.from) <= Double(maximumQueryDays * 86_400)
        else {
            throw XPCContractError.invalidTimeRange
        }
        guard query.repositoryID?.isEmpty != true, query.workUnitID?.isEmpty != true else {
            throw XPCContractError.invalidScope
        }
    }
}

@objc public protocol WWMDXPCService {
    func getHealth(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func querySummary(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func queryEvidence(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func queryRecommendations(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func setCollectionState(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func applyAnnotation(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func startExport(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func requestDeletion(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

public struct XPCPeerPolicy: Codable, Equatable, Sendable {
    public let expectedTeamID: String
    public let expectedBundleIdentifier: String
    public let requiredEntitlement: String

    public init(expectedTeamID: String, expectedBundleIdentifier: String, requiredEntitlement: String) {
        self.expectedTeamID = expectedTeamID
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.requiredEntitlement = requiredEntitlement
    }
}

public struct XPCHealthResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let eventCount: Int
    public let quickCheckPassed: Bool
    public let globallyPaused: Bool

    public init(schemaVersion: Int, eventCount: Int, quickCheckPassed: Bool, globallyPaused: Bool) {
        self.schemaVersion = schemaVersion
        self.eventCount = eventCount
        self.quickCheckPassed = quickCheckPassed
        self.globallyPaused = globallyPaused
    }
}

public struct XPCMetricResponse: Codable, Equatable, Sendable {
    public let name: String
    public let value: Double?
    public let unit: String
    public let evidenceCount: Int
    public let availability: String
    public let explanation: String

    public init(
        name: String,
        value: Double?,
        unit: String,
        evidenceCount: Int,
        availability: String,
        explanation: String
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.evidenceCount = evidenceCount
        self.availability = availability
        self.explanation = explanation
    }
}

public struct XPCSummaryResponse: Codable, Equatable, Sendable {
    public let eventCount: Int
    public let processedThroughSequence: Int64
    public let metrics: [XPCMetricResponse]

    public init(eventCount: Int, processedThroughSequence: Int64, metrics: [XPCMetricResponse]) {
        self.eventCount = eventCount
        self.processedThroughSequence = processedThroughSequence
        self.metrics = metrics
    }
}

/// Safe evidence never includes payloads, source-native identifiers, paths,
/// prompts, titles, arguments, or user-sensitive events.
public struct XPCEvidenceItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sequence: Int64
    public let kind: String
    public let occurredAt: Date?
    public let observedAt: Date
    public let adapterID: String
    public let repositoryID: String?
    public let workUnitID: String?

    public init(
        id: UUID,
        sequence: Int64,
        kind: String,
        occurredAt: Date?,
        observedAt: Date,
        adapterID: String,
        repositoryID: String?,
        workUnitID: String?
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.occurredAt = occurredAt
        self.observedAt = observedAt
        self.adapterID = adapterID
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
    }
}

public struct XPCEvidenceResponse: Codable, Equatable, Sendable {
    public let items: [XPCEvidenceItem]

    public init(items: [XPCEvidenceItem]) {
        self.items = items
    }
}

public struct XPCRecommendationItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let ruleID: String
    public let ruleVersion: Int
    public let scopeKey: String
    public let severity: String
    public let evidenceGrade: String
    public let title: String
    public let explanation: String
    public let observationMetricNames: [String]

    public init(
        id: String,
        ruleID: String,
        ruleVersion: Int,
        scopeKey: String,
        severity: String,
        evidenceGrade: String,
        title: String,
        explanation: String,
        observationMetricNames: [String]
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.scopeKey = scopeKey
        self.severity = severity
        self.evidenceGrade = evidenceGrade
        self.title = title
        self.explanation = explanation
        self.observationMetricNames = observationMetricNames
    }
}

public struct XPCRecommendationsResponse: Codable, Equatable, Sendable {
    public let items: [XPCRecommendationItem]

    public init(items: [XPCRecommendationItem]) {
        self.items = items
    }
}

public struct XPCCollectionStateResponse: Codable, Equatable, Sendable {
    public let globallyPaused: Bool

    public init(globallyPaused: Bool) {
        self.globallyPaused = globallyPaused
    }
}

public enum XPCCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public enum XPCSecurityRequirement {
    public static let implementationNote =
        "The agent must set an explicit NSXPCListener connection code-signing requirement before activation, and clients must set the expected agent requirement before activation. This source contract intentionally does not provide an unsigned fallback."
}
