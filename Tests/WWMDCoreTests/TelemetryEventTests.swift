import XCTest
@testable import WWMDCore

final class TelemetryEventTests: XCTestCase {
    private let descriptor = AdapterDescriptor(
        id: "test.adapter",
        version: "1",
        supportedKinds: [.aiTurn],
        allowedPayloadKeys: ["input_tokens"],
        sensitivityCeiling: .privateMetadata
    )

    func testFactoryProducesValidatedEvent() throws {
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceNativeID: "row-1",
            sourceIdempotencyKey: StableHash.sha256("test-row-1"),
            kind: .aiTurn,
            occurredAt: Date(timeIntervalSince1970: 1),
            payload: ["input_tokens": .number(42)],
            sensitivity: .privateMetadata,
            provenance: ["input_tokens": FieldProvenance(source: "test.adapter", measurement: .measured)]
        )

        let event = try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())

        XCTAssertEqual(event.kind, .aiTurn)
        XCTAssertEqual(event.payload["input_tokens"], .number(42))
        XCTAssertEqual(event.redactionState, .passed)
        XCTAssertNil(event.sequence)
    }

    func testFactoryRejectsWindowTitle() {
        let unsafeDescriptor = AdapterDescriptor(
            id: "unsafe.adapter",
            version: "1",
            supportedKinds: [.activitySession],
            allowedPayloadKeys: ["window_title"],
            sensitivityCeiling: .privateMetadata
        )
        let offer = SourceEventOffer(
            descriptor: unsafeDescriptor,
            sourceIdempotencyKey: StableHash.sha256("unsafe"),
            kind: .activitySession,
            occurredAt: Date(),
            payload: ["window_title": .string("sensitive")],
            sensitivity: .privateMetadata,
            provenance: ["window_title": FieldProvenance(source: "unsafe.adapter", measurement: .measured)]
        )

        XCTAssertThrowsError(try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())) { error in
            XCTAssertEqual(error as? TelemetryValidationError, .prohibitedPayloadField("window_title"))
        }
    }

    func testFactoryRejectsMissingPayloadProvenance() {
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("missing-provenance"),
            kind: .aiTurn,
            occurredAt: Date(),
            payload: ["input_tokens": .number(42)],
            sensitivity: .privateMetadata,
            provenance: [:]
        )

        XCTAssertThrowsError(try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())) { error in
            XCTAssertEqual(error as? TelemetryValidationError, .missingPayloadProvenance("input_tokens"))
        }
    }

    func testFactoryRejectsFreeTextInOpaqueWorkUnitIdentifier() {
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("free-text-work-unit"),
            kind: .aiTurn,
            occurredAt: Date(),
            workUnitID: "fix the user's production incident",
            payload: ["input_tokens": .number(42)],
            sensitivity: .privateMetadata,
            provenance: ["input_tokens": FieldProvenance(source: "test.adapter", measurement: .measured)]
        )

        XCTAssertThrowsError(try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())) { error in
            XCTAssertEqual(error as? TelemetryValidationError, .invalidMetadataValue("work_unit_id"))
        }
    }

    func testFactoryRejectsSecretShapedRepositoryMetadata() {
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("secret-repository-id"),
            kind: .aiTurn,
            occurredAt: Date(),
            repositoryID: "ghp_exampletoken",
            payload: ["input_tokens": .number(42)],
            sensitivity: .privateMetadata,
            provenance: ["input_tokens": FieldProvenance(source: "test.adapter", measurement: .measured)]
        )

        XCTAssertThrowsError(try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())) { error in
            XCTAssertEqual(error as? TelemetryValidationError, .suspectedSecret)
        }
    }
}
