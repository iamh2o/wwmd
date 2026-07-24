import CryptoKit
import Foundation

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum MeasurementClass: String, Codable, CaseIterable, Sendable {
    case measured
    case derived
    case estimated
    case userSupplied = "user_supplied"
}

public enum Sensitivity: String, Codable, CaseIterable, Sendable, Comparable {
    case publicMetadata = "public_metadata"
    case privateMetadata = "private_metadata"
    case userSensitive = "user_sensitive"

    public static func < (lhs: Sensitivity, rhs: Sensitivity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .publicMetadata: 0
        case .privateMetadata: 1
        case .userSensitive: 2
        }
    }
}

public enum RedactionState: String, Codable, CaseIterable, Sendable {
    case passed
    case redacted
    case rejected
    case quarantined
}

public enum TelemetryEventKind: String, Codable, CaseIterable, Sendable {
    case aiTurn = "ai.turn"
    case gitCommit = "git.commit"
    case gitLifecycle = "git.lifecycle"
    case validationResult = "validation.result"
    case activitySession = "activity.session"
    case workUnitDeclared = "work_unit.declared"
    case workUnitOutcomeDeclared = "work_unit.outcome_declared"
    case associationCorrected = "association.corrected"
    case recommendationEmitted = "recommendation.emitted"
    case recommendationDismissed = "recommendation.dismissed"
    case adapterHealth = "adapter.health"
    case diagnostic = "diagnostic"
}

public struct FieldProvenance: Codable, Equatable, Sendable {
    public let source: String
    public let measurement: MeasurementClass
    public let transformation: String?

    public init(source: String, measurement: MeasurementClass, transformation: String? = nil) {
        self.source = source
        self.measurement = measurement
        self.transformation = transformation
    }
}

public struct LocalIdentity: Codable, Equatable, Sendable {
    public let actorID: UUID
    public let deviceID: UUID

    public init(actorID: UUID = UUID(), deviceID: UUID = UUID()) {
        self.actorID = actorID
        self.deviceID = deviceID
    }
}

public struct TelemetryEvent: Codable, Equatable, Sendable, Identifiable {
    public let eventID: UUID
    public let schemaName: String
    public let schemaVersion: Int
    public let sequence: Int64?
    public let adapterID: String
    public let adapterVersion: String
    public let sourceNativeID: String?
    public let sourceIdempotencyKey: String
    public let kind: TelemetryEventKind
    public let occurredAt: Date?
    public let observedAt: Date
    public let persistedAt: Date?
    public let monotonicNanoseconds: UInt64?
    public let actorID: UUID
    public let deviceID: UUID
    public let projectID: String?
    public let repositoryID: String?
    public let worktreeID: String?
    public let branch: String?
    public let provider: String?
    public let client: String?
    public let model: String?
    public let threadID: String?
    public let turnID: String?
    public let workUnitID: String?
    public let parentEventIDs: [UUID]
    public let payload: [String: JSONValue]
    public let sensitivity: Sensitivity
    public let redactionState: RedactionState
    public let provenance: [String: FieldProvenance]
    public let confidence: Double?

    public var id: UUID { eventID }

