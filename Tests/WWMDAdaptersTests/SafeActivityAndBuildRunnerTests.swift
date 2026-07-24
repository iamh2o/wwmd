import XCTest
@testable import WWMDAdapters
@testable import WWMDCore

final class SafeActivityAndBuildRunnerTests: XCTestCase {
    func testSafeActivityOfferContainsNoTitleOrIdleField() throws {
        let offer = SafeActivityAdapter.sessionOffer(
            SafeActivitySessionInput(
                idempotencyKey: StableHash.sha256("activity-1"),
                occurredAt: Date(timeIntervalSince1970: 1),
                state: .started,
                applicationBundleIdentifier: "com.example.editor",
                repositoryID: "repo-a"
            )
        )
        let event = try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())

        XCTAssertEqual(event.payload["application_bundle_id"], .string("com.example.editor"))
        XCTAssertNil(event.payload["window_title"])
        XCTAssertNil(event.payload["idle"])
    }

    func testExplicitRunnerDoesNotPersistArgumentsOrOutput() throws {
        let times = [Date(timeIntervalSince1970: 10), Date(timeIntervalSince1970: 14)]
        let clock = FixtureClock(values: times)
        let runner = ExplicitValidationRunner(runner: FixtureProcessRunner(status: 0), now: clock.next)
        let offer = try runner.execute(
            ExplicitValidationRequest(
                idempotencyKey: StableHash.sha256("validation-1"),
                category: .test,
                executable: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: ["--contains-sensitive-but-ephemeral"],
                repositoryID: "repo-a"
            )
        )
        let event = try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())

        XCTAssertEqual(event.payload["aggregate_status"], .string("passed"))
        XCTAssertEqual(event.payload["duration_ms"], .number(4_000))
        XCTAssertNil(event.payload["arguments"])
        XCTAssertNil(event.payload["output"])
    }
}

private struct FixtureProcessRunner: ValidationProcessRunning {
    let status: Int32

    func run(executable: URL, arguments: [String]) throws -> Int32 {
        status
    }
}

private final class FixtureClock: @unchecked Sendable {
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    func next() -> Date {
        values.removeFirst()
    }
}
