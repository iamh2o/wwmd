import Foundation
import WWMDCore

public enum GitMetadataReaderError: Error, Equatable, Sendable, LocalizedError {
    case rootDoesNotExist
    case rootIsNotRepositoryRoot
    case commandFailed(status: Int32)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .rootDoesNotExist:
            "The selected Git repository root does not exist."
        case .rootIsNotRepositoryRoot:
            "The selected path is not the exact Git repository root."
        case .commandFailed(let status):
            "Git metadata command failed with exit status \(status)."
        case .invalidOutput:
            "Git returned metadata that did not satisfy the WWMD contract."
        }
    }
}

public protocol GitCommandRunning: Sendable {
    func run(arguments: [String], repositoryRoot: URL) throws -> String
}

public struct SystemGitCommandRunner: GitCommandRunning {
    public init() {}

    public func run(arguments: [String], repositoryRoot: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryRoot.path] + arguments
        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitMetadataReaderError.commandFailed(status: -1)
        }
        guard process.terminationStatus == 0 else {
            throw GitMetadataReaderError.commandFailed(status: process.terminationStatus)
        }
        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw GitMetadataReaderError.invalidOutput
        }
        return output
    }
}

public struct GitRepositorySnapshot: Sendable, Equatable {
    public let repositoryID: String
    public let commitInput: GitCommitInput

    public init(repositoryID: String, commitInput: GitCommitInput) {
        self.repositoryID = repositoryID
        self.commitInput = commitInput
    }
}

public struct GitMetadataReader<Runner: GitCommandRunning>: Sendable {
    private let runner: Runner

    public init(runner: Runner) {
        self.runner = runner
    }

    public func latestCommit(at explicitRepositoryRoot: URL) throws -> GitRepositorySnapshot {
        let requestedRoot = explicitRepositoryRoot.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: requestedRoot.path) else {
            throw GitMetadataReaderError.rootDoesNotExist
        }
        let reportedRootText = try runner.run(
            arguments: ["rev-parse", "--show-toplevel"],
            repositoryRoot: requestedRoot
        )
        let reportedRoot = URL(
            fileURLWithPath: reportedRootText.trimmingCharacters(in: .whitespacesAndNewlines)
        ).resolvingSymlinksInPath().standardizedFileURL
        guard reportedRoot == requestedRoot else {
            throw GitMetadataReaderError.rootIsNotRepositoryRoot
        }

        let commitOID = try parseCommitOID(
            runner.run(arguments: ["rev-parse", "HEAD"], repositoryRoot: requestedRoot)
        )
        let branch = try parseBranch(
            runner.run(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], repositoryRoot: requestedRoot)
        )
        let timestamp = try parseUnixTimestamp(
            runner.run(arguments: ["show", "-s", "--format=%ct", "HEAD"], repositoryRoot: requestedRoot)
        )
        let parents = try parseParents(
            runner.run(arguments: ["show", "-s", "--format=%P", "HEAD"], repositoryRoot: requestedRoot)
        )
        let changeCounts: (insertions: Int, deletions: Int, changedFiles: Int)
        if parents.isEmpty {
            changeCounts = (0, 0, 0)
        } else {
            changeCounts = try parseShortStat(
                runner.run(arguments: ["diff", "--shortstat", "HEAD^", "HEAD"], repositoryRoot: requestedRoot)
            )
        }

        let repositoryID = "repo:\(StableHash.sha256("git.local.repository.v1:\(reportedRoot.path)").prefix(16))"
        let input = GitCommitInput(
            idempotencyKey: StableHash.sha256("git.local.commit.v1:\(repositoryID):\(commitOID)"),
            occurredAt: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            repositoryID: repositoryID,
            branch: branch,
            commitOID: commitOID,
            parentCount: parents.count,
            changedFileCount: changeCounts.changedFiles,
            insertions: changeCounts.insertions,
            deletions: changeCounts.deletions
        )
        return GitRepositorySnapshot(repositoryID: repositoryID, commitInput: input)
    }

    private func parseCommitOID(_ output: String) throws -> String {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (7...64).contains(value.count), value.allSatisfy(\.isHexDigit) else {
            throw GitMetadataReaderError.invalidOutput
        }
        return value
    }

    private func parseBranch(_ output: String) throws -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw GitMetadataReaderError.invalidOutput
        }
        return value == "HEAD" ? nil : value
    }

    private func parseUnixTimestamp(_ output: String) throws -> Int64 {
        guard let value = Int64(output.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
            throw GitMetadataReaderError.invalidOutput
        }
        return value
    }

    private func parseParents(_ output: String) throws -> [String] {
        let values = output.split(whereSeparator: \.isWhitespace).map(String.init)
        guard values.allSatisfy({ (7...64).contains($0.count) && $0.allSatisfy(\.isHexDigit) }) else {
            throw GitMetadataReaderError.invalidOutput
        }
        return values
    }

    private func parseShortStat(_ output: String) throws -> (insertions: Int, deletions: Int, changedFiles: Int) {
        let values = output
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard values.count == 3 else {
            throw GitMetadataReaderError.invalidOutput
        }
        return (insertions: values[1], deletions: values[2], changedFiles: values[0])
    }
}
