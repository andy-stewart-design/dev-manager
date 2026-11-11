#if DEBUG
import Darwin
import Foundation

/// The deliberately small, DEBUG-only shell experiment. It owns one marked block
/// in the current user's ~/.zshrc and never reads or edits ~/.zprofile.
enum ProvisioningShellConfiguration {
    static let targetFileName = ".zshrc"
    static let backupFileName = ".zshrc.dev-manager.backup"
    private static let metadataFileName = ".provisioning-shell-configuration.json"
    private static let metadataVersion = 1
    private static let generationBackupPrefix = ".zshrc.dev-manager.backup."
    private static let maximumFileSize: off_t = 4 * 1024 * 1024

    enum Inspection: Sendable {
        case configured(String)
        case notConfigured(String)
        case conflict(String)

        var message: String {
            switch self {
            case let .configured(message), let .notConfigured(message), let .conflict(message):
                return message
            }
        }

        var isConfigured: Bool {
            if case .configured = self { return true }
            return false
        }
    }

    enum ConfigurationError: LocalizedError, Sendable {
        case unsupported(String)
        case conflict(String)
        case unsafePath(String)
        case readFailed(String, String)
        case writeFailed(String, String)

        var errorDescription: String? {
            switch self {
            case let .unsupported(message): return "Shell configuration is unavailable: \(message)"
            case let .conflict(message): return "Shell configuration was left unchanged: \(message)"
            case let .unsafePath(path): return "Shell configuration was left unchanged because this path is unsafe or is a symlink: \(path)"
            case let .readFailed(path, detail): return "Could not safely read \(path): \(detail)"
            case let .writeFailed(path, detail): return "Could not safely update \(path): \(detail)"
            }
        }
    }

    private enum PathKind {
        case missing
        case regular(mode: mode_t)
        case directory
        case symlink
        case other
    }

    private struct FileSnapshot {
        let data: Data
        let text: String
        let mode: mode_t
    }

    private struct Record: Codable {
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

    private static var homeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static var targetURL: URL {
        homeURL.appendingPathComponent(targetFileName)
    }

    private static var legacyBackupURL: URL {
        homeURL.appendingPathComponent(backupFileName)
    }

    private static var metadataDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dev Manager", isDirectory: true)
    }

    private static var metadataURL: URL {
        metadataDirectoryURL.appendingPathComponent(metadataFileName)
    }

    private static func generationBackupURL() -> URL {
        metadataDirectoryURL.appendingPathComponent("\(generationBackupPrefix)\(UUID().uuidString)")
    }

    private static var startMarker: String {
        "# >>> Dev Manager managed fnm initialization >>>"
    }

    private static var endMarker: String {
        "# <<< Dev Manager managed fnm initialization <<<"
    }

    static func hasRecordedConfiguration() -> Bool {
        (try? readOptionalRecord()) != nil
    }

    static func inspect() -> Inspection {
        do {
            let metadataKind = try pathKind(at: metadataURL)
            guard case .regular = metadataKind else {
                if case .missing = metadataKind {
                    return .notConfigured("No Dev Manager shell configuration is recorded. The optional ~/.zshrc change has not been made.")
                }
                throw ConfigurationError.unsafePath(metadataURL.path)
            }

            let record = try readRecord()
            try validateRecordPaths(record)
            try validateBackup(for: record)
            let snapshot = try readOptionalRegularFile(at: targetURL)
            guard let snapshot else {
                guard !record.originalFileExisted else {
                    throw ConfigurationError.conflict("the recorded ~/.zshrc is missing; it was left unchanged")
                }
                guard record.restored == true else {
                    return .conflict("the recorded app-owned block is missing; press Restore once to acknowledge that it is intentionally absent, then Configure again")
                }
                return .notConfigured("The app-owned fnm block is restored. ~/.zshrc is not currently configured by Dev Manager.")
            }

            if containsAnyMarker(in: snapshot.text) {
                let block = try managedBlock(from: snapshot.text)
                guard isCanonicalManagedBlock(block), block == record.managedBlock else {
                    throw ConfigurationError.conflict("the app-owned fnm block was changed; it will not be rewritten")
                }
                guard countOccurrences(of: block, in: snapshot.text) == 1 else {
                    throw ConfigurationError.conflict("the app-owned fnm block is duplicated or malformed")
                }
                return .configured("The app-owned fnm block is present in ~/.zshrc. It is available to future interactive Zsh sessions; it is not required by the app's fixture.")
            }

            guard record.restored == true else {
                return .conflict("the recorded app-owned block is missing; press Restore once to acknowledge that it is intentionally absent, then Configure again")
            }
            return .notConfigured("The app-owned fnm block is restored or already absent. ~/.zshrc is not currently configured by Dev Manager.")
        } catch let error as ConfigurationError {
            return .conflict(error.localizedDescription)
        } catch {
            return .conflict(error.localizedDescription)
        }
    }

