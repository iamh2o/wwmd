import CryptoKit
import Foundation
import SQLite3
import WWMDCore

public enum TelemetryStoreError: Error, Equatable, Sendable, LocalizedError {
    case openFailed(code: Int32)
    case sqliteFailed(code: Int32)
    case migrationFailed(version: Int)
    case decodingFailed
    case integrityCheckFailed
    case invalidCheckpoint
    case destinationAlreadyExists
    case fileOperationFailed
    case backupFailed(code: Int32)
    case invalidDeletionScope
    case duplicateManagedOutputID
    case managedOutputNotFound
    case deletionPreviewStale
    case deletionSelectionTooLarge
    case managedOutputChanged

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            "Unable to open the WWMD database (SQLite code \(code))."
        case .sqliteFailed(let code):
            "WWMD database operation failed (SQLite code \(code))."
        case .migrationFailed(let version):
            "WWMD database migration \(version) failed."
        case .decodingFailed:
            "WWMD database contained an unsupported event encoding."
        case .integrityCheckFailed:
            "WWMD database integrity check failed."
        case .invalidCheckpoint:
            "The adapter checkpoint did not match the persisted event batch."
        case .destinationAlreadyExists:
            "WWMD will not overwrite an existing export or backup destination."
        case .fileOperationFailed:
            "WWMD could not complete the requested local file operation."
        case .backupFailed(let code):
            "WWMD SQLite backup failed (SQLite code \(code))."
        case .invalidDeletionScope:
            "WWMD deletion requires an explicit bounded event scope or exact managed output IDs."
        case .duplicateManagedOutputID:
            "WWMD deletion cannot include the same managed output more than once."
        case .managedOutputNotFound:
            "One or more selected managed outputs no longer have a WWMD receipt."
        case .deletionPreviewStale:
            "WWMD data changed after the deletion preview. Request a new preview before confirming."
        case .deletionSelectionTooLarge:
            "WWMD deletion selects too many managed outputs in one request."
        case .managedOutputChanged:
            "A managed output no longer matches its WWMD checksum and will not be deleted automatically."
        }
    }
}

public struct PersistenceReceipt: Sendable, Equatable {
    public let insertedEvents: [TelemetryEvent]
    public let duplicateSequences: [Int64]
    public let checkpoint: AdapterCheckpoint?

    public init(insertedEvents: [TelemetryEvent], duplicateSequences: [Int64], checkpoint: AdapterCheckpoint?) {
        self.insertedEvents = insertedEvents
        self.duplicateSequences = duplicateSequences
        self.checkpoint = checkpoint
    }
}

public struct StoreHealth: Sendable, Equatable {
    public let schemaVersion: Int
    public let eventCount: Int
    public let quickCheckPassed: Bool

    public init(schemaVersion: Int, eventCount: Int, quickCheckPassed: Bool) {
        self.schemaVersion = schemaVersion
        self.eventCount = eventCount
        self.quickCheckPassed = quickCheckPassed
    }
}

/// A deliberately bounded, metadata-only event query. Callers must provide an
/// explicit time range; this store never discovers a source or query scope.
public struct TelemetryEventQuery: Sendable, Equatable {
    public let from: Date
    public let to: Date
    public let repositoryID: String?
    public let workUnitID: String?
    public let limit: Int

    public init(
        from: Date,
        to: Date,
        repositoryID: String? = nil,
        workUnitID: String? = nil,
        limit: Int
    ) {
        self.from = from
        self.to = to
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
        self.limit = limit
    }
}

public struct CollectionState: Sendable, Equatable {
    public let globallyPaused: Bool
    public let updatedAt: Date

    public init(globallyPaused: Bool, updatedAt: Date) {
        self.globallyPaused = globallyPaused
        self.updatedAt = updatedAt
    }
}

public struct AdapterCollectionState: Sendable, Equatable {
    public let adapterID: String
    public let configurationID: String
    public let enabled: Bool
    public let updatedAt: Date

    public init(adapterID: String, configurationID: String, enabled: Bool, updatedAt: Date) {
        self.adapterID = adapterID
        self.configurationID = configurationID
        self.enabled = enabled
        self.updatedAt = updatedAt
    }
}

public struct PurgeReceipt: Sendable, Equatable {
    public let deletedEventCount: Int
    public let occurredBefore: Date
    public let includedUserSensitiveEvents: Bool

    public init(deletedEventCount: Int, occurredBefore: Date, includedUserSensitiveEvents: Bool) {
        self.deletedEventCount = deletedEventCount
        self.occurredBefore = occurredBefore
        self.includedUserSensitiveEvents = includedUserSensitiveEvents
    }
}

public enum ExportFormat: String, Sendable {
    case ndjson
    case summaryCSV = "summary_csv"
}

public enum ExportProfile: String, Sendable {
    case safe
    case includeUserSensitive = "include_user_sensitive"
}

public struct ExportReceipt: Sendable, Equatable {
    public let exportID: UUID
    public let format: ExportFormat
    public let profile: ExportProfile
    public let eventCount: Int
    public let checksum: String

    public init(exportID: UUID, format: ExportFormat, profile: ExportProfile, eventCount: Int, checksum: String) {
        self.exportID = exportID
        self.format = format
        self.profile = profile
        self.eventCount = eventCount
        self.checksum = checksum
    }
}

public struct BackupReceipt: Sendable, Equatable {
    public let backupID: UUID
    public let checksum: String

    public init(backupID: UUID, checksum: String) {
        self.backupID = backupID
        self.checksum = checksum
    }
}

public enum ManagedOutputKind: String, Sendable, Equatable {
    case export
    case backup
}

/// A safe view of a WWMD-generated output. The on-disk path remains storage
/// private and is never returned through XPC or exported as telemetry.
public struct ManagedOutput: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: ManagedOutputKind
    public let filename: String
    public let byteCount: Int64
    public let checksum: String
    public let createdAt: Date

    public init(
        id: UUID,
        kind: ManagedOutputKind,
        filename: String,
        byteCount: Int64,
        checksum: String,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.byteCount = byteCount
        self.checksum = checksum
        self.createdAt = createdAt
    }
}

/// Event deletion is intentionally bounded and explicit. A nil repository or
/// work-unit field broadens only that one already time-bounded dimension.
public struct EventDeletionScope: Sendable, Equatable {
    public let from: Date
    public let to: Date
    public let repositoryID: String?
    public let workUnitID: String?
    public let includeUserSensitiveEvents: Bool

    public init(
        from: Date,
        to: Date,
        repositoryID: String? = nil,
        workUnitID: String? = nil,
        includeUserSensitiveEvents: Bool
    ) {
        self.from = from
        self.to = to
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
        self.includeUserSensitiveEvents = includeUserSensitiveEvents
    }
}