    public init(
        eventID: UUID = UUID(),
        schemaName: String = "TelemetryEvent",
        schemaVersion: Int = 1,
        sequence: Int64? = nil,
        adapterID: String,
        adapterVersion: String,
        sourceNativeID: String? = nil,
        sourceIdempotencyKey: String,
        kind: TelemetryEventKind,
        occurredAt: Date?,
        observedAt: Date,
        persistedAt: Date? = nil,
        monotonicNanoseconds: UInt64? = nil,
        actorID: UUID,
        deviceID: UUID,
        projectID: String? = nil,
        repositoryID: String? = nil,
        worktreeID: String? = nil,
        branch: String? = nil,
        provider: String? = nil,
        client: String? = nil,
        model: String? = nil,
        threadID: String? = nil,
        turnID: String? = nil,
        workUnitID: String? = nil,
        parentEventIDs: [UUID] = [],
        payload: [String: JSONValue],
        sensitivity: Sensitivity,
        redactionState: RedactionState,
        provenance: [String: FieldProvenance],
        confidence: Double? = nil
    ) {
        self.eventID = eventID
        self.schemaName = schemaName
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.sourceNativeID = sourceNativeID
        self.sourceIdempotencyKey = sourceIdempotencyKey
        self.kind = kind
        self.occurredAt = occurredAt
        self.observedAt = observedAt
        self.persistedAt = persistedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.actorID = actorID
        self.deviceID = deviceID
        self.projectID = projectID
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.branch = branch
        self.provider = provider
        self.client = client
        self.model = model
        self.threadID = threadID
        self.turnID = turnID
        self.workUnitID = workUnitID
        self.parentEventIDs = parentEventIDs
        self.payload = payload
        self.sensitivity = sensitivity
        self.redactionState = redactionState
        self.provenance = provenance
        self.confidence = confidence
    }

    public func persisted(sequence: Int64, at date: Date) -> TelemetryEvent {
        TelemetryEvent(
            eventID: eventID,
            schemaName: schemaName,
            schemaVersion: schemaVersion,
            sequence: sequence,
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            sourceNativeID: sourceNativeID,
            sourceIdempotencyKey: sourceIdempotencyKey,
            kind: kind,
            occurredAt: occurredAt,
            observedAt: observedAt,
            persistedAt: date,
            monotonicNanoseconds: monotonicNanoseconds,
            actorID: actorID,
            deviceID: deviceID,
            projectID: projectID,
            repositoryID: repositoryID,
            worktreeID: worktreeID,
            branch: branch,
            provider: provider,
            client: client,
            model: model,
            threadID: threadID,
            turnID: turnID,
            workUnitID: workUnitID,
            parentEventIDs: parentEventIDs,
            payload: payload,
            sensitivity: sensitivity,
            redactionState: redactionState,
            provenance: provenance,
            confidence: confidence
        )
    }
}

public struct AdapterDescriptor: Sendable, Equatable {
    public let id: String
    public let version: String
    public let supportedKinds: Set<TelemetryEventKind>
    public let allowedPayloadKeys: Set<String>
    public let sensitivityCeiling: Sensitivity

    public init(
        id: String,
        version: String,
        supportedKinds: Set<TelemetryEventKind>,
        allowedPayloadKeys: Set<String>,
        sensitivityCeiling: Sensitivity
    ) {
        self.id = id
        self.version = version
        self.supportedKinds = supportedKinds
        self.allowedPayloadKeys = allowedPayloadKeys
        self.sensitivityCeiling = sensitivityCeiling
    }
}

public struct SourceEventOffer: Sendable, Equatable {
    public let descriptor: AdapterDescriptor
    public let sourceNativeID: String?
    public let sourceIdempotencyKey: String
    public let kind: TelemetryEventKind
    public let occurredAt: Date?
    public let observedAt: Date
    public let monotonicNanoseconds: UInt64?
    public let projectID: String?
    public let repositoryID: String?
    public let worktreeID: String?
    public let branch: String?
    public let provider: String?
    public let client: String?
    public let model: String?
    public let threadID: String?
    public let turnID: String?
    public let workUnitID: String?
    public let parentEventIDs: [UUID]
    public let payload: [String: JSONValue]
    public let sensitivity: Sensitivity
    public let provenance: [String: FieldProvenance]
    public let confidence: Double?