    static func configure(using fnmURL: URL, nodeVersion: String) throws -> String {
        let fnmPath = try resolvedExecutablePath(from: fnmURL)
        let block = makeManagedBlock(fnmPath: fnmPath, nodeVersion: nodeVersion)
        let existingRecord = try readOptionalRecord()

        if let existingRecord {
            try validateRecordPaths(existingRecord)
            try validateBackup(for: existingRecord)
        }

        let targetSnapshot = try readOptionalRegularFile(at: targetURL)
        if let existingRecord {
            if let targetSnapshot, containsAnyMarker(in: targetSnapshot.text) {
                try validateOwnedBlock(in: targetSnapshot.text, expected: existingRecord.managedBlock)
                guard existingRecord.managedBlock == block else {
                    throw ConfigurationError.conflict("the detected fnm executable differs from the owned block; it will not be rewritten")
                }
                let unrelatedText = targetSnapshot.text.replacingOccurrences(of: existingRecord.managedBlock, with: "")
                guard !hasEquivalentFNMInitialization(in: unrelatedText) else {
                    throw ConfigurationError.conflict("an additional fnm-related shell configuration was detected; it was not changed or duplicated")
                }
                return "The existing app-owned ~/.zshrc block is unchanged; no duplicate initialization was added."
            }

            if let targetSnapshot, hasEquivalentFNMInitialization(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("an existing fnm-related shell configuration was detected; it was not duplicated or changed")
            }

            guard existingRecord.restored == true else {
                throw ConfigurationError.conflict("the recorded app-owned block is missing and ~/.zshrc may have been changed; press Restore once to acknowledge that the block is intentionally absent, then Configure again")
            }
        } else if let targetSnapshot {
            if containsAnyMarker(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("a managed marker already exists but is not an unchanged, recorded app-owned block")
            }
            if hasEquivalentFNMInitialization(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("an existing fnm-related shell configuration was detected; it was not duplicated or changed")
            }
        }

        let originalFileExisted = targetSnapshot != nil
        let originalMode = targetSnapshot?.mode ?? 0o600
        let leadingSeparatorAdded = targetSnapshot.map { !$0.text.isEmpty && !$0.text.hasSuffix("\n") } ?? false
        if existingRecord == nil {
            switch try pathKind(at: legacyBackupURL) {
            case .missing: break
            case .regular: throw ConfigurationError.conflict("a legacy backup exists but its ownership record is unavailable; it was not overwritten")
            case .symlink, .directory, .other: throw ConfigurationError.unsafePath(legacyBackupURL.path)
            }
        }
        let startsNewCycle = existingRecord == nil || existingRecord?.restored == true
        let backupURL: URL
        if startsNewCycle {
            backupURL = generationBackupURL()
            if originalFileExisted {
                try ensureMetadataDirectory()
                guard case .missing = try pathKind(at: backupURL) else {
                    throw ConfigurationError.conflict("the new shell backup path is already occupied")
                }
            }
        } else {
            guard let existingRecord else {
                throw ConfigurationError.conflict("the shell ownership record is unavailable")
            }
            backupURL = URL(fileURLWithPath: existingRecord.backupPath)
        }

        let backupKind = try pathKind(at: backupURL)
        if startsNewCycle {
            guard case .missing = backupKind else {
                throw ConfigurationError.conflict("the new shell backup path is already occupied")
            }
        } else if let existingRecord {
            guard existingRecord.originalFileExisted == originalFileExisted else {
                throw ConfigurationError.conflict("the recorded original ~/.zshrc presence does not match the current shell file")
            }
            if existingRecord.originalFileExisted {
                guard case .regular = backupKind else {
                    throw ConfigurationError.conflict("the recorded backup is unavailable")
                }
                _ = try readRegularFile(at: backupURL)
            } else {
                guard case .missing = backupKind else {
                    throw ConfigurationError.conflict("an unexpected backup exists for an originally absent ~/.zshrc")
                }
            }
        }

        let recheckedTarget = try readOptionalRegularFile(at: targetURL)
        guard recheckedTarget?.data == targetSnapshot?.data,
              recheckedTarget?.mode == targetSnapshot?.mode else {
            throw ConfigurationError.conflict("~/.zshrc changed during the safety check; no file was edited")
        }

        var createdBackup = false
        if let targetSnapshot, case .missing = backupKind {
            try writeAtomically(targetSnapshot.data, to: backupURL, mode: targetSnapshot.mode, metadataSource: targetURL)
            createdBackup = true
        }

        // Establish ownership before replacing ~/.zshrc. If the target write
        // fails, Restore can safely acknowledge the attempt before retrying.
        let record = Record(
            version: metadataVersion,
            targetPath: targetURL.path,
            backupPath: backupURL.path,
            originalFileExisted: originalFileExisted,
            originalMode: UInt16(originalMode & 0o7777),
            leadingSeparatorAdded: leadingSeparatorAdded,
            managedBlock: block,
            restored: false
        )
        do {
            try writeRecord(record)
        } catch {
            if createdBackup { _ = unlink(backupURL.path) }
            throw error
        }

        let currentText = targetSnapshot?.text ?? ""
        let updatedText = currentText + (leadingSeparatorAdded ? "\n" : "") + block
        do {
            try writeAtomically(Data(updatedText.utf8), to: targetURL, mode: originalMode, metadataSource: targetSnapshot == nil ? nil : targetURL)
        } catch {
            throw ConfigurationError.writeFailed(targetURL.path, "\(error.localizedDescription) Ownership metadata was retained. Press Restore to acknowledge this incomplete attempt, then retry Configure.")
        }
        return "Configured only ~/.zshrc with one marked fnm block. Future interactive Zsh sessions will select Node \(nodeVersion) when that installed version is available; the app fixture does not depend on this change."
    }