public struct DeletionSelection: Sendable, Equatable {
    public let eventScope: EventDeletionScope?
    public let managedOutputIDs: [UUID]

    public init(eventScope: EventDeletionScope?, managedOutputIDs: [UUID]) {
        self.eventScope = eventScope
        self.managedOutputIDs = managedOutputIDs
    }
}

public struct DeletionPreview: Sendable, Equatable {
    public let latestSequence: Int64
    public let matchingEventCount: Int
    public let managedOutputs: [ManagedOutput]

    public init(latestSequence: Int64, matchingEventCount: Int, managedOutputs: [ManagedOutput]) {
        self.latestSequence = latestSequence
        self.matchingEventCount = matchingEventCount
        self.managedOutputs = managedOutputs
    }
}

public struct DeletionReceipt: Sendable, Equatable {
    public let receiptID: UUID
    public let deletedEventCount: Int
    public let deletedManagedOutputCount: Int
    public let missingManagedOutputCount: Int
    public let createdAt: Date

    public init(
        receiptID: UUID,
        deletedEventCount: Int,
        deletedManagedOutputCount: Int,
        missingManagedOutputCount: Int,
        createdAt: Date
    ) {
        self.receiptID = receiptID
        self.deletedEventCount = deletedEventCount
        self.deletedManagedOutputCount = deletedManagedOutputCount
        self.missingManagedOutputCount = missingManagedOutputCount
        self.createdAt = createdAt
    }
}