    public init(
        descriptor: AdapterDescriptor,
        sourceNativeID: String? = nil,
        sourceIdempotencyKey: String,
        kind: TelemetryEventKind,
        occurredAt: Date?,
        observedAt: Date = Date(),
        monotonicNanoseconds: UInt64? = nil,
        projectID: String? = nil,
        repositoryID: String? = nil,
        worktreeID: String? = nil,
        branch: String? = nil,
        provider: String? = nil,
        client: String? = nil,
        model: String? = nil,
        threadID: String? = nil,
        turnID: String? = nil,
        workUnitID: String? = nil,
        parentEventIDs: [UUID] = [],
        payload: [String: JSONValue],
        sensitivity: Sensitivity,
        provenance: [String: FieldProvenance],
        confidence: Double? = nil
    ) {
        self.descriptor = descriptor
        self.sourceNativeID = sourceNativeID
        self.sourceIdempotencyKey = sourceIdempotencyKey
        self.kind = kind
        self.occurredAt = occurredAt
        self.observedAt = observedAt
        self.monotonicNanoseconds = monotonicNanoseconds
        self.projectID = projectID
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.branch = branch
        self.provider = provider
        self.client = client
        self.model = model
        self.threadID = threadID
        self.turnID = turnID
        self.workUnitID = workUnitID
        self.parentEventIDs = parentEventIDs
        self.payload = payload
        self.sensitivity = sensitivity
        self.provenance = provenance
        self.confidence = confidence
    }
}

public enum TelemetryValidationError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedKind
    case undeclaredPayloadField(String)
    case missingPayloadProvenance(String)
    case unexpectedPayloadProvenance(String)
    case prohibitedPayloadField(String)
    case suspectedSecret
    case invalidConfidence
    case sensitivityAboveAdapterCeiling
    case invalidSchemaVersion
    case invalidMetadataValue(String)
    case unsupportedPayloadShape
    case nonFinitePayloadNumber

    public var errorDescription: String? {
        switch self {
        case .unsupportedKind:
            "The adapter is not allowed to emit this event kind."
        case .undeclaredPayloadField(let field):
            "The adapter offered an undeclared payload field: \(field)."
        case .missingPayloadProvenance(let field):
            "The payload field lacks provenance: \(field)."
        case .unexpectedPayloadProvenance(let field):
            "Provenance exists for a payload field that is not present: \(field)."
        case .prohibitedPayloadField(let field):
            "The payload field is prohibited by the privacy policy: \(field)."
        case .suspectedSecret:
            "The payload contains a value shaped like a secret."
        case .invalidConfidence:
            "Confidence must be in the closed interval from zero to one."
        case .sensitivityAboveAdapterCeiling:
            "The offered sensitivity exceeds the adapter descriptor ceiling."
        case .invalidSchemaVersion:
            "Unsupported telemetry event schema version."
        case .invalidMetadataValue(let field):
            "The metadata field is not a bounded opaque identifier: \(field)."
        case .unsupportedPayloadShape:
            "WWMD V0 payloads may contain only scalar metadata values."
        case .nonFinitePayloadNumber:
            "Payload numbers must be finite."
        }
    }
}