    static func restore() throws -> String {
        guard let record = try readOptionalRecord() else {
            return "No app-owned shell configuration is recorded; nothing was changed."
        }
        try validateRecordPaths(record)
        try validateBackup(for: record)

        guard let snapshot = try readOptionalRegularFile(at: targetURL) else {
            guard !record.originalFileExisted else {
                throw ConfigurationError.conflict("the recorded ~/.zshrc is missing; it was left unchanged")
            }
            guard record.restored != true else {
                return "The app-owned fnm block is already restored; no shell file was changed."
            }
            var updatedRecord = record
            updatedRecord.restored = true
            try writeRecord(updatedRecord)
            return "The app-owned fnm block was already absent; the restore receipt was recorded and no shell file was changed."
        }

        guard containsAnyMarker(in: snapshot.text) else {
            let rechecked = try readRegularFile(at: targetURL)
            guard rechecked.data == snapshot.data,
                  rechecked.mode == snapshot.mode else {
                throw ConfigurationError.conflict("~/.zshrc changed during restore; no file was edited")
            }
            guard record.restored != true else {
                return "The app-owned fnm block is already restored or absent; no shell file was changed."
            }
            // This explicit Restore action acknowledges a missing block in a
            // legacy/current cycle without touching the user's baseline.
            var updatedRecord = record
            updatedRecord.restored = true
            try writeRecord(updatedRecord)
            return "The app-owned fnm block was already absent; the restore receipt was recorded and ~/.zshrc was left unchanged. Configure can now start a new safe cycle."
        }

        let block = try managedBlock(from: snapshot.text)
        guard isCanonicalManagedBlock(block), block == record.managedBlock else {
            throw ConfigurationError.conflict("the app-owned fnm block was changed; it was not rewritten or removed")
        }
        guard countOccurrences(of: block, in: snapshot.text) == 1 else {
            throw ConfigurationError.conflict("the app-owned fnm block is duplicated; the file was left unchanged")
        }

        var restoredText = snapshot.text.replacingOccurrences(of: block, with: "")
        if record.leadingSeparatorAdded,
           record.originalFileExisted,
           let blockRange = snapshot.text.range(of: block),
           blockRange.lowerBound > snapshot.text.startIndex {
            let preceding = snapshot.text.index(before: blockRange.lowerBound)
            let prefix = String(snapshot.text[..<blockRange.lowerBound])
            let originalText = try readRegularFile(at: URL(fileURLWithPath: record.backupPath)).text
            // Remove the separator only when the whole file still has the
            // exact original-plus-separator prefix and the block remains at
            // EOF. Any inserted or changed user text leaves the harmless
            // newline intact rather than joining user lines together.
            if snapshot.text[preceding] == "\n",
               blockRange.upperBound == snapshot.text.endIndex,
               prefix == originalText + "\n" {
                let restoredBlockStart = restoredText.index(restoredText.startIndex, offsetBy: snapshot.text.distance(from: snapshot.text.startIndex, to: preceding))
                restoredText.remove(at: restoredBlockStart)
            }
        }

        let rechecked = try readRegularFile(at: targetURL)
        guard rechecked.data == snapshot.data,
              rechecked.mode == snapshot.mode else {
            throw ConfigurationError.conflict("~/.zshrc changed during restore; no file was edited")
        }

        if !record.originalFileExisted && restoredText.isEmpty {
            guard unlink(targetURL.path) == 0 else {
                throw ConfigurationError.writeFailed(targetURL.path, String(cString: strerror(errno)))
            }
        } else {
            try writeAtomically(Data(restoredText.utf8), to: targetURL, mode: snapshot.mode, metadataSource: targetURL)
        }

        // The target has been restored before this receipt is written. If the
        // metadata write fails, a retry sees the absent block and only records
        // this receipt; it does not touch the user's target again.
        var updatedRecord = record
        updatedRecord.restored = true
        try writeRecord(updatedRecord)
        return "Removed only the app-owned fnm block from ~/.zshrc. Unrelated content and permissions were preserved; the restore receipt was recorded and the backup remains available for inspection."
    }