public actor TelemetryStore {
    public static let latestSchemaVersion = 4
    public static let maximumManagedOutputsPerDeletion = 100

    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let openedConnection = try SQLiteConnection(path: path)
        try Self.migrate(connection: openedConnection)
        self.connection = openedConnection
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func persist(
        events: [TelemetryEvent],
        checkpoint: AdapterCheckpoint? = nil
    ) throws -> PersistenceReceipt {
        if let checkpoint, let first = events.first, checkpoint.adapterID != first.adapterID {
            throw TelemetryStoreError.invalidCheckpoint
        }
        if let checkpoint, events.contains(where: { $0.adapterID != checkpoint.adapterID }) {
            throw TelemetryStoreError.invalidCheckpoint
        }

        try connection.beginImmediate()
        do {
            let persistedAt = Date()
            var inserted: [TelemetryEvent] = []
            var duplicates: [Int64] = []
            for event in events {
                let persisted = event.persisted(sequence: event.sequence ?? 0, at: persistedAt)
                let result = try insertOrFind(persisted)
                switch result {
                case .inserted(let sequence):
                    inserted.append(persisted.persisted(sequence: sequence, at: persistedAt))
                case .duplicate(let sequence):
                    duplicates.append(sequence)
                }
            }
            if let checkpoint {
                try upsert(checkpoint: checkpoint)
            }
            try connection.commit()
            return PersistenceReceipt(insertedEvents: inserted, duplicateSequences: duplicates, checkpoint: checkpoint)
        } catch {
            connection.rollback()
            throw error
        }
    }

    public func events(after sequence: Int64 = 0, limit: Int = 500) throws -> [TelemetryEvent] {
        let statement = try connection.prepare(
            """
            SELECT sequence, event_id, schema_name, schema_version, adapter_id, adapter_version,
                   source_native_id, source_idempotency_key, event_kind, occurred_at, observed_at,
                   persisted_at, monotonic_nanos, actor_id, device_id, project_id, repository_id,
                   worktree_id, branch, provider, client, model, thread_id, turn_id, work_unit_id,
                   parent_event_ids_json, payload_json, sensitivity, redaction_state, provenance_json,
                   confidence
            FROM telemetry_events
            WHERE sequence > ?
            ORDER BY sequence ASC
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(Int64(sequence), to: statement, at: 1)
        try connection.bind(Int64(max(1, min(limit, 500))), to: statement, at: 2)

        var result: [TelemetryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decodeEvent(statement))
        }
        let code = sqlite3_errcode(connection.db)
        if code != SQLITE_OK && code != SQLITE_ROW && code != SQLITE_DONE {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
        return result
    }

    public func eventCount(matching query: TelemetryEventQuery) throws -> Int {
        let statement = try connection.prepare(
            """
            SELECT COUNT(*)
            FROM telemetry_events
            WHERE occurred_at IS NOT NULL
              AND occurred_at >= ?
              AND occurred_at <= ?
              AND (? IS NULL OR repository_id = ?)
              AND (? IS NULL OR work_unit_id = ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(query.from.timeIntervalSince1970, to: statement, at: 1)
        try connection.bind(query.to.timeIntervalSince1970, to: statement, at: 2)
        try connection.bind(query.repositoryID, to: statement, at: 3)
        try connection.bind(query.repositoryID, to: statement, at: 4)
        try connection.bind(query.workUnitID, to: statement, at: 5)
        try connection.bind(query.workUnitID, to: statement, at: 6)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    public func events(matching query: TelemetryEventQuery) throws -> [TelemetryEvent] {
        let statement = try connection.prepare(
            """
            SELECT sequence, event_id, schema_name, schema_version, adapter_id, adapter_version,
                   source_native_id, source_idempotency_key, event_kind, occurred_at, observed_at,
                   persisted_at, monotonic_nanos, actor_id, device_id, project_id, repository_id,
                   worktree_id, branch, provider, client, model, thread_id, turn_id, work_unit_id,
                   parent_event_ids_json, payload_json, sensitivity, redaction_state, provenance_json,
                   confidence
            FROM telemetry_events
            WHERE occurred_at IS NOT NULL
              AND occurred_at >= ?
              AND occurred_at <= ?
              AND (? IS NULL OR repository_id = ?)
              AND (? IS NULL OR work_unit_id = ?)
            ORDER BY sequence ASC
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(query.from.timeIntervalSince1970, to: statement, at: 1)
        try connection.bind(query.to.timeIntervalSince1970, to: statement, at: 2)
        try connection.bind(query.repositoryID, to: statement, at: 3)
        try connection.bind(query.repositoryID, to: statement, at: 4)
        try connection.bind(query.workUnitID, to: statement, at: 5)
        try connection.bind(query.workUnitID, to: statement, at: 6)
        try connection.bind(Int64(max(1, min(query.limit, 500))), to: statement, at: 7)

        var result: [TelemetryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decodeEvent(statement))
        }
        let code = sqlite3_errcode(connection.db)
        if code != SQLITE_OK && code != SQLITE_ROW && code != SQLITE_DONE {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
        return result
    }

    public func checkpoint(adapterID: String, configurationID: String) throws -> AdapterCheckpoint? {
        let statement = try connection.prepare(
            """
            SELECT cursor, source_contract_version, updated_at
            FROM adapter_state
            WHERE adapter_id = ? AND configuration_id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(adapterID, to: statement, at: 1)
        try connection.bind(configurationID, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        guard
            let cursor = connection.columnText(statement, at: 0),
            let version = connection.columnText(statement, at: 1)
        else {
            throw TelemetryStoreError.decodingFailed
        }
        return AdapterCheckpoint(
            adapterID: adapterID,
            configurationID: configurationID,
            cursor: cursor,
            sourceContractVersion: version,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        )
    }

    public func setProjectionCheckpoint(_ checkpoint: ProjectionCheckpoint) throws {
        try connection.beginImmediate()
        do {
            let statement = try connection.prepare(
                """
                INSERT INTO projection_checkpoints (
                    projection_name, projection_version, last_sequence, rebuild_generation, updated_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(projection_name, projection_version) DO UPDATE SET
                    last_sequence = excluded.last_sequence,
                    rebuild_generation = excluded.rebuild_generation,
                    updated_at = excluded.updated_at;
                """
            )
            defer { sqlite3_finalize(statement) }
            try connection.bind(checkpoint.projectionName, to: statement, at: 1)
            try connection.bind(Int64(checkpoint.projectionVersion), to: statement, at: 2)
            try connection.bind(checkpoint.lastSequence, to: statement, at: 3)
            try connection.bind(Int64(checkpoint.rebuildGeneration), to: statement, at: 4)
            try connection.bind(checkpoint.updatedAt.timeIntervalSince1970, to: statement, at: 5)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }
            try connection.commit()
        } catch {
            connection.rollback()
            throw error
        }
    }

    public func projectionCheckpoint(name: String, version: Int) throws -> ProjectionCheckpoint? {
        let statement = try connection.prepare(
            """
            SELECT last_sequence, rebuild_generation, updated_at
            FROM projection_checkpoints
            WHERE projection_name = ? AND projection_version = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(name, to: statement, at: 1)
        try connection.bind(Int64(version), to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return ProjectionCheckpoint(
            projectionName: name,
            projectionVersion: version,
            lastSequence: sqlite3_column_int64(statement, 0),
            rebuildGeneration: Int(sqlite3_column_int64(statement, 1)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        )
    }

    public func health() throws -> StoreHealth {
        let schemaVersion = try currentSchemaVersion()
        let count = try scalarInt("SELECT COUNT(*) FROM telemetry_events;")
        return StoreHealth(
            schemaVersion: schemaVersion,
            eventCount: count,
            quickCheckPassed: try quickCheck()
        )
    }

    public func collectionState() throws -> CollectionState {
        let statement = try connection.prepare(
            "SELECT globally_paused, updated_at FROM collection_state WHERE singleton = 1;"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.decodingFailed
        }
        return CollectionState(
            globallyPaused: sqlite3_column_int(statement, 0) != 0,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    public func setGlobalPause(_ paused: Bool, at date: Date = Date()) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO collection_state (singleton, globally_paused, updated_at)
            VALUES (1, ?, ?)
            ON CONFLICT(singleton) DO UPDATE SET
                globally_paused = excluded.globally_paused,
                updated_at = excluded.updated_at;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(Int64(paused ? 1 : 0), to: statement, at: 1)
        try connection.bind(date.timeIntervalSince1970, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    public func setAdapterEnabled(
        adapterID: String,
        configurationID: String,
        enabled: Bool,
        at date: Date = Date()
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO adapter_preferences (adapter_id, configuration_id, enabled, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(adapter_id, configuration_id) DO UPDATE SET
                enabled = excluded.enabled,
                updated_at = excluded.updated_at;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(adapterID, to: statement, at: 1)
        try connection.bind(configurationID, to: statement, at: 2)
        try connection.bind(Int64(enabled ? 1 : 0), to: statement, at: 3)
        try connection.bind(date.timeIntervalSince1970, to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    public func adapterCollectionState(
        adapterID: String,
        configurationID: String
    ) throws -> AdapterCollectionState? {
        let statement = try connection.prepare(
            """
            SELECT enabled, updated_at
            FROM adapter_preferences
            WHERE adapter_id = ? AND configuration_id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(adapterID, to: statement, at: 1)
        try connection.bind(configurationID, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return AdapterCollectionState(
            adapterID: adapterID,
            configurationID: configurationID,
            enabled: sqlite3_column_int(statement, 0) != 0,
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    public func purgeEvents(
        occurredBefore: Date,
        includeUserSensitiveEvents: Bool
    ) throws -> PurgeReceipt {
        let predicate = includeUserSensitiveEvents
            ? "occurred_at IS NOT NULL AND occurred_at < ?"
            : "occurred_at IS NOT NULL AND occurred_at < ? AND sensitivity != 'user_sensitive'"
        try connection.beginImmediate()
        do {
            let associationStatement = try connection.prepare(
                "DELETE FROM associations WHERE event_id IN (SELECT event_id FROM telemetry_events WHERE \(predicate));"
            )
            defer { sqlite3_finalize(associationStatement) }
            try connection.bind(occurredBefore.timeIntervalSince1970, to: associationStatement, at: 1)
            guard sqlite3_step(associationStatement) == SQLITE_DONE else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }

            let eventStatement = try connection.prepare(
                "DELETE FROM telemetry_events WHERE \(predicate);"
            )
            defer { sqlite3_finalize(eventStatement) }
            try connection.bind(occurredBefore.timeIntervalSince1970, to: eventStatement, at: 1)
            guard sqlite3_step(eventStatement) == SQLITE_DONE else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }
            let deleted = Int(sqlite3_changes(connection.db))
            if deleted > 0 {
                try invalidateDerivedState()
            }
            try connection.commit()
            return PurgeReceipt(
                deletedEventCount: deleted,
                occurredBefore: occurredBefore,
                includedUserSensitiveEvents: includeUserSensitiveEvents
            )
        } catch {
            connection.rollback()
            throw error
        }
    }

    /// Returns only metadata about files WWMD itself generated and registered.
    /// The storage-private absolute path is never exposed by this API.
    public func managedOutputs() throws -> [ManagedOutput] {
        try allManagedOutputRecords().map(\.output)
    }

    /// Previews an exact deletion selection. The returned ledger sequence must
    /// match at confirmation, preventing a stale preview from deleting newly
    /// ingested data.
    public func previewDeletion(selection: DeletionSelection) throws -> DeletionPreview {
        try validateDeletionSelection(selection)
        let managedOutputRecords = try managedOutputRecords(ids: selection.managedOutputIDs)
        let matchingEventCount: Int
        if let eventScope = selection.eventScope {
            matchingEventCount = try eventCount(matchingDeletionScope: eventScope)
        } else {
            matchingEventCount = 0
        }
        return DeletionPreview(
            latestSequence: try latestEventSequence(),
            matchingEventCount: matchingEventCount,
            managedOutputs: managedOutputRecords.map(\.output)
        )
    }

    /// Deletes only the previously previewed scope and registered managed
    /// outputs. The file-system portion is deliberately limited to paths that
    /// this store registered while producing an export or backup.
    public func performDeletion(
        selection: DeletionSelection,
        expectedLatestSequence: Int64,
        scopeDigest: String,
        at date: Date = Date()
    ) throws -> DeletionReceipt {
        try validateDeletionSelection(selection)
        guard !scopeDigest.isEmpty else {
            throw TelemetryStoreError.invalidDeletionScope
        }
        let managedOutputRecords = try managedOutputRecords(ids: selection.managedOutputIDs)

        try connection.beginImmediate()
        do {
            guard try latestEventSequence() == expectedLatestSequence else {
                throw TelemetryStoreError.deletionPreviewStale
            }

            var deletedManagedOutputCount = 0
            var missingManagedOutputCount = 0
            for record in managedOutputRecords {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: record.absolutePath, isDirectory: &isDirectory) {
                    guard !isDirectory.boolValue else {
                        throw TelemetryStoreError.fileOperationFailed
                    }
                    guard try Self.fileChecksum(at: URL(fileURLWithPath: record.absolutePath)) == record.output.checksum else {
                        throw TelemetryStoreError.managedOutputChanged
                    }
                    try FileManager.default.removeItem(atPath: record.absolutePath)
                    deletedManagedOutputCount += 1
                } else {
                    missingManagedOutputCount += 1
                }
            }

            let deletedEventCount: Int
            if let eventScope = selection.eventScope {
                deletedEventCount = try deleteEvents(matchingDeletionScope: eventScope)
                if deletedEventCount > 0 {
                    try invalidateDerivedState()
                }
            } else {
                deletedEventCount = 0
            }

            try deleteManagedOutputRecords(ids: selection.managedOutputIDs)
            let receipt = DeletionReceipt(
                receiptID: UUID(),
                deletedEventCount: deletedEventCount,
                deletedManagedOutputCount: deletedManagedOutputCount,
                missingManagedOutputCount: missingManagedOutputCount,
                createdAt: date
            )
            try record(deletionReceipt: receipt, scopeDigest: scopeDigest)
            try connection.commit()
            return receipt
        } catch {
            connection.rollback()
            throw error
        }
    }

    public func export(
        to path: String,
        format: ExportFormat,
        profile: ExportProfile
    ) throws -> ExportReceipt {
        let url = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw TelemetryStoreError.destinationAlreadyExists
        }
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw TelemetryStoreError.fileOperationFailed
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            var sequence: Int64 = 0
            var count = 0
            var aiTurnCount = 0
            var complete = false
            switch format {
            case .ndjson:
                while !complete {
                    let page = try events(after: sequence)
                    if page.isEmpty {
                        complete = true
                        continue
                    }
                    for event in page where profile == .includeUserSensitive || event.sensitivity != .userSensitive {
                        let encoded = try encoder.encode(event)
                        handle.write(encoded)
                        handle.write(Data([0x0A]))
                        count += 1
                    }
                    sequence = page.last?.sequence ?? sequence
                }
            case .summaryCSV:
                while !complete {
                    let page = try events(after: sequence)
                    if page.isEmpty {
                        complete = true
                        continue
                    }
                    for event in page where profile == .includeUserSensitive || event.sensitivity != .userSensitive {
                        count += 1
                        if event.kind == .aiTurn {
                            aiTurnCount += 1
                        }
                    }
                    sequence = page.last?.sequence ?? sequence
                }
                let csv = "metric,value,unit,evidence_count\ntelemetry.event_count,\(count),event,\(count)\nai.turn.count,\(aiTurnCount),turn,\(aiTurnCount)\n"
                handle.write(Data(csv.utf8))
            }
            try handle.close()

            let createdAt = Date()
            let receipt = ExportReceipt(
                exportID: UUID(),
                format: format,
                profile: profile,
                eventCount: count,
                checksum: try Self.fileChecksum(at: url)
            )
            let managedOutput = try makeManagedOutputRecord(
                id: receipt.exportID,
                kind: .export,
                url: url,
                checksum: receipt.checksum,
                createdAt: createdAt
            )
            try connection.beginImmediate()
            do {
                try record(receipt: receipt, at: createdAt)
                try record(managedOutput: managedOutput)
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
            return receipt
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public func backup(to path: String) throws -> BackupReceipt {
        let url = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw TelemetryStoreError.destinationAlreadyExists
        }
        var destination: OpaquePointer?
        let openCode = sqlite3_open_v2(path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openCode == SQLITE_OK, let destination else {
            if let destination {
                sqlite3_close(destination)
            }
            throw TelemetryStoreError.backupFailed(code: openCode)
        }
        defer { sqlite3_close(destination) }

        do {
            guard let backup = sqlite3_backup_init(destination, "main", connection.db, "main") else {
                throw TelemetryStoreError.backupFailed(code: sqlite3_errcode(destination))
            }
            let stepCode = sqlite3_backup_step(backup, -1)
            let finishCode = sqlite3_backup_finish(backup)
            guard stepCode == SQLITE_DONE, finishCode == SQLITE_OK else {
                throw TelemetryStoreError.backupFailed(code: stepCode == SQLITE_DONE ? finishCode : stepCode)
            }
            let createdAt = Date()
            let receipt = BackupReceipt(backupID: UUID(), checksum: try Self.fileChecksum(at: url))
            let managedOutput = try makeManagedOutputRecord(
                id: receipt.backupID,
                kind: .backup,
                url: url,
                checksum: receipt.checksum,
                createdAt: createdAt
            )
            try connection.beginImmediate()
            do {
                try record(receipt: receipt, at: createdAt)
                try record(managedOutput: managedOutput)
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
            return receipt
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Call only after the agent has stopped and released its SQLite connection.
    public nonisolated static func deleteDatabaseFiles(at path: String) throws -> Int {
        let manager = FileManager.default
        let candidates = [path, "\(path)-wal", "\(path)-shm"]
        var deleted = 0
        do {
            for candidate in candidates where manager.fileExists(atPath: candidate) {
                try manager.removeItem(atPath: candidate)
                deleted += 1
            }
            return deleted
        } catch {
            throw TelemetryStoreError.fileOperationFailed
        }
    }

    public func rebuildableEventCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM telemetry_events;")
    }

    private struct ManagedOutputRecord {
        let output: ManagedOutput
        let absolutePath: String
    }

    private func validateDeletionSelection(_ selection: DeletionSelection) throws {
        guard selection.eventScope != nil || !selection.managedOutputIDs.isEmpty else {
            throw TelemetryStoreError.invalidDeletionScope
        }
        guard Set(selection.managedOutputIDs).count == selection.managedOutputIDs.count else {
            throw TelemetryStoreError.duplicateManagedOutputID
        }
        guard selection.managedOutputIDs.count <= Self.maximumManagedOutputsPerDeletion else {
            throw TelemetryStoreError.deletionSelectionTooLarge
        }
        if let scope = selection.eventScope {
            guard
                scope.to >= scope.from,
                scope.to.timeIntervalSince(scope.from) <= Double(366 * 86_400),
                scope.repositoryID?.isEmpty != true,
                scope.workUnitID?.isEmpty != true
            else {
                throw TelemetryStoreError.invalidDeletionScope
            }
        }
    }

    private func latestEventSequence() throws -> Int64 {
        let statement = try connection.prepare("SELECT COALESCE(MAX(sequence), 0) FROM telemetry_events;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func eventCount(matchingDeletionScope scope: EventDeletionScope) throws -> Int {
        let statement = try connection.prepare(
            "SELECT COUNT(*) FROM telemetry_events WHERE \(deletionPredicate(for: scope));"
        )
        defer { sqlite3_finalize(statement) }
        _ = try bind(scope, to: statement, startingAt: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func deleteEvents(matchingDeletionScope scope: EventDeletionScope) throws -> Int {
        let predicate = deletionPredicate(for: scope)
        let associationStatement = try connection.prepare(
            "DELETE FROM associations WHERE event_id IN (SELECT event_id FROM telemetry_events WHERE \(predicate));"
        )
        defer { sqlite3_finalize(associationStatement) }
        _ = try bind(scope, to: associationStatement, startingAt: 1)
        guard sqlite3_step(associationStatement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }

        let eventStatement = try connection.prepare(
            "DELETE FROM telemetry_events WHERE \(predicate);"
        )
        defer { sqlite3_finalize(eventStatement) }
        _ = try bind(scope, to: eventStatement, startingAt: 1)
        guard sqlite3_step(eventStatement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return Int(sqlite3_changes(connection.db))
    }

    private func invalidateDerivedState() throws {
        try connection.execute(
            """
            DELETE FROM associations;
            DELETE FROM work_units;
            DELETE FROM metric_windows;
            DELETE FROM recommendations;
            DELETE FROM projection_checkpoints;
            """
        )
    }

    private func deletionPredicate(for scope: EventDeletionScope) -> String {
        var predicates = [
            "occurred_at IS NOT NULL",
            "occurred_at >= ?",
            "occurred_at <= ?"
        ]
        if !scope.includeUserSensitiveEvents {
            predicates.append("sensitivity != 'user_sensitive'")
        }
        if scope.repositoryID != nil {
            predicates.append("repository_id = ?")
        }
        if scope.workUnitID != nil {
            predicates.append("work_unit_id = ?")
        }
        return predicates.joined(separator: " AND ")
    }

    @discardableResult
    private func bind(
        _ scope: EventDeletionScope,
        to statement: OpaquePointer?,
        startingAt index: Int32
    ) throws -> Int32 {
        var nextIndex = index
        try connection.bind(scope.from.timeIntervalSince1970, to: statement, at: nextIndex)
        nextIndex += 1
        try connection.bind(scope.to.timeIntervalSince1970, to: statement, at: nextIndex)
        nextIndex += 1
        if let repositoryID = scope.repositoryID {
            try connection.bind(repositoryID, to: statement, at: nextIndex)
            nextIndex += 1
        }
        if let workUnitID = scope.workUnitID {
            try connection.bind(workUnitID, to: statement, at: nextIndex)
            nextIndex += 1
        }
        return nextIndex
    }

    private func allManagedOutputRecords() throws -> [ManagedOutputRecord] {
        let statement = try connection.prepare(
            """
            SELECT output_id, output_kind, absolute_path, filename, byte_count,
                   manifest_checksum, created_at
            FROM managed_outputs
            ORDER BY created_at ASC, output_id ASC;
            """
        )
        defer { sqlite3_finalize(statement) }
        var records: [ManagedOutputRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(try decodeManagedOutputRecord(statement))
        }
        let code = sqlite3_errcode(connection.db)
        if code != SQLITE_OK && code != SQLITE_ROW && code != SQLITE_DONE {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
        return records
    }

    private func managedOutputRecords(ids: [UUID]) throws -> [ManagedOutputRecord] {
        guard !ids.isEmpty else { return [] }
        var records: [ManagedOutputRecord] = []
        for id in ids {
            let statement = try connection.prepare(
                """
                SELECT output_id, output_kind, absolute_path, filename, byte_count,
                       manifest_checksum, created_at
                FROM managed_outputs
                WHERE output_id = ?;
                """
            )
            defer { sqlite3_finalize(statement) }
            try connection.bind(id.uuidString, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TelemetryStoreError.managedOutputNotFound
            }
            records.append(try decodeManagedOutputRecord(statement))
        }
        return records
    }

    private func decodeManagedOutputRecord(_ statement: OpaquePointer?) throws -> ManagedOutputRecord {
        guard
            let idText = connection.columnText(statement, at: 0),
            let id = UUID(uuidString: idText),
            let kindText = connection.columnText(statement, at: 1),
            let kind = ManagedOutputKind(rawValue: kindText),
            let absolutePath = connection.columnText(statement, at: 2),
            let filename = connection.columnText(statement, at: 3),
            let checksum = connection.columnText(statement, at: 5)
        else {
            throw TelemetryStoreError.decodingFailed
        }
        let output = ManagedOutput(
            id: id,
            kind: kind,
            filename: filename,
            byteCount: sqlite3_column_int64(statement, 4),
            checksum: checksum,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        )
        return ManagedOutputRecord(output: output, absolutePath: absolutePath)
    }

    private func makeManagedOutputRecord(
        id: UUID,
        kind: ManagedOutputKind,
        url: URL,
        checksum: String,
        createdAt: Date
    ) throws -> ManagedOutputRecord {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.isFileURL, standardizedURL.path.hasPrefix("/") else {
            throw TelemetryStoreError.fileOperationFailed
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              !standardizedURL.lastPathComponent.isEmpty
        else {
            throw TelemetryStoreError.fileOperationFailed
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: standardizedURL.path)
        guard let byteCount = (attributes[.size] as? NSNumber)?.int64Value else {
            throw TelemetryStoreError.fileOperationFailed
        }
        let output = ManagedOutput(
            id: id,
            kind: kind,
            filename: standardizedURL.lastPathComponent,
            byteCount: byteCount,
            checksum: checksum,
            createdAt: createdAt
        )
        return ManagedOutputRecord(output: output, absolutePath: standardizedURL.path)
    }

    private func deleteManagedOutputRecords(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let statement = try connection.prepare("DELETE FROM managed_outputs WHERE output_id = ?;")
        defer { sqlite3_finalize(statement) }
        for id in ids {
            try connection.bind(id.uuidString, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }
            guard sqlite3_changes(connection.db) == 1 else {
                throw TelemetryStoreError.managedOutputNotFound
            }
            guard sqlite3_reset(statement) == SQLITE_OK else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }
            guard sqlite3_clear_bindings(statement) == SQLITE_OK else {
                throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
            }
        }
    }

    private enum InsertResult {
        case inserted(Int64)
        case duplicate(Int64)
    }

    private func insertOrFind(_ event: TelemetryEvent) throws -> InsertResult {
        let statement = try connection.prepare(
            """
            INSERT OR IGNORE INTO telemetry_events (
                event_id, schema_name, schema_version, adapter_id, adapter_version,
                source_native_id, source_idempotency_key, event_kind, occurred_at,
                observed_at, persisted_at, monotonic_nanos, actor_id, device_id,
                project_id, repository_id, worktree_id, branch, provider, client,
                model, thread_id, turn_id, work_unit_id, parent_event_ids_json,
                payload_json, sensitivity, redaction_state, provenance_json, confidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        let parentIDs = try encoder.encode(event.parentEventIDs)
        let payload = try encoder.encode(event.payload)
        let provenance = try encoder.encode(event.provenance)
        let persistedAt = event.persistedAt ?? Date()

        try connection.bind(event.eventID.uuidString, to: statement, at: 1)
        try connection.bind(event.schemaName, to: statement, at: 2)
        try connection.bind(Int64(event.schemaVersion), to: statement, at: 3)
        try connection.bind(event.adapterID, to: statement, at: 4)
        try connection.bind(event.adapterVersion, to: statement, at: 5)
        try connection.bind(event.sourceNativeID, to: statement, at: 6)
        try connection.bind(event.sourceIdempotencyKey, to: statement, at: 7)
        try connection.bind(event.kind.rawValue, to: statement, at: 8)
        try connection.bind(event.occurredAt?.timeIntervalSince1970, to: statement, at: 9)
        try connection.bind(event.observedAt.timeIntervalSince1970, to: statement, at: 10)
        try connection.bind(persistedAt.timeIntervalSince1970, to: statement, at: 11)
        if let monotonic = event.monotonicNanoseconds {
            try connection.bind(Int64(bitPattern: monotonic), to: statement, at: 12)
        } else {
            try connection.bindNull(to: statement, at: 12)
        }
        try connection.bind(event.actorID.uuidString, to: statement, at: 13)
        try connection.bind(event.deviceID.uuidString, to: statement, at: 14)
        try connection.bind(event.projectID, to: statement, at: 15)
        try connection.bind(event.repositoryID, to: statement, at: 16)
        try connection.bind(event.worktreeID, to: statement, at: 17)
        try connection.bind(event.branch, to: statement, at: 18)
        try connection.bind(event.provider, to: statement, at: 19)
        try connection.bind(event.client, to: statement, at: 20)
        try connection.bind(event.model, to: statement, at: 21)
        try connection.bind(event.threadID, to: statement, at: 22)
        try connection.bind(event.turnID, to: statement, at: 23)
        try connection.bind(event.workUnitID, to: statement, at: 24)
        try connection.bind(parentIDs, to: statement, at: 25)
        try connection.bind(payload, to: statement, at: 26)
        try connection.bind(event.sensitivity.rawValue, to: statement, at: 27)
        try connection.bind(event.redactionState.rawValue, to: statement, at: 28)
        try connection.bind(provenance, to: statement, at: 29)
        try connection.bind(event.confidence, to: statement, at: 30)

        let step = sqlite3_step(statement)
        guard step == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: step)
        }
        if sqlite3_changes(connection.db) == 1 {
            return .inserted(sqlite3_last_insert_rowid(connection.db))
        }
        let existing = try existingSequence(for: event)
        return .duplicate(existing)
    }

    private func existingSequence(for event: TelemetryEvent) throws -> Int64 {
        let statement = try connection.prepare(
            """
            SELECT sequence
            FROM telemetry_events
            WHERE source_idempotency_key = ? OR event_id = ?
            ORDER BY sequence ASC
            LIMIT 1;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(event.sourceIdempotencyKey, to: statement, at: 1)
        try connection.bind(event.eventID.uuidString, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.decodingFailed
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func upsert(checkpoint: AdapterCheckpoint) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO adapter_state (
                adapter_id, configuration_id, health, cursor, source_contract_version, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(adapter_id, configuration_id) DO UPDATE SET
                health = excluded.health,
                cursor = excluded.cursor,
                source_contract_version = excluded.source_contract_version,
                updated_at = excluded.updated_at;
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(checkpoint.adapterID, to: statement, at: 1)
        try connection.bind(checkpoint.configurationID, to: statement, at: 2)
        try connection.bind(AdapterHealthState.healthy.rawValue, to: statement, at: 3)
        try connection.bind(checkpoint.cursor, to: statement, at: 4)
        try connection.bind(checkpoint.sourceContractVersion, to: statement, at: 5)
        try connection.bind(checkpoint.updatedAt.timeIntervalSince1970, to: statement, at: 6)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: result)
        }
    }

    private func decodeEvent(_ statement: OpaquePointer?) throws -> TelemetryEvent {
        guard
            let eventIDText = connection.columnText(statement, at: 1),
            let eventID = UUID(uuidString: eventIDText),
            let schemaName = connection.columnText(statement, at: 2),
            let adapterID = connection.columnText(statement, at: 4),
            let adapterVersion = connection.columnText(statement, at: 5),
            let idempotency = connection.columnText(statement, at: 7),
            let kindText = connection.columnText(statement, at: 8),
            let kind = TelemetryEventKind(rawValue: kindText),
            let actorText = connection.columnText(statement, at: 13),
            let actorID = UUID(uuidString: actorText),
            let deviceText = connection.columnText(statement, at: 14),
            let deviceID = UUID(uuidString: deviceText),
            let parentData = connection.columnData(statement, at: 25),
            let payloadData = connection.columnData(statement, at: 26),
            let sensitivityText = connection.columnText(statement, at: 27),
            let sensitivity = Sensitivity(rawValue: sensitivityText),
            let redactionText = connection.columnText(statement, at: 28),
            let redactionState = RedactionState(rawValue: redactionText),
            let provenanceData = connection.columnData(statement, at: 29)
        else {
            throw TelemetryStoreError.decodingFailed
        }
        let parentIDs = try decoder.decode([UUID].self, from: parentData)
        let payload = try decoder.decode([String: JSONValue].self, from: payloadData)
        let provenance = try decoder.decode([String: FieldProvenance].self, from: provenanceData)
        let occurredAt = sqlite3_column_type(statement, 9) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
        let monotonic = sqlite3_column_type(statement, 12) == SQLITE_NULL
            ? nil
            : UInt64(bitPattern: sqlite3_column_int64(statement, 12))
        let confidence = sqlite3_column_type(statement, 30) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, 30)

        return TelemetryEvent(
            eventID: eventID,
            schemaName: schemaName,
            schemaVersion: Int(sqlite3_column_int64(statement, 3)),
            sequence: sqlite3_column_int64(statement, 0),
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            sourceNativeID: connection.columnText(statement, at: 6),
            sourceIdempotencyKey: idempotency,
            kind: kind,
            occurredAt: occurredAt,
            observedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            persistedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
            monotonicNanoseconds: monotonic,
            actorID: actorID,
            deviceID: deviceID,
            projectID: connection.columnText(statement, at: 15),
            repositoryID: connection.columnText(statement, at: 16),
            worktreeID: connection.columnText(statement, at: 17),
            branch: connection.columnText(statement, at: 18),
            provider: connection.columnText(statement, at: 19),
            client: connection.columnText(statement, at: 20),
            model: connection.columnText(statement, at: 21),
            threadID: connection.columnText(statement, at: 22),
            turnID: connection.columnText(statement, at: 23),
            workUnitID: connection.columnText(statement, at: 24),
            parentEventIDs: parentIDs,
            payload: payload,
            sensitivity: sensitivity,
            redactionState: redactionState,
            provenance: provenance,
            confidence: confidence
        )
    }

    private nonisolated static func migrate(connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                checksum TEXT NOT NULL,
                applied_at REAL NOT NULL
            );
            """
        )
        let current = try migrationSchemaVersion(connection)
        guard current <= Self.latestSchemaVersion else {
            throw TelemetryStoreError.migrationFailed(version: current)
        }
        if current < 1 {
            try connection.beginImmediate()
            do {
                try connection.execute(
                    """
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
                    CREATE INDEX telemetry_events_kind_occurred_idx
                        ON telemetry_events(event_kind, occurred_at, sequence);
                    CREATE INDEX telemetry_events_repository_occurred_idx
                        ON telemetry_events(repository_id, occurred_at, sequence);
                    CREATE INDEX telemetry_events_work_unit_sequence_idx
                        ON telemetry_events(work_unit_id, sequence);
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
                )
                let migration = try connection.prepare(
                    "INSERT INTO schema_migrations (version, checksum, applied_at) VALUES (?, ?, ?);"
                )
                defer { sqlite3_finalize(migration) }
                try connection.bind(Int64(1), to: migration, at: 1)
                try connection.bind(StableHash.sha256("wwmd-schema-v1"), to: migration, at: 2)
                try connection.bind(Date().timeIntervalSince1970, to: migration, at: 3)
                guard sqlite3_step(migration) == SQLITE_DONE else {
                    throw TelemetryStoreError.migrationFailed(version: 1)
                }
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
        }
        if current < 2 {
            try connection.beginImmediate()
            do {
                try connection.execute(
                    """
                    CREATE TABLE work_units (
                        work_unit_id TEXT PRIMARY KEY,
                        kind TEXT NOT NULL,
                        repository_id TEXT,
                        worktree_id TEXT,
                        branch TEXT,
                        started_at REAL NOT NULL,
                        ended_at REAL,
                        user_confirmed INTEGER NOT NULL,
                        latest_event_sequence INTEGER NOT NULL
                    );
                    CREATE TABLE associations (
                        association_id TEXT PRIMARY KEY,
                        event_id TEXT NOT NULL,
                        work_unit_id TEXT NOT NULL,
                        score REAL NOT NULL,
                        evidence_json BLOB NOT NULL,
                        rule_version INTEGER NOT NULL,
                        state TEXT NOT NULL,
                        correction_event_id TEXT,
                        UNIQUE(event_id, work_unit_id, rule_version),
                        FOREIGN KEY(event_id) REFERENCES telemetry_events(event_id)
                    );
                    CREATE TABLE metric_windows (
                        metric_name TEXT NOT NULL,
                        metric_version INTEGER NOT NULL,
                        window_start REAL NOT NULL,
                        window_end REAL NOT NULL,
                        dimensions_json BLOB NOT NULL,
                        value REAL,
                        unit TEXT NOT NULL,
                        evidence_count INTEGER NOT NULL,
                        availability TEXT NOT NULL,
                        explanation TEXT NOT NULL,
                        price_table_version TEXT,
                        PRIMARY KEY(metric_name, metric_version, window_start, window_end, dimensions_json)
                    );
                    CREATE TABLE recommendations (
                        recommendation_id TEXT PRIMARY KEY,
                        rule_id TEXT NOT NULL,
                        rule_version INTEGER NOT NULL,
                        scope_key TEXT NOT NULL,
                        severity TEXT NOT NULL,
                        evidence_grade TEXT NOT NULL,
                        state TEXT NOT NULL,
                        emitted_sequence INTEGER NOT NULL,
                        dismissed_sequence INTEGER,
                        snoozed_until REAL,
                        UNIQUE(rule_id, rule_version, scope_key, state)
                    );
                    CREATE TABLE export_receipts (
                        export_id TEXT PRIMARY KEY,
                        format TEXT NOT NULL,
                        manifest_checksum TEXT NOT NULL,
                        redaction_profile TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE backup_receipts (
                        backup_id TEXT PRIMARY KEY,
                        manifest_checksum TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    """
                )
                let migration = try connection.prepare(
                    "INSERT INTO schema_migrations (version, checksum, applied_at) VALUES (?, ?, ?);"
                )
                defer { sqlite3_finalize(migration) }
                try connection.bind(Int64(2), to: migration, at: 1)
                try connection.bind(StableHash.sha256("wwmd-schema-v2-projections"), to: migration, at: 2)
                try connection.bind(Date().timeIntervalSince1970, to: migration, at: 3)
                guard sqlite3_step(migration) == SQLITE_DONE else {
                    throw TelemetryStoreError.migrationFailed(version: 2)
                }
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
        }
        if current < 3 {
            try connection.beginImmediate()
            do {
                try connection.execute(
                    """
                    CREATE TABLE collection_state (
                        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                        globally_paused INTEGER NOT NULL,
                        updated_at REAL NOT NULL
                    );
                    INSERT INTO collection_state (singleton, globally_paused, updated_at)
                    VALUES (1, 0, 0);
                    CREATE TABLE adapter_preferences (
                        adapter_id TEXT NOT NULL,
                        configuration_id TEXT NOT NULL,
                        enabled INTEGER NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY(adapter_id, configuration_id)
                    );
                    """
                )
                let migration = try connection.prepare(
                    "INSERT INTO schema_migrations (version, checksum, applied_at) VALUES (?, ?, ?);"
                )
                defer { sqlite3_finalize(migration) }
                try connection.bind(Int64(3), to: migration, at: 1)
                try connection.bind(StableHash.sha256("wwmd-schema-v3-collection-state"), to: migration, at: 2)
                try connection.bind(Date().timeIntervalSince1970, to: migration, at: 3)
                guard sqlite3_step(migration) == SQLITE_DONE else {
                    throw TelemetryStoreError.migrationFailed(version: 3)
                }
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
        }
        if current < 4 {
            try connection.beginImmediate()
            do {
                try connection.execute(
                    """
                    CREATE TABLE managed_outputs (
                        output_id TEXT PRIMARY KEY,
                        output_kind TEXT NOT NULL,
                        absolute_path TEXT NOT NULL,
                        filename TEXT NOT NULL,
                        byte_count INTEGER NOT NULL,
                        manifest_checksum TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        UNIQUE(output_kind, absolute_path)
                    );
                    CREATE TABLE deletion_receipts (
                        receipt_id TEXT PRIMARY KEY,
                        scope_digest TEXT NOT NULL,
                        deleted_event_count INTEGER NOT NULL,
                        deleted_managed_output_count INTEGER NOT NULL,
                        missing_managed_output_count INTEGER NOT NULL,
                        created_at REAL NOT NULL
                    );
                    """
                )
                let migration = try connection.prepare(
                    "INSERT INTO schema_migrations (version, checksum, applied_at) VALUES (?, ?, ?);"
                )
                defer { sqlite3_finalize(migration) }
                try connection.bind(Int64(4), to: migration, at: 1)
                try connection.bind(StableHash.sha256("wwmd-schema-v4-managed-deletion"), to: migration, at: 2)
                try connection.bind(Date().timeIntervalSince1970, to: migration, at: 3)
                guard sqlite3_step(migration) == SQLITE_DONE else {
                    throw TelemetryStoreError.migrationFailed(version: 4)
                }
                try connection.commit()
            } catch {
                connection.rollback()
                throw error
            }
        }
    }

    private nonisolated static func migrationSchemaVersion(_ connection: SQLiteConnection) throws -> Int {
        let statement = try connection.prepare("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func currentSchemaVersion() throws -> Int {
        try scalarInt("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;")
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try connection.prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func quickCheck() throws -> Bool {
        let statement = try connection.prepare("PRAGMA quick_check;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
        return connection.columnText(statement, at: 0) == "ok"
    }

    private func record(receipt: ExportReceipt, at date: Date) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO export_receipts (
                export_id, format, manifest_checksum, redaction_profile, created_at
            ) VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(receipt.exportID.uuidString, to: statement, at: 1)
        try connection.bind(receipt.format.rawValue, to: statement, at: 2)
        try connection.bind(receipt.checksum, to: statement, at: 3)
        try connection.bind(receipt.profile.rawValue, to: statement, at: 4)
        try connection.bind(date.timeIntervalSince1970, to: statement, at: 5)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    private func record(receipt: BackupReceipt, at date: Date) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO backup_receipts (backup_id, manifest_checksum, created_at)
            VALUES (?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(receipt.backupID.uuidString, to: statement, at: 1)
        try connection.bind(receipt.checksum, to: statement, at: 2)
        try connection.bind(date.timeIntervalSince1970, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    private func record(managedOutput record: ManagedOutputRecord) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO managed_outputs (
                output_id, output_kind, absolute_path, filename, byte_count,
                manifest_checksum, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(record.output.id.uuidString, to: statement, at: 1)
        try connection.bind(record.output.kind.rawValue, to: statement, at: 2)
        try connection.bind(record.absolutePath, to: statement, at: 3)
        try connection.bind(record.output.filename, to: statement, at: 4)
        try connection.bind(record.output.byteCount, to: statement, at: 5)
        try connection.bind(record.output.checksum, to: statement, at: 6)
        try connection.bind(record.output.createdAt.timeIntervalSince1970, to: statement, at: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    private func record(deletionReceipt receipt: DeletionReceipt, scopeDigest: String) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO deletion_receipts (
                receipt_id, scope_digest, deleted_event_count,
                deleted_managed_output_count, missing_managed_output_count, created_at
            ) VALUES (?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try connection.bind(receipt.receiptID.uuidString, to: statement, at: 1)
        try connection.bind(scopeDigest, to: statement, at: 2)
        try connection.bind(Int64(receipt.deletedEventCount), to: statement, at: 3)
        try connection.bind(Int64(receipt.deletedManagedOutputCount), to: statement, at: 4)
        try connection.bind(Int64(receipt.missingManagedOutputCount), to: statement, at: 5)
        try connection.bind(receipt.createdAt.timeIntervalSince1970, to: statement, at: 6)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TelemetryStoreError.sqliteFailed(code: sqlite3_errcode(connection.db))
        }
    }

    private nonisolated static func fileChecksum(at url: URL) throws -> String {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            throw TelemetryStoreError.fileOperationFailed
        }
    }
}

private final class SQLiteConnection {
    let db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard code == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw TelemetryStoreError.openFailed(code: code)
        }
        db = handle
        do {
            try execute("PRAGMA foreign_keys = ON;")
            try execute("PRAGMA journal_mode = WAL;")
            try execute("PRAGMA synchronous = NORMAL;")
            try execute("PRAGMA busy_timeout = 5000;")
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func beginImmediate() throws {
        try execute("BEGIN IMMEDIATE;")
    }

    func commit() throws {
        try execute("COMMIT;")
    }

    func rollback() {
        try? execute("ROLLBACK;")
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if errorMessage != nil {
            sqlite3_free(errorMessage)
        }
        guard code == SQLITE_OK else {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK else {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
        return statement
    }

    func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) throws {
        let code: Int32
        if let value {
            code = value.withCString {
                sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
            }
        } else {
            code = sqlite3_bind_null(statement, index)
        }
        try checkBind(code)
    }

    func bind(_ value: Int64, to statement: OpaquePointer?, at index: Int32) throws {
        try checkBind(sqlite3_bind_int64(statement, index, value))
    }

    func bind(_ value: Double?, to statement: OpaquePointer?, at index: Int32) throws {
        if let value {
            try checkBind(sqlite3_bind_double(statement, index, value))
        } else {
            try bindNull(to: statement, at: index)
        }
    }

    func bind(_ value: Data, to statement: OpaquePointer?, at index: Int32) throws {
        let code = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
        try checkBind(code)
    }

    func bindNull(to statement: OpaquePointer?, at index: Int32) throws {
        try checkBind(sqlite3_bind_null(statement, index))
    }

    func columnText(_ statement: OpaquePointer?, at index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func columnData(_ statement: OpaquePointer?, at index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func checkBind(_ code: Int32) throws {
        guard code == SQLITE_OK else {
            throw TelemetryStoreError.sqliteFailed(code: code)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