public enum PrivacyGate {
    private static let prohibitedFragments = [
        "prompt", "response", "content", "window_title", "title", "command",
        "argument", "environment", "clipboard", "screenshot", "keystroke",
        "browser_history", "log"
    ]
    private static let secretFieldNames = [
        "api_key", "access_token", "refresh_token", "secret", "password",
        "private_key", "authorization"
    ]
    private static let opaqueIdentifierCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._:-/+@")
    )
    private static let branchCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._:-/+@")
    )

    public static func validate(_ offer: SourceEventOffer) throws {
        guard offer.descriptor.supportedKinds.contains(offer.kind) else {
            throw TelemetryValidationError.unsupportedKind
        }
        guard offer.sensitivity <= offer.descriptor.sensitivityCeiling else {
            throw TelemetryValidationError.sensitivityAboveAdapterCeiling
        }
        if let confidence = offer.confidence, !(0.0...1.0).contains(confidence) {
            throw TelemetryValidationError.invalidConfidence
        }
        try validateMetadata(offer)

        for key in offer.payload.keys {
            guard offer.descriptor.allowedPayloadKeys.contains(key) else {
                throw TelemetryValidationError.undeclaredPayloadField(key)
            }
            guard offer.provenance[key] != nil else {
                throw TelemetryValidationError.missingPayloadProvenance(key)
            }
            let normalized = key.lowercased()
            if prohibitedFragments.contains(where: { normalized.contains($0) }) {
                throw TelemetryValidationError.prohibitedPayloadField(key)
            }
            if secretFieldNames.contains(where: { normalized == $0 || normalized.contains("\($0)_") }) {
                throw TelemetryValidationError.prohibitedPayloadField(key)
            }
        }
        for key in offer.provenance.keys where offer.payload[key] == nil {
            throw TelemetryValidationError.unexpectedPayloadProvenance(key)
        }
        try validatePayloadValues(offer.payload)
        if containsSecretShape(offer.payload) || containsSecretShape(in: metadataStrings(from: offer)) {
            throw TelemetryValidationError.suspectedSecret
        }
    }

    private static func validateMetadata(_ offer: SourceEventOffer) throws {
        try requireOpaque(offer.descriptor.id, field: "adapter_id", maximumLength: 128)
        try requireOpaque(offer.descriptor.version, field: "adapter_version", maximumLength: 64)
        try requireOpaque(offer.sourceIdempotencyKey, field: "source_idempotency_key", maximumLength: 256)
        try requireOptionalOpaque(offer.sourceNativeID, field: "source_native_id", maximumLength: 256)
        try requireOptionalOpaque(offer.projectID, field: "project_id", maximumLength: 128)
        try requireOptionalOpaque(offer.repositoryID, field: "repository_id", maximumLength: 128)
        try requireOptionalOpaque(offer.worktreeID, field: "worktree_id", maximumLength: 128)
        try requireOptionalOpaque(offer.branch, field: "branch", maximumLength: 256, allowed: branchCharacters)
        try requireOptionalOpaque(offer.provider, field: "provider", maximumLength: 128)
        try requireOptionalOpaque(offer.client, field: "client", maximumLength: 128)
        try requireOptionalOpaque(offer.model, field: "model", maximumLength: 128)
        try requireOptionalOpaque(offer.threadID, field: "thread_id", maximumLength: 128)
        try requireOptionalOpaque(offer.turnID, field: "turn_id", maximumLength: 128)
        try requireOptionalOpaque(offer.workUnitID, field: "work_unit_id", maximumLength: 128)
        for (field, provenance) in offer.provenance {
            try requireOpaque(field, field: "provenance_field", maximumLength: 128)
            try requireOpaque(provenance.source, field: "provenance_source", maximumLength: 128)
            try requireOptionalOpaque(provenance.transformation, field: "provenance_transformation", maximumLength: 128)
        }
    }

    private static func validatePayloadValues(_ payload: [String: JSONValue]) throws {
        for value in payload.values {
            switch value {
            case .string(let string):
                try requireOpaque(string, field: "payload_value", maximumLength: 256)
            case .number(let number):
                guard number.isFinite else {
                    throw TelemetryValidationError.nonFinitePayloadNumber
                }
            case .boolean, .null:
                continue
            case .object, .array:
                throw TelemetryValidationError.unsupportedPayloadShape
            }
        }
    }

    private static func requireOptionalOpaque(
        _ value: String?,
        field: String,
        maximumLength: Int,
        allowed: CharacterSet = opaqueIdentifierCharacters
    ) throws {
        if let value {
            try requireOpaque(value, field: field, maximumLength: maximumLength, allowed: allowed)
        }
    }

    private static func requireOpaque(
        _ value: String,
        field: String,
        maximumLength: Int,
        allowed: CharacterSet = opaqueIdentifierCharacters
    ) throws {
        guard !value.isEmpty,
              value.count <= maximumLength,
              value.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw TelemetryValidationError.invalidMetadataValue(field)
        }
    }

    private static func metadataStrings(from offer: SourceEventOffer) -> [String] {
        [
            offer.descriptor.id,
            offer.descriptor.version,
            offer.sourceIdempotencyKey,
            offer.sourceNativeID,
            offer.projectID,
            offer.repositoryID,
            offer.worktreeID,
            offer.branch,
            offer.provider,
            offer.client,
            offer.model,
            offer.threadID,
            offer.turnID,
            offer.workUnitID
        ].compactMap { $0 }
        + offer.provenance.flatMap { [$0.key, $0.value.source, $0.value.transformation].compactMap { $0 } }
    }

    private static func containsSecretShape(_ value: [String: JSONValue]) -> Bool {
        value.values.contains(where: containsSecretShape)
    }

    private static func containsSecretShape(in values: [String]) -> Bool {
        values.contains { value in
            let prefixes = ["sk-", "AKIA", "ghp_", "github_pat_"]
            return prefixes.contains(where: value.hasPrefix)
        }
    }

    private static func containsSecretShape(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text):
            let prefixes = ["sk-", "AKIA", "ghp_", "github_pat_"]
            return prefixes.contains(where: text.hasPrefix)
        case .object(let object):
            return containsSecretShape(object)
        case .array(let array):
            return array.contains(where: containsSecretShape)
        case .number, .boolean, .null:
            return false
        }
    }
}

