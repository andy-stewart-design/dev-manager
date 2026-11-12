#if DEBUG
import Darwin
import Foundation

/// App-owned, bounded diagnostics for runtime installation commands. This helper never
/// records environment values or credentials and does not invoke a process logger.
nonisolated enum ProvisioningInstallationLog {
    nonisolated enum AppendResult: Sendable {
        case wrote(URL)
        case failed(String)
    }

    private nonisolated static let maximumBytes = 256 * 1024
    private nonisolated static let maximumStreamBytes = 12_000
    private nonisolated static let logFileName = "provisioning.log"
    private nonisolated static let rotatedLogFileName = "provisioning.log.1"

    nonisolated static var logURL: URL {
        logsDirectoryURL.appendingPathComponent(logFileName)
    }

    nonisolated static func existingLogURL() -> URL? {
        do {
            try validateDirectory(at: logsDirectoryURL)
            guard case .regular = try pathKind(at: logURL) else { return nil }
            let data = try readRegularFile(at: logURL)
            guard String(data: data, encoding: .utf8) != nil else { return nil }
            return logURL
        } catch {
            return nil
        }
    }

    nonisolated static func append(
        commandLabel: String,
        result: ProvisioningProcessResult,
        timestamp: Date = Date()
    ) -> AppendResult {
        do {
            try ensureDirectories()
            let current = try readOptionalRegularFile(at: logURL) ?? Data()
            if !current.isEmpty, String(data: current, encoding: .utf8) == nil {
                throw LogError.readFailed(logURL.path, "the existing log is not valid UTF-8")
            }
            let record = Data(formatRecord(commandLabel: commandLabel, result: result, timestamp: timestamp).utf8)
            var combined = current
            combined.append(record)
            let didRotate = combined.count > maximumBytes
            let bounded = didRotate ? Data(combined.suffix(maximumBytes)) : combined

            if didRotate, !current.isEmpty {
                try rotateCurrentLog()
            }
            try writeAtomically(bounded, to: logURL)
            guard let validatedURL = existingLogURL() else {
                return .failed("the written file could not be validated as a regular UTF-8 log")
            }
            return .wrote(validatedURL)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private nonisolated static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private nonisolated static var appDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Dev Manager", isDirectory: true)
    }

    private nonisolated static var logsDirectoryURL: URL {
        appDirectoryURL.appendingPathComponent("Logs", isDirectory: true)
    }

    private nonisolated static func formatRecord(
        commandLabel: String,
        result: ProvisioningProcessResult,
        timestamp: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let status: String
        if result.timedOut {
            status = "timeout (exit status \(result.terminationStatus))"
        } else {
            status = "exit status \(result.terminationStatus)"
        }
        return """
        [\(formatter.string(from: timestamp))] command: \(commandLabel)
        status: \(status)
        stdout:
        \(boundedTail(result.stdout))
        stderr:
        \(boundedTail(result.stderr))

        """
    }

    private nonisolated static func boundedTail(_ text: String) -> String {
        guard text.utf8.count > maximumStreamBytes else { return text }
        return String(decoding: Array(text.utf8.suffix(maximumStreamBytes)), as: UTF8.self)
    }

    nonisolated private enum PathKind {
        case missing
        case regular
        case directory
        case symlink
        case other
    }

    private nonisolated static func ensureDirectories() throws {
        try ensureDirectory(at: applicationSupportURL, mode: 0o700)
        try ensureDirectory(at: appDirectoryURL, mode: 0o700)
        try ensureDirectory(at: logsDirectoryURL, mode: 0o700)
    }

    private nonisolated static func validateDirectory(at url: URL) throws {
        guard case .directory = try pathKind(at: url) else {
            throw LogError.unsafePath(url.path)
        }
    }

    private nonisolated static func ensureDirectory(at url: URL, mode: mode_t) throws {
        switch try pathKind(at: url) {
        case .directory:
            return
        case .missing:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            guard chmod(url.path, mode) == 0 else {
                throw LogError.writeFailed(url.path, String(cString: strerror(errno)))
            }
            guard case .directory = try pathKind(at: url) else {
                throw LogError.unsafePath(url.path)
            }
        case .regular, .symlink, .other:
            throw LogError.unsafePath(url.path)
        }
    }

    private nonisolated static func rotateCurrentLog() throws {
        let rotatedURL = logsDirectoryURL.appendingPathComponent(rotatedLogFileName)
        try validateExistingLog(at: logURL)
        switch try pathKind(at: rotatedURL) {
        case .missing:
            break
        case .regular:
            let previous = try readRegularFile(at: rotatedURL)
            guard String(data: previous, encoding: .utf8) != nil else {
                throw LogError.readFailed(rotatedURL.path, "the log is not valid UTF-8")
            }
        case .directory, .symlink, .other:
            throw LogError.unsafePath(rotatedURL.path)
        }

        // POSIX rename atomically replaces a valid previous file. Do not unlink it
        // first: if this fails, the previous backup must remain available.
        guard rename(logURL.path, rotatedURL.path) == 0 else {
            throw LogError.writeFailed(logURL.path, String(cString: strerror(errno)))
        }
    }

    private nonisolated static func readOptionalRegularFile(at url: URL) throws -> Data? {
        switch try pathKind(at: url) {
        case .missing:
            return nil
        case .regular:
            return try readRegularFile(at: url)
        case .directory, .symlink, .other:
            throw LogError.unsafePath(url.path)
        }
    }

    private nonisolated static func readRegularFile(at url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw LogError.readFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }

        let info = try validatedLogMetadata(for: descriptor, at: url)
        guard info.st_size <= off_t(maximumBytes) else {
            throw LogError.readFailed(url.path, "the log exceeds its bounded size")
        }

        var data = Data()
        while data.count < Int(info.st_size) {
            var buffer = [UInt8](repeating: 0, count: min(64 * 1024, Int(info.st_size) - data.count))
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return Darwin.read(descriptor, baseAddress, bytes.count)
            }
            guard count > 0 else {
                throw LogError.readFailed(url.path, count == 0 ? "unexpected end of file" : String(cString: strerror(errno)))
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    private nonisolated static func pathKind(at url: URL) throws -> PathKind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw LogError.readFailed(url.path, String(cString: strerror(errno)))
            }
            return .missing
        }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    private nonisolated static func validateExistingLog(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw LogError.readFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        let info = try validatedLogMetadata(for: descriptor, at: url)
        guard info.st_size <= off_t(maximumBytes) else {
            throw LogError.readFailed(url.path, "the log exceeds its bounded size")
        }
    }

    private nonisolated static func validatedLogMetadata(for descriptor: Int32, at url: URL) throws -> stat {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw LogError.readFailed(url.path, String(cString: strerror(errno)))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw LogError.unsafePath(url.path)
        }
        guard info.st_nlink == 1 else {
            throw LogError.unsafePath(url.path)
        }
        guard info.st_uid == geteuid() else {
            throw LogError.unsafePath(url.path)
        }
        guard (info.st_mode & 0o7777) == 0o600 else {
            throw LogError.unsafePath(url.path)
        }
        return info
    }

    private nonisolated static func writeAtomically(_ data: Data, to url: URL) throws {
        let temporary = logsDirectoryURL.appendingPathComponent(".\(url.lastPathComponent).dev-manager-\(UUID().uuidString).tmp")
        guard case .missing = try pathKind(at: temporary) else {
            throw LogError.writeFailed(url.path, "the temporary path is already occupied")
        }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw LogError.writeFailed(url.path, String(cString: strerror(errno)))
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
                throw LogError.writeFailed(url.path, String(cString: strerror(errno)))
            }
            offset += written
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0, fsync(descriptor) == 0 else {
            throw LogError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        switch try pathKind(at: url) {
        case .missing:
            break
        case .regular:
            try validateExistingLog(at: url)
        case .directory, .symlink, .other:
            throw LogError.unsafePath(url.path)
        }
        guard rename(temporary.path, url.path) == 0 else {
            throw LogError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        succeeded = true
    }

    nonisolated private enum LogError: LocalizedError {
        case unsafePath(String)
        case readFailed(String, String)
        case writeFailed(String, String)

        nonisolated var errorDescription: String? {
            switch self {
            case let .unsafePath(path): return "unsafe app-owned log path: \(path)"
            case let .readFailed(path, detail): return "could not read \(path): \(detail)"
            case let .writeFailed(path, detail): return "could not write \(path): \(detail)"
            }
        }
    }
}
#endif
