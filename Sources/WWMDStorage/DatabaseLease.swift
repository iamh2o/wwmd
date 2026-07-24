import Darwin
import Foundation

public enum DatabaseLeaseError: Error, Equatable, Sendable, LocalizedError {
    case databasePathMustBeAbsolute
    case databasePathIsDirectory
    case lockFileOpenFailed
    case databaseAlreadyInUse

    public var errorDescription: String? {
        switch self {
        case .databasePathMustBeAbsolute:
            "WWMD requires an explicit absolute database file path."
        case .databasePathIsDirectory:
            "WWMD requires a database file path, not a directory."
        case .lockFileOpenFailed:
            "WWMD could not create or open its local database lease file."
        case .databaseAlreadyInUse:
            "This WWMD database is already open by another WWMD runtime. Close that runtime before opening it here."
        }
    }
}

/// An advisory, process-lifetime lease for one explicitly selected WWMD
/// database. Both local app mode and `wwmdd` acquire it before opening SQLite,
/// preventing those supported entrypoints from becoming concurrent writers.
public final class DatabaseLease: @unchecked Sendable {
    public let databasePath: String
    public let lockPath: String

    private let descriptor: Int32

    public init(databasePath: String) throws {
        let databaseURL = URL(fileURLWithPath: databasePath).standardizedFileURL
        guard databaseURL.isFileURL, databaseURL.path.hasPrefix("/"), databaseURL.path != "/" else {
            throw DatabaseLeaseError.databasePathMustBeAbsolute
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: databaseURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw DatabaseLeaseError.databasePathIsDirectory
        }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lockPath = "\(databaseURL.path).wwmd.lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw DatabaseLeaseError.lockFileOpenFailed
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            if errno == EWOULDBLOCK || errno == EAGAIN {
                throw DatabaseLeaseError.databaseAlreadyInUse
            }
            throw DatabaseLeaseError.lockFileOpenFailed
        }
        self.databasePath = databaseURL.path
        self.lockPath = lockPath
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
    }
}
