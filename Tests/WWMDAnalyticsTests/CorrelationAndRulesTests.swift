import XCTest
@testable import WWMDAnalytics
@testable import WWMDCore

final class CorrelationAndRulesTests: XCTestCase {
    func testCorrelationSelectsClearEvidenceWinner() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let event = try makeEvent(
            idempotency: "clear-winner",
            repositoryID: "repo-a",
            branch: "main",
            workUnitID: "wu-a",
            occurredAt: start.addingTimeInterval(60)
        )
        let workUnits = [
            WorkUnit(id: "wu-a", kind: .feature, repositoryID: "repo-a", branch: "main", startedAt: start),
            WorkUnit(id: "wu-b", kind: .bug, repositoryID: "repo-b", branch: "other", startedAt: start)
        ]

        let resolution = CorrelationEngine.resolve(event: event, workUnits: workUnits)

        XCTAssertEqual(resolution.state, .automatic)
        XCTAssertEqual(resolution.selected?.workUnitID, "wu-a")
        XCTAssertGreaterThanOrEqual(resolution.selected?.score ?? 0, 0.70)
    }

    func testCacheRatioRequiresTwentyMeasuredTurns() throws {
        let few = try (0..<19).map {
            try makeEvent(idempotency: "few-\($0)", repositoryID: "repo-a", branch: nil, workUnitID: nil, occurredAt: Date())
        }
        let enough = try (0..<20).map {
            try makeEvent(idempotency: "enough-\($0)", repositoryID: "repo-a", branch: nil, workUnitID: nil, occurredAt: Date())
        }

        XCTAssertEqual(MetricCalculator.cacheReadRatio(events: few).availability, .insufficientEvidence)
        XCTAssertEqual(MetricCalculator.cacheReadRatio(events: enough).value ?? -1, 0.25, accuracy: 0.0001)
    }

    func testDataQualityRecommendationNeedsCoverageEvidence() throws {
        let events = try (0..<20).map {
            try makeEvent(idempotency: "coverage-\($0)", repositoryID: "repo-a", branch: nil, workUnitID: nil, occurredAt: Date())
        }
        let coverage = MetricCalculator.correlationCoverage(events: events, associatedEventIDs: [])
        let recommendation = RecommendationEngine.dataQualityGap(coverage: coverage)

        XCTAssertEqual(coverage.value, 0)
        XCTAssertEqual(recommendation?.ruleID, "data.correlation_gap")
    }

    func testContextPressureNeedsMeasuredFloorAndProducesDeterministicRule() throws {
        let few = try (0..<9).map { try makeContextEvent(idempotency: "context-few-\($0)") }
        let enough = try (0..<10).map { try makeContextEvent(idempotency: "context-enough-\($0)") }

        XCTAssertEqual(MetricCalculator.contextUtilizationMean(events: few).availability, .insufficientEvidence)
        let metric = MetricCalculator.contextUtilizationMean(events: enough)
        XCTAssertEqual(metric.value ?? -1, 0.90, accuracy: 0.0001)
        XCTAssertEqual(
            RecommendationEngine.sustainedContextPressure(contextUtilization: metric)?.ruleID,
            "ai.sustained_context_pressure"
        )
    }

    func testProjectionRebuildIsDeterministic() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = try (0..<20).map {
            try makeEvent(
                idempotency: "projection-\($0)",
                repositoryID: "repo-a",
                branch: "main",
                workUnitID: "wu-a",
                occurredAt: start.addingTimeInterval(Double($0))
            )
        }
        let workUnits = [
            WorkUnit(id: "wu-a", kind: .feature, repositoryID: "repo-a", branch: "main", startedAt: start)
        ]

        let first = ProjectionEngine.rebuild(events: events, workUnits: workUnits)
        let second = ProjectionEngine.rebuild(events: events.reversed(), workUnits: workUnits)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.projectionName, "v0.summary")
        XCTAssertEqual(first.associations.filter { $0.resolution.state == .automatic }.count, 20)
    }

    func testDismissedRecommendationIsSuppressedByItsLedgerControl() throws {
        let events = try (0..<20).map {
            try makeEvent(
                idempotency: "dismissal-\($0)",
                repositoryID: "repo-a",
                branch: nil,
                workUnitID: nil,
                occurredAt: Date(timeIntervalSince1970: Double($0))
            )
        }
        let proposal = try XCTUnwrap(ProjectionEngine.rebuild(events: events, workUnits: []).recommendations.first)
        let control = try makeDismissalControl(for: proposal.id)

        let rebuilt = ProjectionEngine.rebuild(events: events + [control], workUnits: [])

        XCTAssertFalse(rebuilt.recommendations.contains(where: { $0.id == proposal.id }))
    }

    func testUserAssociationCorrectionOverridesAutomaticAssociation() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let event = try makeEvent(
            idempotency: "corrected-association",
            repositoryID: "repo-a",
            branch: "main",
            workUnitID: "wu-a",
            occurredAt: start.addingTimeInterval(10)
        )
        let correction = try makeClearCorrection(for: event.eventID)
        let snapshot = ProjectionEngine.rebuild(
            events: [event, correction],
            workUnits: [WorkUnit(id: "wu-a", kind: .feature, repositoryID: "repo-a", branch: "main", startedAt: start)]
        )

        XCTAssertEqual(
            snapshot.associations.first(where: { $0.id == event.eventID })?.resolution.state,
            .unassociated
        )
    }

    func testSnoozedRecommendationReturnsAfterItsExplicitDeadline() throws {
        let events = try (0..<20).map {
            try makeEvent(
                idempotency: "snooze-\($0)",
                repositoryID: "repo-a",
                branch: nil,
                workUnitID: nil,
                occurredAt: Date(timeIntervalSince1970: Double($0))
            )
        }
        let proposal = try XCTUnwrap(ProjectionEngine.rebuild(events: events, workUnits: []).recommendations.first)
        let control = try makeSnoozeControl(for: proposal.id, until: Date(timeIntervalSince1970: 200))

        XCTAssertFalse(
            RecommendationEngine.active(
                proposals: [proposal],
                controlEvents: [control],
                at: Date(timeIntervalSince1970: 199)
            ).contains(where: { $0.id == proposal.id })
        )
        XCTAssertTrue(
            RecommendationEngine.active(
                proposals: [proposal],
                controlEvents: [control],
                at: Date(timeIntervalSince1970: 200)
            ).contains(where: { $0.id == proposal.id })
        )
    }

    private func makeEvent(
        idempotency: String,
        repositoryID: String,
        branch: String?,
        workUnitID: String?,
        occurredAt: Date
    ) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "ai.test",
            version: "1",
            supportedKinds: [.aiTurn],
            allowedPayloadKeys: ["input_tokens", "cached_input_tokens"],
            sensitivityCeiling: .privateMetadata
        )
        let payload: [String: JSONValue] = [
            "input_tokens": .number(100),
            "cached_input_tokens": .number(25)
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "ai.test", measurement: .measured))
        })
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256(idempotency),
            kind: .aiTurn,
            occurredAt: occurredAt,
            repositoryID: repositoryID,
            branch: branch,
            workUnitID: workUnitID,
            payload: payload,
            sensitivity: .privateMetadata,
            provenance: provenance
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func makeDismissalControl(for recommendationID: String) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "annotation.test",
            version: "1",
            supportedKinds: [.recommendationDismissed],
            allowedPayloadKeys: ["recommendation_id", "disposition", "reason_code", "snooze_until"],
            sensitivityCeiling: .userSensitive
        )
        let payload: [String: JSONValue] = [
            "recommendation_id": .string(recommendationID),
            "disposition": .string("dismissed"),
            "reason_code": .string("not_useful"),
            "snooze_until": .null
        ]
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("dismissal-\(recommendationID)"),
            kind: .recommendationDismissed,
            occurredAt: Date(timeIntervalSince1970: 100),
            payload: payload,
            sensitivity: .userSensitive,
            provenance: Dictionary(uniqueKeysWithValues: payload.keys.map {
                ($0, FieldProvenance(source: "annotation.test", measurement: .userSupplied))
            })
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func makeContextEvent(idempotency: String) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "ai.context.test",
            version: "1",
            supportedKinds: [.aiTurn],
            allowedPayloadKeys: ["context_utilization"],
            sensitivityCeiling: .privateMetadata
        )
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256(idempotency),
            kind: .aiTurn,
            occurredAt: Date(timeIntervalSince1970: 1),
            payload: ["context_utilization": .number(0.90)],
            sensitivity: .privateMetadata,
            provenance: [
                "context_utilization": FieldProvenance(source: "ai.context.test", measurement: .measured)
            ]
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func makeClearCorrection(for eventID: UUID) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "annotation.test",
            version: "1",
            supportedKinds: [.associationCorrected],
            allowedPayloadKeys: ["event_id", "correction", "work_unit_id"],
            sensitivityCeiling: .userSensitive
        )
        let payload: [String: JSONValue] = [
            "event_id": .string(eventID.uuidString),
            "correction": .string("clear"),
            "work_unit_id": .null
        ]
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("clear-\(eventID.uuidString)"),
            kind: .associationCorrected,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            parentEventIDs: [eventID],
            payload: payload,
            sensitivity: .userSensitive,
            provenance: Dictionary(uniqueKeysWithValues: payload.keys.map {
                ($0, FieldProvenance(source: "annotation.test", measurement: .userSupplied))
            })
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func makeSnoozeControl(for recommendationID: String, until: Date) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "annotation.test",
            version: "1",
            supportedKinds: [.recommendationDismissed],
            allowedPayloadKeys: ["recommendation_id", "disposition", "reason_code", "snooze_until"],
            sensitivityCeiling: .userSensitive
        )
        let payload: [String: JSONValue] = [
            "recommendation_id": .string(recommendationID),
            "disposition": .string("snoozed"),
            "reason_code": .string("review_later"),
            "snooze_until": .string(ISO8601DateFormatter().string(from: until))
        ]
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("snooze-\(recommendationID)"),
            kind: .recommendationDismissed,
            occurredAt: Date(timeIntervalSince1970: 100),
            payload: payload,
            sensitivity: .userSensitive,
            provenance: Dictionary(uniqueKeysWithValues: payload.keys.map {
                ($0, FieldProvenance(source: "annotation.test", measurement: .userSupplied))
            })
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }
}
