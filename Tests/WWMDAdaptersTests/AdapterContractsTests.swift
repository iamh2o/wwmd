import XCTest
@testable import WWMDAdapters
@testable import WWMDCore

final class AdapterContractsTests: XCTestCase {
    func testCodexImportIsBlockedWithoutContract() {
        XCTAssertThrowsError(try CodexCSVImportGate.validate(headers: ["id"], contract: nil)) { error in
            XCTAssertEqual(error as? AdapterContractError, .missingCodexCSVContract)
        }
    }

    func testCodexImportRequiresExactHeaderOrder() throws {
        let contract = CodexCSVContract(
            version: "1",
            exactHeaders: ["id", "occurred_at"],
            sourceIDRule: "id",
            timestampSemantics: "RFC3339 UTC"
        )
        try CodexCSVImportGate.validate(headers: ["id", "occurred_at"], contract: contract)
        XCTAssertThrowsError(try CodexCSVImportGate.validate(headers: ["occurred_at", "id"], contract: contract))
    }

    func testBuildAdapterDoesNotAcceptCommandContent() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let offer = BuildTestAdapter.resultOffer(
            BuildTestInput(
                idempotencyKey: StableHash.sha256("build-1"),
                category: .test,
                startedAt: start,
                endedAt: start.addingTimeInterval(2),
                status: .passed,
                repositoryID: "repo-a"
            )
        )
        let event = try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())

        XCTAssertEqual(event.kind, .validationResult)
        XCTAssertNil(event.payload["command"])
        XCTAssertEqual(event.payload["aggregate_status"], .string("passed"))
    }

    func testRecommendationControlRequiresAConsistentSnoozeTime() {
        XCTAssertThrowsError(
            try RecommendationControlInput(
                idempotencyKey: StableHash.sha256("bad-snooze"),
                occurredAt: Date(timeIntervalSince1970: 10),
                recommendationID: "data.correlation_gap:v1:global",
                disposition: .snoozed,
                reason: .reviewLater,
                snoozeUntil: Date(timeIntervalSince1970: 9)
            )
        ) { error in
            XCTAssertEqual(error as? AdapterContractError, .invalidRecommendationControl)
        }
    }
}
