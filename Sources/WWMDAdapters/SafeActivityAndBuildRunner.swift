import Foundation
import WWMDCore

public enum SafeActivitySessionState: String, Sendable {
    case started
    case ended
}

public struct SafeActivitySessionInput: Sendable, Equatable {
    public let idempotencyKey: String
    public let occurredAt: Date
    public let state: SafeActivitySessionState
    public let applicationBundleIdentifier: String
    public let repositoryID: String?

    public init(
        idempotencyKey: String,
        occurredAt: Date,
        state: SafeActivitySessionState,
        applicationBundleIdentifier: String,
        repositoryID: String? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.occurredAt = occurredAt
        self.state = state
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.repositoryID = repositoryID
    }
}

public enum SafeActivityAdapter {
    public static func sessionOffer(_ input: SafeActivitySessionInput) -> SourceEventOffer {
        let payload: [String: JSONValue] = [
            "session_state": .string(input.state.rawValue),
            "application_bundle_id": .string(input.applicationBundleIdentifier),
            "repository_id": input.repositoryID.map(JSONValue.string) ?? .null
        ]
        let provenance = Dictionary(uniqueKeysWithValues: payload.keys.map {
            ($0, FieldProvenance(source: "activity.safe", measurement: .measured))
        })
        return SourceEventOffer(
            descriptor: V0AdapterDescriptors.activity,
            sourceIdempotencyKey: input.idempotencyKey,
            kind: .activitySession,
            occurredAt: input.occurredAt,
            repositoryID: input.repositoryID,
            payload: payload,
            sensitivity: .privateMetadata,
            provenance: provenance
        )
    }
}

public enum ExplicitValidationRunnerError: Error, Equatable, Sendable, LocalizedError {
    case processCouldNotStart

    public var errorDescription: String? {
        "The explicit validation command could not start."
    }
}

public protocol ValidationProcessRunning: Sendable {
    func run(executable: URL, arguments: [String]) throws -> Int32
}

public struct SystemValidationProcessRunner: ValidationProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            throw ExplicitValidationRunnerError.processCouldNotStart
        }
    }
}

public struct ExplicitValidationRequest: Sendable, Equatable {
    public let idempotencyKey: String
    public let category: ValidationCategory
    public let executable: URL
    public let arguments: [String]
    public let repositoryID: String?
    public let workUnitID: String?

    public init(
        idempotencyKey: String,
        category: ValidationCategory,
        executable: URL,
        arguments: [String],
        repositoryID: String? = nil,
        workUnitID: String? = nil
    ) {
        self.idempotencyKey = idempotencyKey
        self.category = category
        self.executable = executable
        self.arguments = arguments
        self.repositoryID = repositoryID
        self.workUnitID = workUnitID
    }
}

public struct ExplicitValidationRunner<Runner: ValidationProcessRunning>: Sendable {
    private let runner: Runner
    private let now: @Sendable () -> Date

    public init(runner: Runner, now: @escaping @Sendable () -> Date = Date.init) {
        self.runner = runner
        self.now = now
    }

    /// Command arguments are deliberately ephemeral. The returned offer contains
    /// only category, timing, aggregate status, and explicit scope metadata.
    public func execute(_ request: ExplicitValidationRequest) throws -> SourceEventOffer {
        let startedAt = now()
        let status = try runner.run(executable: request.executable, arguments: request.arguments)
        let endedAt = now()
        return BuildTestAdapter.resultOffer(
            BuildTestInput(
                idempotencyKey: request.idempotencyKey,
                category: request.category,
                startedAt: startedAt,
                endedAt: endedAt,
                status: status == 0 ? .passed : .failed,
                repositoryID: request.repositoryID,
                workUnitID: request.workUnitID
            )
        )
    }
}
