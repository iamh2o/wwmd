import XCTest
import SQLite3
@testable import WWMDCore
@testable import WWMDStorage

final class TelemetryStoreTests: XCTestCase {
    func testDatabaseLeaseRejectsAnotherSupportedRuntimeForTheSameDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-lease-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path

        let first = try DatabaseLease(databasePath: path)
        XCTAssertThrowsError(try DatabaseLease(databasePath: path)) { error in
            XCTAssertEqual(error as? DatabaseLeaseError, .databaseAlreadyInUse)
        }
        withExtendedLifetime(first) {}
    }

    func testDatabaseLeaseRejectsDirectoryPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-lease-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try DatabaseLease(databasePath: directory.path)) { error in
            XCTAssertEqual(error as? DatabaseLeaseError, .databasePathIsDirectory)
        }
    }

    func testStorePersistsDeduplicatesAndCheckpointsAtomically() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let event = try makeEvent()
        let checkpoint = AdapterCheckpoint(
            adapterID: "test.adapter",
            configurationID: "default",
            cursor: "cursor-1",
            sourceContractVersion: "1"
        )

        let first = try await store.persist(events: [event], checkpoint: checkpoint)
        let second = try await store.persist(events: [event], checkpoint: checkpoint)
        let events = try await store.events()
        let savedCheckpoint = try await store.checkpoint(adapterID: "test.adapter", configurationID: "default")
        let projection = ProjectionCheckpoint(
            projectionName: "v0.summary",
            projectionVersion: 1,
            lastSequence: first.insertedEvents[0].sequence ?? 0,
            rebuildGeneration: 1
        )
        try await store.setProjectionCheckpoint(projection)
        let savedProjection = try await store.projectionCheckpoint(name: "v0.summary", version: 1)
        let health = try await store.health()

        XCTAssertEqual(first.insertedEvents.count, 1)
        XCTAssertEqual(second.insertedEvents.count, 0)
        XCTAssertEqual(second.duplicateSequences.count, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(savedCheckpoint?.cursor, "cursor-1")
        XCTAssertEqual(savedProjection?.lastSequence, first.insertedEvents[0].sequence)
        XCTAssertEqual(health.schemaVersion, 4)
        XCTAssertEqual(health.eventCount, 1)
        XCTAssertTrue(health.quickCheckPassed)
    }

    func testCheckpointMustMatchBatchAdapter() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let event = try makeEvent()
        let wrongCheckpoint = AdapterCheckpoint(
            adapterID: "other.adapter",
            configurationID: "default",
            cursor: "cursor",
            sourceContractVersion: "1"
        )

        do {
            _ = try await store.persist(events: [event], checkpoint: wrongCheckpoint)
            XCTFail("Expected mismatch to throw")
        } catch let error as TelemetryStoreError {
            XCTAssertEqual(error, .invalidCheckpoint)
        }
    }

    func testV1DatabaseMigratesAtomicallyToLatestSchema() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("ledger.sqlite").path

        try createV1Fixture(at: path)
        let store = try TelemetryStore(path: path)
        let health = try await store.health()
        let projection = ProjectionCheckpoint(
            projectionName: "v0.summary",
            projectionVersion: 1,
            lastSequence: 0,
            rebuildGeneration: 1
        )
        try await store.setProjectionCheckpoint(projection)
        let savedProjection = try await store.projectionCheckpoint(name: "v0.summary", version: 1)

        XCTAssertEqual(health.schemaVersion, 4)
        XCTAssertEqual(health.eventCount, 0)
        XCTAssertEqual(savedProjection?.projectionName, projection.projectionName)
        XCTAssertEqual(savedProjection?.projectionVersion, projection.projectionVersion)
        XCTAssertEqual(savedProjection?.lastSequence, projection.lastSequence)
        XCTAssertEqual(savedProjection?.rebuildGeneration, projection.rebuildGeneration)
        XCTAssertEqual(
            savedProjection?.updatedAt.timeIntervalSince(projection.updatedAt) ?? .infinity,
            0,
            accuracy: 0.001
        )
    }

    func testPauseAndAdapterOptInPersist() async throws {
        let store = try TelemetryStore(path: ":memory:")
        let initialState = try await store.collectionState()
        let initialAdapterState = try await store.adapterCollectionState(adapterID: "git.local", configurationID: "repo-a")
        XCTAssertFalse(initialState.globallyPaused)
        XCTAssertNil(initialAdapterState)

        let date = Date(timeIntervalSince1970: 1_000)
        try await store.setGlobalPause(true, at: date)
        try await store.setAdapterEnabled(
            adapterID: "git.local",
            configurationID: "repo-a",
            enabled: true,
            at: date
        )

        let savedState = try await store.collectionState()
        let savedAdapterState = try await store.adapterCollectionState(adapterID: "git.local", configurationID: "repo-a")
        XCTAssertTrue(savedState.globallyPaused)
        XCTAssertEqual(savedAdapterState?.enabled, true)
    }

    func testSafeExportBackupAndPurge() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("ledger.sqlite").path
        let store = try TelemetryStore(path: databasePath)
        let privateEvent = try makeEvent()
        let sensitiveEvent = try makeSensitiveAnnotationEvent()
        _ = try await store.persist(events: [privateEvent, sensitiveEvent])

        let exportPath = directory.appendingPathComponent("safe.ndjson").path
        let export = try await store.export(to: exportPath, format: .ndjson, profile: .safe)
        let exportText = try String(contentsOfFile: exportPath, encoding: .utf8)
        XCTAssertEqual(export.eventCount, 1)
        XCTAssertTrue(exportText.contains("test.adapter"))
        XCTAssertFalse(exportText.contains("work_unit.outcome_declared"))

        let backupPath = directory.appendingPathComponent("backup.sqlite").path
        let backup = try await store.backup(to: backupPath)
        XCTAssertFalse(backup.checksum.isEmpty)
        let restored = try TelemetryStore(path: backupPath)
        let restoredHealth = try await restored.health()
        XCTAssertEqual(restoredHealth.eventCount, 2)

        let purge = try await store.purgeEvents(
            occurredBefore: Date(timeIntervalSince1970: 2),
            includeUserSensitiveEvents: false
        )
        XCTAssertEqual(purge.deletedEventCount, 1)
        let remainingEvents = try await store.events()
        XCTAssertEqual(remainingEvents.count, 1)
    }

    func testManagedOutputsAndExplicitDeletionArePreviewedThenRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-managed-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TelemetryStore(path: directory.appendingPathComponent("ledger.sqlite").path)
        _ = try await store.persist(events: [try makeEvent(), try makeSensitiveAnnotationEvent()])
        try await store.setProjectionCheckpoint(
            ProjectionCheckpoint(
                projectionName: "v0.summary",
                projectionVersion: 1,
                lastSequence: 2,
                rebuildGeneration: 1
            )
        )

        let exportPath = directory.appendingPathComponent("safe.ndjson").path
        let backupPath = directory.appendingPathComponent("backup.sqlite").path
        let export = try await store.export(to: exportPath, format: .ndjson, profile: .safe)
        let backup = try await store.backup(to: backupPath)
        let outputs = try await store.managedOutputs()
        XCTAssertEqual(Set(outputs.map(\.id)), Set([export.exportID, backup.backupID]))

        let selection = DeletionSelection(
            eventScope: EventDeletionScope(
                from: Date(timeIntervalSince1970: 0),
                to: Date(timeIntervalSince1970: 2),
                includeUserSensitiveEvents: true
            ),
            managedOutputIDs: [export.exportID, backup.backupID]
        )
        let preview = try await store.previewDeletion(selection: selection)
        XCTAssertEqual(preview.matchingEventCount, 2)
        XCTAssertEqual(preview.managedOutputs.count, 2)

        let receipt = try await store.performDeletion(
            selection: selection,
            expectedLatestSequence: preview.latestSequence,
            scopeDigest: StableHash.sha256("test-managed-delete"),
            at: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(receipt.deletedEventCount, 2)
        XCTAssertEqual(receipt.deletedManagedOutputCount, 2)
        XCTAssertEqual(receipt.missingManagedOutputCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupPath))
        let remainingEvents = try await store.events()
        let remainingOutputs = try await store.managedOutputs()
        let remainingProjection = try await store.projectionCheckpoint(name: "v0.summary", version: 1)
        XCTAssertTrue(remainingEvents.isEmpty)
        XCTAssertTrue(remainingOutputs.isEmpty)
        XCTAssertNil(remainingProjection)
    }

    func testManagedDeletionRejectsAStaleLedgerPreview() async throws {
        let store = try TelemetryStore(path: ":memory:")
        _ = try await store.persist(events: [try makeEvent()])
        let selection = DeletionSelection(
            eventScope: EventDeletionScope(
                from: Date(timeIntervalSince1970: 0),
                to: Date(timeIntervalSince1970: 3),
                includeUserSensitiveEvents: true
            ),
            managedOutputIDs: []
        )
        let preview = try await store.previewDeletion(selection: selection)
        _ = try await store.persist(events: [try makeEvent(sourceID: "row-2", occurredAt: 2)])

        do {
            _ = try await store.performDeletion(
                selection: selection,
                expectedLatestSequence: preview.latestSequence,
                scopeDigest: StableHash.sha256("test-stale-delete")
            )
            XCTFail("Expected stale preview rejection")
        } catch let error as TelemetryStoreError {
            XCTAssertEqual(error, .deletionPreviewStale)
        }
    }

    func testManagedDeletionClearsReceiptWhenTheUserAlreadyRemovedTheOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-missing-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TelemetryStore(path: directory.appendingPathComponent("ledger.sqlite").path)
        let exportPath = directory.appendingPathComponent("safe.ndjson").path
        let export = try await store.export(to: exportPath, format: .ndjson, profile: .safe)
        try FileManager.default.removeItem(atPath: exportPath)

        let selection = DeletionSelection(eventScope: nil, managedOutputIDs: [export.exportID])
        let preview = try await store.previewDeletion(selection: selection)
        let receipt = try await store.performDeletion(
            selection: selection,
            expectedLatestSequence: preview.latestSequence,
            scopeDigest: StableHash.sha256("test-missing-output")
        )

        XCTAssertEqual(receipt.deletedEventCount, 0)
        XCTAssertEqual(receipt.deletedManagedOutputCount, 0)
        XCTAssertEqual(receipt.missingManagedOutputCount, 1)
        let outputs = try await store.managedOutputs()
        XCTAssertTrue(outputs.isEmpty)
    }

    func testManagedDeletionRefusesAChangedOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-changed-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TelemetryStore(path: directory.appendingPathComponent("ledger.sqlite").path)
        let exportPath = directory.appendingPathComponent("safe.ndjson").path
        let export = try await store.export(to: exportPath, format: .ndjson, profile: .safe)
        try Data("changed outside WWMD".utf8).write(to: URL(fileURLWithPath: exportPath))

        let selection = DeletionSelection(eventScope: nil, managedOutputIDs: [export.exportID])
        let preview = try await store.previewDeletion(selection: selection)

        do {
            _ = try await store.performDeletion(
                selection: selection,
                expectedLatestSequence: preview.latestSequence,
                scopeDigest: StableHash.sha256("test-changed-output")
            )
            XCTFail("Expected changed output rejection")
        } catch let error as TelemetryStoreError {
            XCTAssertEqual(error, .managedOutputChanged)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportPath))
        let outputs = try await store.managedOutputs()
        XCTAssertEqual(outputs.map(\.id), [export.exportID])
    }

    private func makeEvent(sourceID: String = "row-1", occurredAt: TimeInterval = 1) throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "test.adapter",
            version: "1",
            supportedKinds: [.aiTurn],
            allowedPayloadKeys: ["input_tokens"],
            sensitivityCeiling: .privateMetadata
        )
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceNativeID: sourceID,
            sourceIdempotencyKey: StableHash.sha256("storage-\(sourceID)"),
            kind: .aiTurn,
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            payload: ["input_tokens": .number(10)],
            sensitivity: .privateMetadata,
            provenance: ["input_tokens": FieldProvenance(source: "test.adapter", measurement: .measured)]
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func makeSensitiveAnnotationEvent() throws -> TelemetryEvent {
        let descriptor = AdapterDescriptor(
            id: "annotation.test",
            version: "1",
            supportedKinds: [.workUnitOutcomeDeclared],
            allowedPayloadKeys: ["work_unit_id", "kind", "outcome"],
            sensitivityCeiling: .userSensitive
        )
        let payload: [String: JSONValue] = [
            "work_unit_id": .string("wu-a"),
            "kind": .string("feature"),
            "outcome": .string("completed")
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "annotation.test", measurement: .userSupplied))
        })
        let offer = SourceEventOffer(
            descriptor: descriptor,
            sourceIdempotencyKey: StableHash.sha256("sensitive-annotation"),
            kind: .workUnitOutcomeDeclared,
            occurredAt: Date(timeIntervalSince1970: 1),
            payload: payload,
            sensitivity: .userSensitive,
            provenance: provenance
        )
        return try TelemetryEventFactory.make(offer: offer, identity: LocalIdentity())
    }

    private func createV1Fixture(at path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw NSError(domain: "WWMDStorageTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE schema_migrations (
            version INTEGER PRIMARY KEY,
            checksum TEXT NOT NULL,
            applied_at REAL NOT NULL
        );
        INSERT INTO schema_migrations (version, checksum, applied_at)
            VALUES (1, 'fixture-v1', 0);
        CREATE TABLE telemetry_events (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL UNIQUE,
            schema_name TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            adapter_id TEXT NOT NULL,
            adapter_version TEXT NOT NULL,
            source_native_id TEXT,
            source_idempotency_key TEXT NOT NULL UNIQUE,
            event_kind TEXT NOT NULL,
            occurred_at REAL,
            observed_at REAL NOT NULL,
            persisted_at REAL NOT NULL,
            monotonic_nanos INTEGER,
            actor_id TEXT NOT NULL,
            device_id TEXT NOT NULL,
            project_id TEXT,
            repository_id TEXT,
            worktree_id TEXT,
            branch TEXT,
            provider TEXT,
            client TEXT,
            model TEXT,
            thread_id TEXT,
            turn_id TEXT,
            work_unit_id TEXT,
            parent_event_ids_json BLOB NOT NULL,
            payload_json BLOB NOT NULL,
            sensitivity TEXT NOT NULL,
            redaction_state TEXT NOT NULL,
            provenance_json BLOB NOT NULL,
            confidence REAL
        );
        CREATE TABLE adapter_state (
            adapter_id TEXT NOT NULL,
            configuration_id TEXT NOT NULL,
            health TEXT NOT NULL,
            cursor TEXT,
            source_contract_version TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY(adapter_id, configuration_id)
        );
        CREATE TABLE projection_checkpoints (
            projection_name TEXT NOT NULL,
            projection_version INTEGER NOT NULL,
            last_sequence INTEGER NOT NULL,
            rebuild_generation INTEGER NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(projection_name, projection_version)
        );
        CREATE TABLE quarantine_receipts (
            adapter_id TEXT NOT NULL,
            adapter_version TEXT NOT NULL,
            reason_code TEXT NOT NULL,
            cursor_digest TEXT NOT NULL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            count INTEGER NOT NULL,
            PRIMARY KEY(adapter_id, adapter_version, reason_code, cursor_digest)
        );
        """
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if errorMessage != nil {
            sqlite3_free(errorMessage)
        }
        guard result == SQLITE_OK else {
            throw NSError(domain: "WWMDStorageTests", code: Int(result))
        }
    }
}
