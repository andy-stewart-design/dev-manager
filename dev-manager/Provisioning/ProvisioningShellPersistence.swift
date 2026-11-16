import Darwin
import Foundation

/// The filesystem boundary for shell configuration. Locations are injectable so
/// tests never need to touch the user's home directory. All reads use lstat/open
/// with no-follow checks and all replacements are bounded, metadata-preserving,
/// fsynced atomic writes.
struct ProvisioningShellLocation: Sendable {
    let homeURL: URL
    let applicationSupportURL: URL

    init(homeURL: URL, applicationSupportURL: URL) {
        self.homeURL = homeURL.standardizedFileURL
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
    }

    static var production: Self {
        Self(
            homeURL: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            applicationSupportURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        )
    }
}

struct ProvisioningShellPersistence {
    enum WriteOperation {
        case backup
        case target
        case receipt
    }

    typealias FailureInjector = (WriteOperation, URL) -> Error?

    enum PathKind {
        case missing
        case regular(mode: mode_t)
        case directory
        case symlink
        case other
    }

    struct FileSnapshot {
        let data: Data
        let text: String
        let mode: mode_t
    }

    struct Record: Codable {
        var version: Int
        var targetPath: String
        var backupPath: String
        var originalFileExisted: Bool
        var originalMode: UInt16
        var leadingSeparatorAdded: Bool
        var managedBlock: String
        // Optional so metadata written before this receipt remains readable.
        // nil means a legacy record whose missing block needs explicit Restore acknowledgement.
        var restored: Bool?
    }

    let location: ProvisioningShellLocation
    let failureInjector: FailureInjector?
    private let metadataFileName = ".provisioning-shell-configuration.json"
    private let metadataVersion = 1
    private let generationBackupPrefix = ".zshrc.dev-manager.backup."
    private let maximumFileSize: off_t = 4 * 1024 * 1024

    init(location: ProvisioningShellLocation, failureInjector: FailureInjector? = nil) {
        self.location = location
        self.failureInjector = failureInjector
    }

    var targetURL: URL { location.homeURL.appendingPathComponent(ProvisioningShellConfiguration.targetFileName) }
    var legacyBackupURL: URL { location.homeURL.appendingPathComponent(ProvisioningShellConfiguration.backupFileName) }
    var metadataDirectoryURL: URL { location.applicationSupportURL.appendingPathComponent("Dev Manager", isDirectory: true) }
    var metadataURL: URL { metadataDirectoryURL.appendingPathComponent(metadataFileName) }

    func generationBackupURL() -> URL {
        metadataDirectoryURL.appendingPathComponent("\(generationBackupPrefix)\(UUID().uuidString)")
    }