    private static func makeManagedBlock(fnmPath: String, nodeVersion: String) -> String {
        let fnmDirectory = URL(fileURLWithPath: fnmPath).deletingLastPathComponent().path
        return """
        \(startMarker)
        export PATH=\(shellQuote(fnmDirectory)):$PATH
        eval "$(\(shellQuote(fnmPath)) env --use-on-cd --shell zsh)"
        # Dev Manager selects the pinned runtime for this shell; no install or network action is requested.
        if command -v fnm >/dev/null 2>&1; then
          fnm use \(shellQuote(nodeVersion)) >/dev/null 2>&1
        fi
        \(endMarker)
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isCanonicalManagedBlock(_ block: String) -> Bool {
        let lines = block.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count == 8,
              lines[0] == startMarker,
              lines[1].hasPrefix("export PATH='") && lines[1].hasSuffix("':$PATH"),
              lines[2].hasPrefix("eval \"$('"),
              lines[2].hasSuffix("' env --use-on-cd --shell zsh)\""),
              lines[3] == "# Dev Manager selects the pinned runtime for this shell; no install or network action is requested.",
              lines[4] == "if command -v fnm >/dev/null 2>&1; then",
              lines[5].hasPrefix("  fnm use '") && lines[5].hasSuffix("' >/dev/null 2>&1"),
              lines[6] == "fi",
              lines[7] == endMarker else { return false }
        let pathPrefix = "export PATH='"
        let pathSuffix = "':$PATH"
        let path = String(lines[1].dropFirst(pathPrefix.count).dropLast(pathSuffix.count))
        guard path.hasPrefix("/"), !path.contains("\n") else { return false }
        let evalPrefix = "eval \"$('"
        let evalSuffix = "' env --use-on-cd --shell zsh)\""
        guard lines[2].hasPrefix(evalPrefix), lines[2].hasSuffix(evalSuffix) else { return false }
        let evalPath = String(lines[2].dropFirst(evalPrefix.count).dropLast(evalSuffix.count))
        return evalPath.hasPrefix("/") && !evalPath.contains("\n")
    }

    private static func managedBlock(from text: String) throws -> String {
        guard countOccurrences(of: startMarker, in: text) == 1,
              countOccurrences(of: endMarker, in: text) == 1,
              let start = text.range(of: startMarker),
              let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex) else {
            throw ConfigurationError.conflict("the app-owned fnm block is missing or malformed")
        }

        let startsAtLineBoundary = start.lowerBound == text.startIndex
            || text[..<start.lowerBound].utf8.last == 0x0A
        // Inspect bytes because Swift treats CRLF as a single Character.
        let followingBytes = text[end.upperBound...].utf8
        let endsAtLineBoundary = followingBytes.isEmpty
            || followingBytes.first == 0x0A
            || followingBytes.starts(with: [0x0D, 0x0A])
        guard startsAtLineBoundary, endsAtLineBoundary else {
            throw ConfigurationError.conflict("the app-owned fnm block is missing or malformed")
        }

        let block = String(text[start.lowerBound..<end.upperBound])
        guard !text[start.upperBound...].contains(startMarker), !text[..<start.lowerBound].contains(endMarker) else {
            throw ConfigurationError.conflict("managed fnm markers are duplicated or out of order")
        }
        return block
    }

    private static func validateOwnedBlock(in text: String, expected: String) throws {
        guard let found = try? managedBlock(from: text) else {
            throw ConfigurationError.conflict("the app-owned fnm block is missing or malformed; it will not be rewritten")
        }
        guard found == expected else {
            throw ConfigurationError.conflict("the app-owned fnm block was changed; it will not be rewritten")
        }
        guard countOccurrences(of: found, in: text) == 1 else {
            throw ConfigurationError.conflict("the app-owned fnm block is duplicated; it will not be rewritten")
        }
    }

    private static func containsAnyMarker(in text: String) -> Bool {
        text.contains(startMarker) || text.contains(endMarker)
    }

    private static func hasEquivalentFNMInitialization(in text: String) -> Bool {
        let nonCommentLines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }
        // Joining lines conservatively catches split references such as `f\\` / `nm`.
        let joined = nonCommentLines.joined()
        return joined.lowercased().contains("fnm")
    }

    private static func validateRecordPaths(_ record: Record) throws {
        guard record.targetPath == targetURL.path,
              isSupportedBackupPath(record.backupPath) else {
            throw ConfigurationError.conflict("the recorded target or backup path is not a supported Dev Manager shell location")
        }
        guard record.version == metadataVersion else {
            throw ConfigurationError.conflict("the recorded metadata version is unsupported")
        }
    }

    private static func isSupportedBackupPath(_ path: String) -> Bool {
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

    private static func countOccurrences(of value: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: value, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func resolvedExecutablePath(from url: URL) throws -> String {
        guard url.path.hasPrefix("/") else {
            throw ConfigurationError.unsupported("fnm did not provide an absolute executable path")
        }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else {
            throw ConfigurationError.unsupported("the detected fnm executable could not be resolved safely")
        }
        let path = String(cString: buffer)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw ConfigurationError.unsupported("the detected fnm executable is not executable")
        }
        return path
    }

    private static func readOptionalRecord() throws -> Record? {
        switch try pathKind(at: metadataURL) {
        case .missing: return nil
        case .regular: return try readRecord()
        case .symlink, .directory, .other: throw ConfigurationError.unsafePath(metadataURL.path)
        }
    }

    private static func readRecord() throws -> Record {
        let snapshot = try readRegularFile(at: metadataURL)
        do {
            let record = try JSONDecoder().decode(Record.self, from: snapshot.data)
            guard record.version == metadataVersion else {
                throw ConfigurationError.conflict("the recorded metadata version is unsupported")
            }
            return record
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.conflict("the recorded shell metadata is invalid")
        }
    }

    private static func writeRecord(_ record: Record) throws {
        try ensureMetadataDirectory()
        let data = try JSONEncoder().encode(record)
        try writeAtomically(data, to: metadataURL, mode: 0o600)
    }

    private static func ensureMetadataDirectory() throws {
        let support = metadataURL.deletingLastPathComponent().deletingLastPathComponent()
        let container = metadataURL.deletingLastPathComponent()
        for directory in [support, container] {
            switch try pathKind(at: directory) {
            case .directory: continue
            case .missing:
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                guard case .directory = try pathKind(at: directory) else {
                    throw ConfigurationError.writeFailed(directory.path, "the metadata directory was not created as a directory")
                }
            case .symlink, .regular, .other:
                throw ConfigurationError.unsafePath(directory.path)
            }
        }
    }

    private static func validateBackup(for record: Record) throws {
        let backupURL = URL(fileURLWithPath: record.backupPath)
        switch try pathKind(at: backupURL) {
        case .regular:
            guard record.originalFileExisted else {
                throw ConfigurationError.conflict("an unexpected backup exists for a configuration that originally had no ~/.zshrc")
            }
        case .missing:
            guard !record.originalFileExisted else {
                throw ConfigurationError.conflict("the recorded ~/.zshrc backup is missing")
            }
        case .symlink, .directory, .other:
            throw ConfigurationError.unsafePath(backupURL.path)
        }
    }

    private static func readOptionalRegularFile(at url: URL) throws -> FileSnapshot? {
        switch try pathKind(at: url) {
        case .missing: return nil
        case .regular: return try readRegularFile(at: url)
        case .symlink, .directory, .other: throw ConfigurationError.unsafePath(url.path)
        }
    }

    private static func pathKind(at url: URL) throws -> PathKind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw ConfigurationError.readFailed(url.path, String(cString: strerror(errno)))
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

    private static func readRegularFile(at url: URL) throws -> FileSnapshot {
        let kind = try pathKind(at: url)
        guard case let .regular(mode) = kind else {
            throw ConfigurationError.unsafePath(url.path)
        }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw ConfigurationError.readFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw ConfigurationError.readFailed(url.path, "the file changed type during inspection")
        }
        guard info.st_size <= maximumFileSize else {
            throw ConfigurationError.readFailed(url.path, "the file is larger than the supported safety limit")
        }
        var data = Data()
        while data.count < Int(info.st_size) {
            var buffer = [UInt8](repeating: 0, count: min(64 * 1024, Int(info.st_size) - data.count))
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return Darwin.read(descriptor, baseAddress, bytes.count)
            }
            guard count > 0 else {
                throw ConfigurationError.readFailed(url.path, count == 0 ? "unexpected end of file" : String(cString: strerror(errno)))
            }
            data.append(contentsOf: buffer[0..<count])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.conflict("\(url.path) is not valid UTF-8; it was left unchanged")
        }
        return FileSnapshot(data: data, text: text, mode: mode)
    }

    private static func writeAtomically(_ data: Data, to url: URL, mode: mode_t, metadataSource: URL? = nil) throws {
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).dev-manager-\(UUID().uuidString).tmp")
        guard case .missing = try pathKind(at: temporary) else {
            throw ConfigurationError.writeFailed(url.path, "the temporary path already exists")
        }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
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
                throw ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
            }
            offset += written
        }

        if let metadataSource {
            guard copyfile(metadataSource.path, temporary.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW)) == 0 else {
                throw ConfigurationError.writeFailed(url.path, "could not preserve the source file's ownership, ACL, extended attributes, or flags: \(String(cString: strerror(errno)))")
            }
        } else {
            guard fchmod(descriptor, mode) == 0 else {
                throw ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
            }
        }
        guard fsync(descriptor) == 0 else {
            throw ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        guard rename(temporary.path, url.path) == 0 else {
            throw ConfigurationError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        succeeded = true
    }
}
#endif
