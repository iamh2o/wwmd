import XCTest
@testable import WWMDAdapters
@testable import WWMDCore
@testable import WWMDIPC
@testable import WWMDAgentRuntime
@testable import WWMDStorage

final class WWMDAgentRuntimeTests: XCTestCase {
    func testRuntimeRequiresExplicitOptInAndHonorsPause() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
        let offer = makeOffer()

        do {
            _ = try await runtime.ingest(offer: offer, configurationID: "repo-a")
            XCTFail("Expected opt-in requirement")
        } catch let error as WWMDAgentError {
            XCTAssertEqual(error, .adapterNotOptedIn)
        }

        try await runtime.setAdapterEnabled(adapterID: "git.local", configurationID: "repo-a", enabled: true)
        let receipt = try await runtime.ingest(offer: offer, configurationID: "repo-a")
        XCTAssertEqual(receipt.insertedEvents.count, 1)

        try await runtime.setGlobalPause(true)
        do {
            _ = try await runtime.ingest(offer: offer, configurationID: "repo-a")
            XCTFail("Expected global pause")
        } catch let error as WWMDAgentError {
            XCTAssertEqual(error, .collectionPaused)
        }
    }

    func testXPCServiceReturnsHealthForValidatedRequest() throws {
        let store = try TelemetryStore(path: ":memory:")
        let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
        let service = WWMDAgentXPCService(runtime: runtime)
        let request = try XPCCodec.encode(XPCRequestEnvelope(kind: .health, capability: .query))
        let completed = expectation(description: "health reply")

        service.getHealth(request) { data, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            if let data {
                let response = try? XPCCodec.decode(XPCHealthResponse.self, from: data)
                XCTAssertEqual(response?.schemaVersion, 3)
                XCTAssertEqual(response?.eventCount, 0)
                XCTAssertFalse(response?.globallyPaused ?? true)
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
    }

    func testXPCServiceProvidesSafeScopedQueriesAndPauseControl() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
        try await runtime.setAdapterEnabled(adapterID: "git.local", configurationID: "repo-a", enabled: true)
        _ = try await runtime.ingest(offer: makeOffer(), configurationID: "repo-a")
        try await runtime.setAdapterEnabled(
            adapterID: V0AdapterDescriptors.annotation.id,
            configurationID: "annotation-a",
            enabled: true
        )
        _ = try await runtime.recordWorkUnitOutcome(
            WorkUnitOutcomeInput(
                idempotencyKey: StableHash.sha256("sensitive-outcome"),
                occurredAt: Date(timeIntervalSince1970: 2),
                workUnitID: "wu-a",
                kind: .feature,
                outcome: .completed,
                repositoryID: "repo-a"
            ),
            configurationID: "annotation-a"
        )
        let service = WWMDAgentXPCService(runtime: runtime)
        let scope = XPCScopedQuery(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100)
        )

        let summaryCompleted = expectation(description: "summary reply")
        let summaryRequest = try XPCCodec.encode(
            XPCSummaryRequest(
                envelope: XPCRequestEnvelope(kind: .querySummary, capability: .query),
                query: SummaryQuery(from: scope.from, to: scope.to, metricNames: [])
            )
        )
        service.querySummary(summaryRequest) { data, error in
            XCTAssertNil(error)
            let response = data.flatMap { try? XPCCodec.decode(XPCSummaryResponse.self, from: $0) }
            XCTAssertEqual(response?.eventCount, 1)
            XCTAssertEqual(response?.metrics.first(where: { $0.name == "ai.turn.count" })?.value, 0)
            summaryCompleted.fulfill()
        }
        await fulfillment(of: [summaryCompleted], timeout: 2)

        let evidenceCompleted = expectation(description: "evidence reply")
        let evidenceRequest = try XPCCodec.encode(
            XPCEvidenceRequest(
                envelope: XPCRequestEnvelope(kind: .queryEvidence, capability: .query),
                query: XPCEvidenceQuery(scope: scope, limit: 10)
            )
        )
        service.queryEvidence(evidenceRequest) { data, error in
            XCTAssertNil(error)
            let response = data.flatMap { try? XPCCodec.decode(XPCEvidenceResponse.self, from: $0) }
            XCTAssertEqual(response?.items.count, 1)
            XCTAssertEqual(response?.items.first?.repositoryID, "repo-a")
            XCTAssertEqual(response?.items.first?.kind, TelemetryEventKind.gitCommit.rawValue)
            evidenceCompleted.fulfill()
        }
        await fulfillment(of: [evidenceCompleted], timeout: 2)

        let controlCompleted = expectation(description: "control reply")
        let controlRequest = try XPCCodec.encode(
            XPCCollectionStateRequest(
                envelope: XPCRequestEnvelope(kind: .setCollectionState, capability: .control),
                globallyPaused: true
            )
        )
        service.setCollectionState(controlRequest) { data, error in
            XCTAssertNil(error)
            let response = data.flatMap { try? XPCCodec.decode(XPCCollectionStateResponse.self, from: $0) }
            XCTAssertTrue(response?.globallyPaused ?? false)
            controlCompleted.fulfill()
        }
        await fulfillment(of: [controlCompleted], timeout: 2)
    }

    func testGitReaderIsNotInvokedBeforeItsExactConfigurationIsOptedIn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-agent-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TelemetryStore(path: ":memory:")
        let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
        let runner = CountingGitRunner(root: directory)
        let reader = GitMetadataReader(runner: runner)

        do {
            _ = try await runtime.ingestGitLatestCommit(
                at: directory,
                configurationID: "selected-repo",
                reader: reader
            )
            XCTFail("Expected explicit opt-in requirement")
        } catch let error as WWMDAgentError {
            XCTAssertEqual(error, .adapterNotOptedIn)
        }
        XCTAssertEqual(runner.callCount, 0)

        try await runtime.setAdapterEnabled(
            adapterID: V0AdapterDescriptors.git.id,
            configurationID: "selected-repo",
            enabled: true
        )
        let receipt = try await runtime.ingestGitLatestCommit(
            at: directory,
            configurationID: "selected-repo",
            reader: reader
        )
        XCTAssertEqual(receipt.insertedEvents.count, 1)
        XCTAssertGreaterThan(runner.callCount, 0)
    }

    func testBuildCommandIsNotExecutedBeforeItsExactConfigurationIsOptedIn() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let runtime = WWMDAgentRuntime(store: store, identity: LocalIdentity())
        let process = CountingValidationRunner()
        let request = ExplicitValidationRequest(
            idempotencyKey: StableHash.sha256("runtime-validation"),
            category: .test,
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: ["--ephemeral-only"],
            repositoryID: "repo-a"
        )
        let runner = ExplicitValidationRunner(runner: process)

        do {
            _ = try await runtime.runExplicitValidation(
                request,
                configurationID: "explicit-test",
                runner: runner
            )
            XCTFail("Expected explicit opt-in requirement")
        } catch let error as WWMDAgentError {
            XCTAssertEqual(error, .adapterNotOptedIn)
        }
        XCTAssertEqual(process.callCount, 0)

        try await runtime.setAdapterEnabled(
            adapterID: V0AdapterDescriptors.build.id,
            configurationID: "explicit-test",
            enabled: true
        )
        let receipt = try await runtime.runExplicitValidation(
            request,
            configurationID: "explicit-test",
            runner: runner
        )
        XCTAssertEqual(receipt.insertedEvents.count, 1)
        XCTAssertEqual(process.callCount, 1)
    }

    private func makeOffer() -> SourceEventOffer {
        let descriptor = AdapterDescriptor(
            id: "git.local",
            version: "1",
            supportedKinds: [.gitCommit],
            allowedPayloadKeys: ["commit_oid"],
            sensitivityCeiling: .privateMetadata
        )
        return SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("agent-ingest"),
            kind: .gitCommit,
            occurredAt: Date(timeIntervalSince1970: 1),
            repositoryID: "repo-a",
            payload: ["commit_oid": .string("0123456789abcdef")],
            sensitivity: .privateMetadata,
            provenance: ["commit_oid": FieldProvenance(source: "git.local", measurement: .measured)]
        )
    }
}

private final class CountingGitRunner: GitCommandRunning, @unchecked Sendable {
    let root: URL
    private(set) var callCount = 0

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
    }

    func run(arguments: [String], repositoryRoot: URL) throws -> String {
        callCount += 1
        switch arguments {
        case ["rev-parse", "--show-toplevel"]:
            return "\(root.path)\n"
        case ["rev-parse", "HEAD"]:
            return "0123456789abcdef\n"
        case ["rev-parse", "--abbrev-ref", "HEAD"]:
            return "main\n"
        case ["show", "-s", "--format=%ct", "HEAD"]:
            return "1000\n"
        case ["show", "-s", "--format=%P", "HEAD"]:
            return "fedcba9876543210\n"
        case ["diff", "--shortstat", "HEAD^", "HEAD"]:
            return " 3 files changed, 10 insertions(+), 2 deletions(-)\n"
        default:
            throw GitMetadataReaderError.invalidOutput
        }
    }
}

private final class CountingValidationRunner: ValidationProcessRunning, @unchecked Sendable {
    private(set) var callCount = 0

    func run(executable: URL, arguments: [String]) throws -> Int32 {
        callCount += 1
        return 0
    }
}
