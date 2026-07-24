import Foundation
import WWMDCore

public enum AdapterContractError: Error, Equatable, Sendable, LocalizedError {
    case missingCodexCSVContract
    case emptyCodexCSVContract
    case headerMismatch(expected: [String], actual: [String])
    case duplicateAdapterID(String)
    case invalidValidationCategory
    case invalidRecommendationControl
    case invalidAssociationCorrection

    public var errorDescription: String? {
        switch self {
        case .missingCodexCSVContract:
            "Codex CSV import is blocked until an exact source contract is supplied."
        case .emptyCodexCSVContract:
            "A Codex CSV contract must declare a non-empty exact header list."
        case .headerMismatch(let expected, let actual):
            "Codex CSV headers did not match the configured contract. Expected \(expected), received \(actual)."
        case .duplicateAdapterID(let id):
            "A static adapter descriptor is already registered for \(id)."
        case .invalidValidationCategory:
            "Only explicit build or test categories are accepted."
        case .invalidRecommendationControl:
            "A recommendation control has an invalid disposition or snooze time."
        case .invalidAssociationCorrection:
            "An association correction must either select a work unit or clear the association."
        }
    }
}

public struct CodexCSVContract: Codable, Equatable, Sendable {
    public let version: String
    public let exactHeaders: [String]
    public let sourceIDRule: String
    public let timestampSemantics: String

    public init(version: String, exactHeaders: [String], sourceIDRule: String, timestampSemantics: String) {
        self.version = version
        self.exactHeaders = exactHeaders
        self.sourceIDRule = sourceIDRule
        self.timestampSemantics = timestampSemantics
    }
}

public enum CodexCSVImportGate {
    public static func validate(headers: [String], contract: CodexCSVContract?) throws {
        guard let contract else {
            throw AdapterContractError.missingCodexCSVContract
        }
        guard !contract.exactHeaders.isEmpty,
              !contract.sourceIDRule.isEmpty,
              !contract.timestampSemantics.isEmpty
        else {
            throw AdapterContractError.emptyCodexCSVContract
        }
        guard headers == contract.exactHeaders else {
            throw AdapterContractError.headerMismatch(expected: contract.exactHeaders, actual: headers)
        }
    }
}

public struct StaticAdapterRegistry: Sendable {
    private var descriptors: [String: AdapterDescriptor]

    public init() {
        descriptors = [:]
    }

    public mutating func register(_ descriptor: AdapterDescriptor) throws {
        guard descriptors[descriptor.id] == nil else {
            throw AdapterContractError.duplicateAdapterID(descriptor.id)
        }
        descriptors[descriptor.id] = descriptor
    }

    public func descriptor(id: String) -> AdapterDescriptor? {
        descriptors[id]
    }

    public var allDescriptors: [AdapterDescriptor] {
        descriptors.values.sorted { $0.id < $1.id }
    }
}

public enum V0AdapterDescriptors {
    public static let git = AdapterDescriptor(
        id: "git.local",
        version: "1",
        supportedKinds: [.gitCommit, .gitLifecycle],
        allowedPayloadKeys: ["commit_oid", "parent_count", "changed_file_count", "insertions", "deletions", "lifecycle"],
        sensitivityCeiling: .privateMetadata
    )

    public static let build = AdapterDescriptor(
        id: "build.wrapper",
        version: "1",
        supportedKinds: [.validationResult],
        allowedPayloadKeys: ["category", "started_at", "duration_ms", "aggregate_status", "repository_id"],
        sensitivityCeiling: .privateMetadata
    )

    public static let activity = AdapterDescriptor(
        id: "activity.safe",
        version: "1",
        supportedKinds: [.activitySession],
        allowedPayloadKeys: ["session_state", "application_bundle_id", "repository_id"],
        sensitivityCeiling: .privateMetadata
    )

    public static let annotation = AdapterDescriptor(
        id: "annotation.local",
        version: "1",
        supportedKinds: [.workUnitDeclared, .workUnitOutcomeDeclared, .associationCorrected, .recommendationDismissed],
        allowedPayloadKeys: ["work_unit_id", "kind", "outcome", "repository_id", "event_id", "correction", "recommendation_id", "disposition", "reason_code", "snooze_until"],
        sensitivityCeiling: .userSensitive
    )
}