    func validateRecordPaths(_ record: Record) throws {
        guard record.targetPath == targetURL.path,
              isSupportedBackupPath(record.backupPath) else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the recorded target or backup path is not a supported Dev Manager shell location")
        }
        guard record.version == metadataVersion else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the recorded metadata version is unsupported")
        }
    }

    func isSupportedBackupPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path else { return false }
        if path == legacyBackupURL.path { return true }
        guard url.deletingLastPathComponent().path == metadataDirectoryURL.path,
              url.lastPathComponent.hasPrefix(generationBackupPrefix) else {
            return false
        }
        let suffix = String(url.lastPathComponent.dropFirst(generationBackupPrefix.count))
        return UUID(uuidString: suffix) != nil
    }

    func resolvedExecutablePath(from url: URL) throws -> String {
        guard url.path.hasPrefix("/") else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsupported("fnm did not provide an absolute executable path")
        }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsupported("the detected fnm executable could not be resolved safely")
        }
        let path = String(cString: buffer)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsupported("the detected fnm executable is not executable")
        }
        return path
    }

    func readOptionalRecord() throws -> Record? {
        switch try pathKind(at: metadataURL) {
        case .missing: return nil
        case .regular: return try readRecord()
        case .symlink, .directory, .other: throw ProvisioningShellConfiguration.ConfigurationError.unsafePath(metadataURL.path)
        }
    }

    func readRecord() throws -> Record {
        let snapshot = try readRegularFile(at: metadataURL)
        do {
            let record = try JSONDecoder().decode(Record.self, from: snapshot.data)
            guard record.version == metadataVersion else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("the recorded metadata version is unsupported")
            }
            return record
        } catch let error as ProvisioningShellConfiguration.ConfigurationError {
            throw error
        } catch {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the recorded shell metadata is invalid")
        }
    }

    func writeRecord(_ record: Record) throws {
        try ensureMetadataDirectory()
        let data = try JSONEncoder().encode(record)
        try writeAtomically(data, to: metadataURL, mode: 0o600, operation: .receipt)
    }

    func ensureMetadataDirectory() throws {
        let support = metadataURL.deletingLastPathComponent().deletingLastPathComponent()
        let container = metadataURL.deletingLastPathComponent()
        for directory in [support, container] {
            switch try pathKind(at: directory) {
            case .directory: continue
            case .missing:
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                guard case .directory = try pathKind(at: directory) else {
                    throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(directory.path, "the metadata directory was not created as a directory")
                }
            case .symlink, .regular, .other:
                throw ProvisioningShellConfiguration.ConfigurationError.unsafePath(directory.path)
            }
        }
    }

    func validateBackup(for record: Record) throws {
        let backupURL = URL(fileURLWithPath: record.backupPath)
        switch try pathKind(at: backupURL) {
        case .regular:
            guard record.originalFileExisted else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("an unexpected backup exists for a configuration that originally had no ~/.zshrc")
            }
        case .missing:
            guard !record.originalFileExisted else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("the recorded ~/.zshrc backup is missing")
            }
        case .symlink, .directory, .other:
            throw ProvisioningShellConfiguration.ConfigurationError.unsafePath(backupURL.path)
        }
    }

    func readOptionalRegularFile(at url: URL) throws -> FileSnapshot? {
        switch try pathKind(at: url) {
        case .missing: return nil
        case .regular: return try readRegularFile(at: url)
        case .symlink, .directory, .other: throw ProvisioningShellConfiguration.ConfigurationError.unsafePath(url.path)
        }
    }

    func pathKind(at url: URL) throws -> PathKind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw ProvisioningShellConfiguration.ConfigurationError.readFailed(url.path, String(cString: strerror(errno)))
            }
            return .missing
        }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .regular(mode: info.st_mode & 0o7777)
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    func readRegularFile(at url: URL) throws -> FileSnapshot {
        let kind = try pathKind(at: url)
        guard case let .regular(mode) = kind else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsafePath(url.path)
        }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw ProvisioningShellConfiguration.ConfigurationError.readFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw ProvisioningShellConfiguration.ConfigurationError.readFailed(url.path, "the file changed type during inspection")
        }
        guard info.st_size <= maximumFileSize else {
            throw ProvisioningShellConfiguration.ConfigurationError.readFailed(url.path, "the file is larger than the supported safety limit")
        }
        var data = Data()
        while data.count < Int(info.st_size) {
            var buffer = [UInt8](repeating: 0, count: min(64 * 1024, Int(info.st_size) - data.count))
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return Darwin.read(descriptor, baseAddress, bytes.count)
            }
            guard count > 0 else {
                throw ProvisioningShellConfiguration.ConfigurationError.readFailed(url.path, count == 0 ? "unexpected end of file" : String(cString: strerror(errno)))
            }
            data.append(contentsOf: buffer[0..<count])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("\(url.path) is not valid UTF-8; it was left unchanged")
        }
        return FileSnapshot(data: data, text: text, mode: mode)
    }

    func writeAtomically(_ data: Data, to url: URL, mode: mode_t, metadataSource: URL? = nil, operation: WriteOperation = .target) throws {
        if let failure = failureInjector?(operation, url) { throw failure }
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).dev-manager-\(UUID().uuidString).tmp")
        guard case .missing = try pathKind(at: temporary) else {
            throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, "the temporary path already exists")
        }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        var succeeded = false
        defer {
            close(descriptor)
            if !succeeded { _ = unlink(temporary.path) }
        }
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return Darwin.write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
            }
            guard written > 0 else {
                throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
            }
            offset += written
        }

        if let metadataSource {
            guard copyfile(metadataSource.path, temporary.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)) == 0 else {
                throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, "could not preserve the source file's ownership, ACL, extended attributes, or flags: \(String(cString: strerror(errno)))")
            }
        } else {
            guard fchmod(descriptor, mode) == 0 else {
                throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
            }
        }
        guard fsync(descriptor) == 0 else {
            throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        guard rename(temporary.path, url.path) == 0 else {
            throw ProvisioningShellConfiguration.ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        succeeded = true
    }
}
