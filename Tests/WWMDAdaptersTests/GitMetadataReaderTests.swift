import XCTest
@testable import WWMDAdapters

final class GitMetadataReaderTests: XCTestCase {
    func testReaderEmitsOnlyAggregateCommitMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-git-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let runner = FixtureGitRunner(root: root)
        let snapshot = try GitMetadataReader(runner: runner).latestCommit(at: root)

        XCTAssertTrue(snapshot.repositoryID.hasPrefix("repo:"))
        XCTAssertEqual(snapshot.commitInput.commitOID, "0123456789abcdef")
        XCTAssertEqual(snapshot.commitInput.branch, "main")
        XCTAssertEqual(snapshot.commitInput.parentCount, 1)
        XCTAssertEqual(snapshot.commitInput.changedFileCount, 3)
        XCTAssertEqual(snapshot.commitInput.insertions, 10)
        XCTAssertEqual(snapshot.commitInput.deletions, 2)
    }

    func testReaderRejectsSelectedSubdirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wwmd-git-root-\(UUID().uuidString)", isDirectory: true)
        let child = directory.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = FixtureGitRunner(root: directory)
        XCTAssertThrowsError(try GitMetadataReader(runner: runner).latestCommit(at: child)) { error in
            XCTAssertEqual(error as? GitMetadataReaderError, .rootIsNotRepositoryRoot)
        }
    }
}

private struct FixtureGitRunner: GitCommandRunning {
    let root: URL

    func run(arguments: [String], repositoryRoot: URL) throws -> String {
        switch arguments {
        case ["rev-parse", "--show-toplevel"]:
            return "\(root.resolvingSymlinksInPath().standardizedFileURL.path)\n"
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