public struct GitCommitInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let occurredAt: Date
    public let repositoryID: String
    public let branch: String?
    public let commitOID: String
    public let parentCount: Int
    public let changedFileCount: Int
    public let insertions: Int
    public let deletions: Int

    public init(
        idempotencyKey: String,
        occurredAt: Date,
        repositoryID: String,
        branch: String? = nil,
        commitOID: String,
        parentCount: Int,
        changedFileCount: Int,
        insertions: Int,
        deletions: Int
    ) {
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.repositoryID = repositoryID
        self.branch = branch
        self.commitOID = commitOID
        self.parentCount = parentCount
        self.changedFileCount = changedFileCount
        self.insertions = insertions
        self.deletions = deletions
    }
}

public enum GitMetadataAdapter {
    public static func commitOffer(_ input: GitCommitInput) -> SourceEventOffer {
        let payload: [String: JSONValue] = [
            "commit_oid": .string(input.commitOID),
            "parent_count": .number(Double(input.parentCount)),
            "changed_file_count": .number(Double(input.changedFileCount)),
            "insertions": .number(Double(input.insertions)),
            "deletions": .number(Double(input.deletions))
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "git.local", measurement: .measured))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.git,
            sourceNativeID: input.commitOID,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .gitCommit,
            occurredAt: input.occurredAt,
            repositoryID: input.repositoryID,
            branch: input.branch,
            payload: payload,
            sensitivity: .privateMetadata,
            provenance: provenance
        )
    }
}

public enum ValidationCategory: String, Sendable {
    case build
    case test
}

public enum AggregateValidationStatus: String, Sendable {
    case passed
    case failed
    case cancelled
}

public struct BuildTestInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let category: ValidationCategory
    public let startedAt: Date
    public let endedAt: Date
    public let status: AggregateValidationStatus
    public let repositoryID: String?
    public let workUnitID: String?

    public init(
        idempotencyKey: String,
        category: ValidationCategory,
        startedAt: Date,
        endedAt: Date,
        status: AggregateValidationStatus,
        repositoryID: String? = nil,
        workUnitID: String? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
    }
}

public enum BuildTestAdapter {
    public static func resultOffer(_ input: BuildTestInput) -> SourceEventOffer {
        let duration = max(0, input.endedAt.timeIntervalSince(input.startedAt) * 1_000)
        let payload: [String: JSONValue] = [
            "category": .string(input.category.rawValue),
            "started_at": .string(ISO8601DateFormatter().string(from: input.startedAt)),
            "duration_ms": .number(duration),
            "aggregate_status": .string(input.status.rawValue),
            "repository_id": input.repositoryID.map(JSONValue.string) ?? .null
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "build.wrapper", measurement: .measured))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.build,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .validationResult,
            occurredAt: input.endedAt,
            repositoryID: input.repositoryID,
            workUnitID: input.workUnitID,
            payload: payload,
            sensitivity: .privateMetadata,
            provenance: provenance
        )
    }
}

public struct WorkUnitOutcomeInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let occurredAt: Date
    public let workUnitID: String
    public let kind: AnnotationWorkUnitKind
    public let outcome: AnnotationOutcome
    public let repositoryID: String?

    public init(
        idempotencyKey: String,
        occurredAt: Date,
        workUnitID: String,
        kind: AnnotationWorkUnitKind,
        outcome: AnnotationOutcome,
        repositoryID: String? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.workUnitID = workUnitID
        self.kind = kind
        self.outcome = outcome
        self.repositoryID = repositoryID
    }
}

public enum AnnotationWorkUnitKind: String, CaseIterable, Sendable {
    case feature
    case bug
    case investigation
    case refactor
    case review
    case documentation
    case maintenance
    case uncategorized
}

public enum AnnotationOutcome: String, CaseIterable, Sendable {
    case completed
    case abandoned
    case deferred
}

public enum RecommendationControlDisposition: String, CaseIterable, Sendable {
    case dismissed
    case snoozed
}