public enum TelemetryEventFactory {
    public static func make(offer: SourceEventOffer, identity: LocalIdentity) throws -> TelemetryEvent {
        try PrivacyGate.validate(offer)
        return TelemetryEvent(
            adapterID: offer.descriptor.id,
            adapterVersion: offer.descriptor.version,
            sourceNativeID: offer.sourceNativeID,
            sourceIdempotencyKey: offer.sourceIdempotencyKey,
            kind: offer.kind,
            occurredAt: offer.occurredAt,
            observedAt: offer.observedAt,
            monotonicNanoseconds: offer.monotonicNanoseconds,
            actorID: identity.actorID,
            deviceID: identity.deviceID,
            projectID: offer.projectID,
            repositoryID: offer.repositoryID,
            worktreeID: offer.worktreeID,
            branch: offer.branch,
            provider: offer.provider,
            client: offer.client,
            model: offer.model,
            threadID: offer.threadID,
            turnID: offer.turnID,
            workUnitID: offer.workUnitID,
            parentEventIDs: offer.parentEventIDs,
            payload: offer.payload,
            sensitivity: offer.sensitivity,
            redactionState: .passed,
            provenance: offer.provenance,
            confidence: offer.confidence
        )
    }
}

public enum StableHash {
    public static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AdapterHealthState: String, Codable, CaseIterable, Sendable {
    case disabled
    case blocked
    case starting
    case healthy
    case paused
    case degraded
    case incompatible
    case failed
}

public struct AdapterCheckpoint: Codable, Equatable, Sendable {
    public let adapterID: String
    public let configurationID: String
    public let cursor: String
    public let sourceContractVersion: String
    public let updatedAt: Date

    public init(
        adapterID: String,
        configurationID: String,
        cursor: String,
        sourceContractVersion: String,
        updatedAt: Date = Date()
    ) {
        self.adapterID = adapterID
        self.configurationID = configurationID
        self.cursor = cursor
        self.sourceContractVersion = sourceContractVersion
        self.updatedAt = updatedAt
    }
}

public struct ProjectionCheckpoint: Codable, Equatable, Sendable {
    public let projectionName: String
    public let projectionVersion: Int
    public let lastSequence: Int64
    public let rebuildGeneration: Int
    public let updatedAt: Date

    public init(
        projectionName: String,
        projectionVersion: Int,
        lastSequence: Int64,
        rebuildGeneration: Int,
        updatedAt: Date = Date()
    ) {
        self.projectionName = projectionName
        self.projectionVersion = projectionVersion
        self.lastSequence = lastSequence
        self.rebuildGeneration = rebuildGeneration
        self.updatedAt = updatedAt
    }
}
