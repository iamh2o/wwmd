import Foundation
import WWMDAnalytics
import WWMDAdapters
import WWMDCore
import WWMDIPC
import WWMDStorage

public enum WWMDAgentError: Error, Equatable, Sendable, LocalizedError {
    case collectionPaused
    case adapterNotOptedIn
    case adapterDisabled
    case checkpointScopeMismatch
    case queryResultLimitExceeded(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .collectionPaused:
            "WWMD collection is globally paused."
        case .adapterNotOptedIn:
            "The adapter has no explicit opt-in state for this configuration."
        case .adapterDisabled:
            "The adapter is explicitly disabled for this configuration."
        case .checkpointScopeMismatch:
            "The source checkpoint does not match the explicit adapter configuration."
        case .queryResultLimitExceeded(let maximum):
            "The requested query has more than \(maximum) matching events. Narrow the explicit time or metadata scope."
        }
    }
}

public actor WWMDAgentRuntime {
    public static let maximumSummaryEvents = 500

    private let store: TelemetryStore
    private let identity: LocalIdentity

    public init(store: TelemetryStore, identity: LocalIdentity) {
        self.store = store
        self.identity = identity
    }

    public func health() async throws -> StoreHealth {
        try await store.health()
    }

    public func collectionState() async throws -> CollectionState {
        try await store.collectionState()
    }

    public func setGlobalPause(_ paused: Bool) async throws {
        try await store.setGlobalPause(paused)
    }

    public func setCollectionState(_ paused: Bool) async throws -> XPCCollectionStateResponse {
        try await store.setGlobalPause(paused)
        return XPCCollectionStateResponse(globallyPaused: try await store.collectionState().globallyPaused)
    }

    public func setAdapterEnabled(
        adapterID: String,
        configurationID: String,
        enabled: Bool
    ) async throws {
        try await store.setAdapterEnabled(
            adapterID: adapterID,
            configurationID: configurationID,
            enabled: enabled
        )
    }

    public func ingest(
        offer: SourceEventOffer,
        configurationID: String,
        checkpoint: AdapterCheckpoint? = nil
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: offer.descriptor.id,
            configurationID: configurationID
        )
        if let checkpoint {
            guard checkpoint.adapterID == offer.descriptor.id,
                  checkpoint.configurationID == configurationID
            else {
                throw WWMDAgentError.checkpointScopeMismatch
            }
        }
        let event = try TelemetryEventFactory.make(offer: offer, identity: identity)
        return try await store.persist(events: [event], checkpoint: checkpoint)
    }

    /// Reads only the exact user-selected repository root. Consent is checked
    /// before invoking Git and checked again by `ingest` before persistence.
    public func ingestGitLatestCommit<Runner: GitCommandRunning>(
        at explicitRepositoryRoot: URL,
        configurationID: String,
        reader: GitMetadataReader<Runner>
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.git.id,
            configurationID: configurationID
        )
        let snapshot = try reader.latestCommit(at: explicitRepositoryRoot)
        let offer = GitMetadataAdapter.commitOffer(snapshot.commitInput)
        let checkpoint = AdapterCheckpoint(
            adapterID: V0AdapterDescriptors.git.id,
            configurationID: configurationID,
            cursor: snapshot.commitInput.commitOID,
            sourceContractVersion: V0AdapterDescriptors.git.version
        )
        return try await ingest(offer: offer, configurationID: configurationID, checkpoint: checkpoint)
    }

    public func ingestGitLatestCommit(
        at explicitRepositoryRoot: URL,
        configurationID: String
    ) async throws -> PersistenceReceipt {
        try await ingestGitLatestCommit(
            at: explicitRepositoryRoot,
            configurationID: configurationID,
            reader: GitMetadataReader(runner: SystemGitCommandRunner())
        )
    }

    /// Runs an explicit user-provided build/test command only after that exact
    /// adapter configuration is opted in. Arguments and output remain
    /// ephemeral inside the supplied runner.
    public func runExplicitValidation<Runner: ValidationProcessRunning>(
        _ request: ExplicitValidationRequest,
        configurationID: String,
        runner: ExplicitValidationRunner<Runner>
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.build.id,
            configurationID: configurationID
        )
        let offer = try runner.execute(request)
        return try await ingest(offer: offer, configurationID: configurationID)
    }

    public func recordSafeActivity(
        _ input: SafeActivitySessionInput,
        configurationID: String
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.activity.id,
            configurationID: configurationID
        )
        return try await ingest(
            offer: SafeActivityAdapter.sessionOffer(input),
            configurationID: configurationID
        )
    }

    public func recordWorkUnitOutcome(
        _ input: WorkUnitOutcomeInput,
        configurationID: String
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.annotation.id,
            configurationID: configurationID
        )
        return try await ingest(
            offer: AnnotationAdapter.outcomeOffer(input),
            configurationID: configurationID
        )
    }

    public func recordRecommendationControl(
        _ input: RecommendationControlInput,
        configurationID: String
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.annotation.id,
            configurationID: configurationID
        )
        return try await ingest(
            offer: AnnotationAdapter.recommendationControlOffer(input),
            configurationID: configurationID
        )
    }

    public func recordAssociationCorrection(
        _ input: AssociationCorrectionInput,
        configurationID: String
    ) async throws -> PersistenceReceipt {
        try await assertCollectionPermitted(
            adapterID: V0AdapterDescriptors.annotation.id,
            configurationID: configurationID
        )
        return try await ingest(
            offer: AnnotationAdapter.associationCorrectionOffer(input),
            configurationID: configurationID
        )
    }

    public func projection(
        workUnits: [WorkUnit]
    ) async throws -> ProjectionSnapshot {
        let events = try await store.events(after: 0)
        return ProjectionEngine.rebuild(events: events, workUnits: workUnits)
    }

    public func summary(query: SummaryQuery) async throws -> XPCSummaryResponse {
        try XPCContractValidator.validate(query)
        let events = try await boundedEvents(
            scope: XPCScopedQuery(
                from: query.from,
                to: query.to,
                repositoryID: query.repositoryID,
                workUnitID: query.workUnitID
            ),
            maximum: Self.maximumSummaryEvents
        )
        let safeEvents = events.filter { $0.sensitivity != .userSensitive }
        let snapshot = ProjectionEngine.rebuild(events: safeEvents, workUnits: [])
        let requested = Set(query.metricNames)
        let metrics = snapshot.metrics
            .filter { requested.isEmpty || requested.contains($0.name) }
            .map {
                XPCMetricResponse(
                    name: $0.name,
                    value: $0.value,
                    unit: $0.unit,
                    evidenceCount: $0.evidenceCount,
                    availability: $0.availability.rawValue,
                    explanation: $0.explanation
                )
            }
        return XPCSummaryResponse(
            eventCount: safeEvents.count,
            processedThroughSequence: snapshot.processedThroughSequence,
            metrics: metrics
        )
    }

    public func evidence(query: XPCEvidenceQuery) async throws -> XPCEvidenceResponse {
        try XPCContractValidator.validate(query)
        let events = try await boundedEvents(scope: query.scope, maximum: query.limit)
        let items = events
            .filter { $0.sensitivity != .userSensitive }
            .compactMap { event -> XPCEvidenceItem? in
                guard let sequence = event.sequence else { return nil }
                return XPCEvidenceItem(
                    id: event.eventID,
                    sequence: sequence,
                    kind: event.kind.rawValue,
                    occurredAt: event.occurredAt,
                    observedAt: event.observedAt,
                    adapterID: event.adapterID,
                    repositoryID: event.repositoryID,
                    workUnitID: event.workUnitID
                )
            }
        return XPCEvidenceResponse(items: items)
    }

    public func recommendations(query: XPCScopedQuery) async throws -> XPCRecommendationsResponse {
        try XPCContractValidator.validateScope(query)
        let events = try await boundedEvents(scope: query, maximum: Self.maximumSummaryEvents)
        let snapshot = ProjectionEngine.rebuild(events: events, workUnits: [])
        return XPCRecommendationsResponse(
            items: snapshot.recommendations.map {
                XPCRecommendationItem(
                    id: $0.id,
                    ruleID: $0.ruleID,
                    ruleVersion: $0.ruleVersion,
                    scopeKey: $0.scopeKey,
                    severity: $0.severity.rawValue,
                    evidenceGrade: $0.evidenceGrade,
                    title: $0.title,
                    explanation: $0.explanation,
                    observationMetricNames: $0.observationMetricNames
                )
            }
        )
    }

    private func boundedEvents(scope: XPCScopedQuery, maximum: Int) async throws -> [TelemetryEvent] {
        let query = TelemetryEventQuery(
            from: scope.from,
            to: scope.to,
            repositoryID: scope.repositoryID,
            workUnitID: scope.workUnitID,
            limit: maximum
        )
        let count = try await store.eventCount(matching: query)
        guard count <= maximum else {
            throw WWMDAgentError.queryResultLimitExceeded(maximum: maximum)
        }
        return try await store.events(matching: query)
    }

    private func assertCollectionPermitted(
        adapterID: String,
        configurationID: String
    ) async throws {
        let collectionState = try await store.collectionState()
        guard !collectionState.globallyPaused else {
            throw WWMDAgentError.collectionPaused
        }
        guard let adapterState = try await store.adapterCollectionState(
            adapterID: adapterID,
            configurationID: configurationID
        ) else {
            throw WWMDAgentError.adapterNotOptedIn
        }
        guard adapterState.enabled else {
            throw WWMDAgentError.adapterDisabled
        }
    }
}