public enum RecommendationControlReason: String, CaseIterable, Sendable {
    case notUseful = "not_useful"
    case notRelevant = "not_relevant"
    case alreadyAddressed = "already_addressed"
    case reviewLater = "review_later"
}

public enum AssociationCorrectionKind: String, CaseIterable, Sendable {
    case associate
    case clear
}

public struct AssociationCorrectionInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let occurredAt: Date
    public let eventID: UUID
    public let kind: AssociationCorrectionKind
    public let workUnitID: String?

    public init(
        idempotencyKey: String,
        occurredAt: Date,
        eventID: UUID,
        kind: AssociationCorrectionKind,
        workUnitID: String? = nil
    ) throws {
        switch kind {
        case .associate:
            guard let workUnitID, !workUnitID.isEmpty else {
                throw AdapterContractError.invalidAssociationCorrection
            }
        case .clear:
            guard workUnitID == nil else {
                throw AdapterContractError.invalidAssociationCorrection
            }
        }
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.eventID = eventID
        self.kind = kind
        self.workUnitID = workUnitID
    }
}

public struct RecommendationControlInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let occurredAt: Date
    public let recommendationID: String
    public let disposition: RecommendationControlDisposition
    public let reason: RecommendationControlReason
    public let snoozeUntil: Date?

    public init(
        idempotencyKey: String,
        occurredAt: Date,
        recommendationID: String,
        disposition: RecommendationControlDisposition,
        reason: RecommendationControlReason,
        snoozeUntil: Date? = nil
    ) throws {
        switch disposition {
        case .dismissed:
            guard snoozeUntil == nil else {
                throw AdapterContractError.invalidRecommendationControl
            }
        case .snoozed:
            guard let snoozeUntil, snoozeUntil > occurredAt else {
                throw AdapterContractError.invalidRecommendationControl
            }
        }
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.recommendationID = recommendationID
        self.disposition = disposition
        self.reason = reason
        self.snoozeUntil = snoozeUntil
    }
}

public enum AnnotationAdapter {
    public static func outcomeOffer(_ input: WorkUnitOutcomeInput) -> SourceEventOffer {
        let payload: [String: JSONValue] = [
            "work_unit_id": .string(input.workUnitID),
            "kind": .string(input.kind.rawValue),
            "outcome": .string(input.outcome.rawValue),
            "repository_id": input.repositoryID.map(JSONValue.string) ?? .null
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "annotation.local", measurement: .userSupplied))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.annotation,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .workUnitOutcomeDeclared,
            occurredAt: input.occurredAt,
            repositoryID: input.repositoryID,
            workUnitID: input.workUnitID,
            payload: payload,
            sensitivity: .userSensitive,
            provenance: provenance
        )
    }

    public static func recommendationControlOffer(_ input: RecommendationControlInput) -> SourceEventOffer {
        let formatter = ISO8601DateFormatter()
        let payload: [String: JSONValue] = [
            "recommendation_id": .string(input.recommendationID),
            "disposition": .string(input.disposition.rawValue),
            "reason_code": .string(input.reason.rawValue),
            "snooze_until": input.snoozeUntil.map { .string(formatter.string(from: $0)) } ?? .null
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "annotation.local", measurement: .userSupplied))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.annotation,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .recommendationDismissed,
            occurredAt: input.occurredAt,
            payload: payload,
            sensitivity: .userSensitive,
            provenance: provenance
        )
    }

    public static func associationCorrectionOffer(_ input: AssociationCorrectionInput) -> SourceEventOffer {
        let payload: [String: JSONValue] = [
            "event_id": .string(input.eventID.uuidString),
            "correction": .string(input.kind.rawValue),
            "work_unit_id": input.workUnitID.map(JSONValue.string) ?? .null
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "annotation.local", measurement: .userSupplied))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.annotation,
            sourceNativeID: input.eventID.uuidString,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .associationCorrected,
            occurredAt: input.occurredAt,
            workUnitID: input.workUnitID,
            parentEventIDs: [input.eventID],
            payload: payload,
            sensitivity: .userSensitive,
            provenance: provenance
        )
    }
}
