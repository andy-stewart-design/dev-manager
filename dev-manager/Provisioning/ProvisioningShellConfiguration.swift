import Darwin
import Foundation

/// The deliberately small optional shell configuration. It owns one marked block
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
        case configuredExternally(String)
        case notConfigured(String)
        case unverified(String)
        case conflict(String)

        var message: String {
            switch self {
            case let .configured(message), let .configuredExternally(message), let .notConfigured(message), let .unverified(message), let .conflict(message):
                return message
            }
        }

        /// True for either an unchanged app-owned block or a recognized
        /// external initializer. It is deliberately not an ownership claim.
        var isConfigured: Bool {
            switch self {
            case .configured, .configuredExternally: return true
            default: return false
            }
        }

        var isAppManaged: Bool {
            if case .configured = self { return true }
            return false
        }

        var isConfiguredExternally: Bool {
            if case .configuredExternally = self { return true }
            return false
        }
    }

    enum ExternalInitializationClassification: Equatable, Sendable {
        case recognized
        case none
        case unknown
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

    /// Restore is offered only for a presently app-owned block or for the
    /// narrow, safe acknowledgement flows used by an active receipt. A
    /// restored receipt alone never makes unrelated external shell setup ours.
    static func canRestore() -> Bool {
        do {
            guard let record = try readOptionalRecord() else { return false }
            try validateRecordPaths(record)
            try validateBackup(for: record)
            guard let snapshot = try readOptionalRegularFile(at: targetURL) else {
                return !record.originalFileExisted && record.restored != true
            }
            guard containsAnyMarker(in: snapshot.text) else {
                return record.restored != true
            }
            let block = try managedBlock(from: snapshot.text)
            guard isCanonicalManagedBlock(block), block == record.managedBlock,
                  countOccurrences(of: block, in: snapshot.text) == 1 else { return false }
            return true
        } catch {
            return false
        }
    }

    static func inspect() -> Inspection {
        do {
            let metadataKind = try pathKind(at: metadataURL)
            if case .missing = metadataKind {
                return try inspectUnownedTarget()
            }
            guard case .regular = metadataKind else {
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
                return .configured("The app-owned fnm block is present in ~/.zshrc. It is available to future interactive Zsh sessions and is optional for the app.")
            }

            guard record.restored == true else {
                return .conflict("the recorded app-owned block is missing; press Restore once to acknowledge that it is intentionally absent, then Configure again")
            }
            return inspection(for: snapshot.text)
        } catch let error as ConfigurationError {
            return .conflict(error.localizedDescription)
        } catch {
            return .conflict(error.localizedDescription)
        }
    }

    private static func inspectUnownedTarget() throws -> Inspection {
        switch try pathKind(at: targetURL) {
        case .missing:
            return .notConfigured("No Dev Manager shell configuration is recorded and ~/.zshrc does not exist. The optional shell change has not been made.")
        case .regular:
            guard let snapshot = try readOptionalRegularFile(at: targetURL) else {
                return .notConfigured("No Dev Manager shell configuration is recorded. The optional ~/.zshrc change has not been made.")
            }
            if containsAnyMarker(in: snapshot.text) {
                return .conflict("managed fnm markers are present in ~/.zshrc but their app ownership record is unavailable; the file was left unchanged")
            }
            return inspection(for: snapshot.text)
        case .symlink, .directory, .other:
            return .unverified("~/.zshrc is not a safe regular file to inspect. It was not followed or changed.")
        }
    }

    private static func inspection(for text: String) -> Inspection {
        switch classifyExternalInitialization(text) {
        case .recognized:
            return .configuredExternally("A recognized external fnm initializer is present in ~/.zshrc. It is not app-owned; Configure and Restore are unavailable. Recognition is not proof that every fresh shell runs it.")
        case .none:
            return .notConfigured("No Dev Manager shell configuration or recognized fnm initializer was found in ~/.zshrc. The optional shell change has not been made.")
        case .unknown:
            return .unverified("~/.zshrc contains fnm-related shell setup that Dev Manager cannot safely classify. It was left unchanged; Configure is unavailable.")
        }
    }

    static func configure(using fnmURL: URL, nodeVersion: String, fnmDirectoryURL: URL? = nil) throws -> String {
        if let fnmDirectoryURL, !fnmDirectoryURL.standardizedFileURL.path.hasPrefix("/") {
            throw ConfigurationError.unsupported("the selected fnm data root is not an absolute path")
        }
        let fnmPath = try resolvedExecutablePath(from: fnmURL)
        let block = makeManagedBlock(fnmPath: fnmPath, nodeVersion: nodeVersion, fnmDirectoryURL: fnmDirectoryURL)
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

            if let targetSnapshot {
                if hasRecognizedFNMInitialization(in: targetSnapshot.text), existingRecord.restored == true {
                    return "A recognized external fnm initializer is already present in ~/.zshrc; no app-owned block or backup was added."
                }
                if hasEquivalentFNMInitialization(in: targetSnapshot.text) {
                    throw ConfigurationError.conflict("an existing fnm-related shell configuration was detected; it was not duplicated or changed")
                }
            }

            guard existingRecord.restored == true else {
                throw ConfigurationError.conflict("the recorded app-owned block is missing and ~/.zshrc may have been changed; press Restore once to acknowledge that the block is intentionally absent, then Configure again")
            }
        } else if let targetSnapshot {
            if containsAnyMarker(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("a managed marker already exists but is not an unchanged, recorded app-owned block")
            }
            if hasRecognizedFNMInitialization(in: targetSnapshot.text) {
                return "A recognized external fnm initializer is already present in ~/.zshrc; no app-owned block or backup was added."
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
        return "Configured only ~/.zshrc with one marked fnm block. Future interactive Zsh sessions will select Node \(nodeVersion) when that installed version is available; project files are not changed by this action."
    }

    static func restore() throws -> String {
        guard canRestore() else {
            throw ConfigurationError.conflict("there is no safely recoverable app-owned shell configuration; external shell setup was left unchanged")
        }
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

    static func makeManagedBlock(fnmPath: String, nodeVersion: String, fnmDirectoryURL: URL?) -> String {
        let fnmDirectory = URL(fileURLWithPath: fnmPath).deletingLastPathComponent().path
        let rootLine = fnmDirectoryURL.map { "export FNM_DIR=\(shellQuote($0.standardizedFileURL.path))\n" } ?? ""
        return "\(startMarker)\n\(rootLine)export PATH=\(shellQuote(fnmDirectory)):$PATH\neval \"$(\(shellQuote(fnmPath)) env --use-on-cd --shell zsh)\"\n# Dev Manager selects the pinned runtime for this shell; no install or network action is requested.\nif command -v fnm >/dev/null 2>&1; then\n  fnm use \(shellQuote(nodeVersion)) >/dev/null 2>&1\nfi\n\(endMarker)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isCanonicalManagedBlock(_ block: String) -> Bool {
        let lines = block.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hasRoot = lines.count == 9
        let oldShape = lines.count == 8
        guard hasRoot || oldShape else { return false }
        let pathIndex = hasRoot ? 2 : 1
        let evalIndex = hasRoot ? 3 : 2
        let commentIndex = hasRoot ? 4 : 3
        let ifIndex = hasRoot ? 5 : 4
        let useIndex = hasRoot ? 6 : 5
        let fiIndex = hasRoot ? 7 : 6
        let endIndex = hasRoot ? 8 : 7
        guard lines[0] == startMarker,
              lines[pathIndex].hasPrefix("export PATH='") && lines[pathIndex].hasSuffix("':$PATH"),
              lines[evalIndex].hasPrefix("eval \"$('"),
              lines[evalIndex].hasSuffix("' env --use-on-cd --shell zsh)\""),
              lines[commentIndex] == "# Dev Manager selects the pinned runtime for this shell; no install or network action is requested.",
              lines[ifIndex] == "if command -v fnm >/dev/null 2>&1; then",
              lines[useIndex].hasPrefix("  fnm use '") && lines[useIndex].hasSuffix("' >/dev/null 2>&1"),
              lines[fiIndex] == "fi",
              lines[endIndex] == endMarker else { return false }
        if hasRoot {
            let rootPrefix = "export FNM_DIR='"
            guard lines[1].hasPrefix(rootPrefix), lines[1].hasSuffix("'") else { return false }
            let root = String(lines[1].dropFirst(rootPrefix.count).dropLast())
            guard root.hasPrefix("/"), !root.contains("\n") else { return false }
        }
        let pathPrefix = "export PATH='"
        let pathSuffix = "':$PATH"
        let path = String(lines[pathIndex].dropFirst(pathPrefix.count).dropLast(pathSuffix.count))
        guard path.hasPrefix("/"), !path.contains("\n") else { return false }
        let evalPrefix = "eval \"$('"
        let evalSuffix = "' env --use-on-cd --shell zsh)\""
        guard lines[evalIndex].hasPrefix(evalPrefix), lines[evalIndex].hasSuffix(evalSuffix) else { return false }
        let evalPath = String(lines[evalIndex].dropFirst(evalPrefix.count).dropLast(evalSuffix.count))
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

    /// Classifies only a small, standalone subset of fnm's documented shell
    /// initializer. This is intentionally not a shell parser: no command,
    /// substitution, profile, or sourced file is evaluated. The small amount
    /// of block tracking here prevents a valid top-level initializer from
    /// being hidden by an unrelated function later in the file.
    static func classifyExternalInitialization(_ text: String) -> ExternalInitializationClassification {
        var sawUnknown = false
        var sawRecognized = false
        var functionBraceDepth = 0
        var conditionalDepth = 0
        var pendingFunctionBody = false

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let withoutComment = removingShellComment(from: line)
            guard !withoutComment.isEmpty else { continue }

            let functionDeclaration = isFunctionDeclarationLine(withoutComment)
            let startsFunctionBodyOnNextLine = pendingFunctionBody && withoutComment.first == "{"
            let insideFunction = functionBraceDepth > 0 || pendingFunctionBody
            let insideConditional = conditionalDepth > 0
            let hasControlWrapper = insideConditional || isShellWrapperLine(withoutComment)
            let initializerCandidates = knownInitializerCandidates(in: withoutComment)

            // A candidate embedded in a declaration or control statement is
            // deliberately unknown. A candidate on an ordinary top-level
            // command line is the only form that can be recognized.
            if !initializerCandidates.isEmpty {
                if insideFunction || insideConditional || functionDeclaration || hasControlWrapper {
                    sawUnknown = true
                } else {
                    sawRecognized = true
                }
            }

            // Ignore fnm-managed paths and prose. Only command-like fnm setup
            // (including source/indirection) is ambiguous and should prevent a
            // green result.
            let isStandaloneInitializer = initializerCandidates.count == 1 &&
                withoutComment.trimmingCharacters(in: .whitespaces) == initializerCandidates[0]
            if isAmbiguousFNMSetupLine(withoutComment),
               !isStandaloneInitializer || insideFunction || insideConditional || hasControlWrapper {
                sawUnknown = true
            }

            if functionDeclaration {
                if hasOpeningBrace(withoutComment) {
                    functionBraceDepth += braceDelta(in: withoutComment)
                } else {
                    pendingFunctionBody = true
                }
            } else if startsFunctionBodyOnNextLine {
                pendingFunctionBody = false
                functionBraceDepth += 1 + braceDelta(in: withoutComment, excludingFirstOpeningBrace: true)
            } else if functionBraceDepth > 0 {
                functionBraceDepth = max(0, functionBraceDepth + braceDelta(in: withoutComment))
            }

            conditionalDepth += conditionalOpenCount(in: withoutComment)
            conditionalDepth = max(0, conditionalDepth - conditionalCloseCount(in: withoutComment))
        }

        if sawUnknown { return .unknown }
        return sawRecognized ? .recognized : .none
    }

    private static func isShellWrapperLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let firstWord = shellWords(line)?.first?.lowercased()
        return lower.hasPrefix("if ") || lower.hasPrefix("if\t") ||
            lower.hasPrefix("for ") || lower.hasPrefix("for\t") ||
            lower.hasPrefix("while ") || lower.hasPrefix("while\t") ||
            lower.hasPrefix("case ") || lower.hasPrefix("case\t") ||
            lower.hasPrefix("function ") || isFunctionDeclarationLine(line) ||
            firstWord == "then" || firstWord == "fi" || firstWord == "done" || firstWord == "esac" ||
            containsShellToken("then", in: line) || containsShellToken("fi", in: line) ||
            containsShellToken("done", in: line) || containsShellToken("esac", in: line)
    }

    /// Recognizes only the declaration shape needed to keep a wrapped fnm
    /// initializer unverified. The declaration may put its opening brace on
    /// the next line; this is deliberately not a shell grammar.
    private static func isFunctionDeclarationLine(_ line: String) -> Bool {
        if line.lowercased().hasPrefix("function ") { return true }

        var index = line.startIndex
        func skipWhitespace() {
            while index < line.endIndex, line[index].isWhitespace {
                index = line.index(after: index)
            }
        }
        func isNameStart(_ character: Character) -> Bool {
            character == "_" || character.isLetter
        }
        func isNameCharacter(_ character: Character) -> Bool {
            isNameStart(character) || character.isNumber
        }

        skipWhitespace()
        guard index < line.endIndex, isNameStart(line[index]) else { return false }
        index = line.index(after: index)
        while index < line.endIndex, isNameCharacter(line[index]) {
            index = line.index(after: index)
        }
        skipWhitespace()
        guard index < line.endIndex, line[index] == "(" else { return false }
        index = line.index(after: index)
        skipWhitespace()
        guard index < line.endIndex, line[index] == ")" else { return false }
        index = line.index(after: index)
        skipWhitespace()
        guard index == line.endIndex || line[index] == "{" else { return false }
        return true
    }

    private static func knownInitializerCandidates(in line: String) -> [String] {
        var candidates = [String]()
        var searchStart = line.startIndex
        let prefix = "eval \"$("
        let suffix = ")\""
        while let start = line.range(of: prefix, range: searchStart..<line.endIndex) {
            guard let end = line.range(of: suffix, range: start.upperBound..<line.endIndex) else { break }
            let candidate = String(line[start.lowerBound..<end.upperBound])
            if isKnownExternalInitializer(candidate) {
                candidates.append(candidate)
            }
            searchStart = end.upperBound
        }
        return candidates
    }

    private static func isAmbiguousFNMSetupLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.contains("fnm") else { return false }
        // An eval/source line is setup-shaped even when its executable is
        // indirect. Keep this conservative rather than treating every FNM_*
        // reference in an assignment or path as an invocation.
        if lower.hasPrefix("source ") || lower.hasPrefix("source\t") ||
            lower.hasPrefix(". ") || lower.hasPrefix(".\t") {
            return true
        }
        if lower.contains("eval ") {
            return true
        }
        if containsFNMVariableInExecutablePosition(in: line) {
            return true
        }

        for statement in line.split(separator: ";", omittingEmptySubsequences: true).map(String.init) {
            var words = shellWords(statement.trimmingCharacters(in: .whitespaces)) ?? []
            while words.first?.lowercased() == "then" {
                words.removeFirst()
            }
            guard let command = words.first?.lowercased() else { continue }
            let invokesFNM = command == "fnm" ||
                (command.hasSuffix("/fnm") && command.hasPrefix("/")) ||
                (command == "command" && words.dropFirst().first?.lowercased() == "fnm")
            guard invokesFNM else { continue }
            // `fnm env`, `fnm use`, and similar commands are setup. A path
            // containing `fnm` never becomes the command word here.
            return words.count > 1
        }
        return false
    }

    /// FNM_* expansions are ambiguous only when they can be the command being
    /// invoked. In particular, `${FNM_DIR:-...}` in `local`/`export` values
    /// and ordinary managed paths are data references, not fnm setup.
    private static func containsFNMVariableInExecutablePosition(in line: String) -> Bool {
        for statement in line.split(separator: ";", omittingEmptySubsequences: true).map(String.init) {
            var words = shellWords(statement.trimmingCharacters(in: .whitespaces)) ?? []
            while let first = words.first?.lowercased(),
                  ["if", "while", "until", "then", "!"].contains(first) {
                words.removeFirst()
            }
            while let first = words.first, isShellAssignmentWord(first) {
                words.removeFirst()
            }
            guard let command = words.first else { continue }
            if isFNMVariableExecutable(command) {
                return true
            }
            if command.lowercased() == "command",
               let executable = words.dropFirst().first,
               isFNMVariableExecutable(executable) {
                return true
            }
        }
        return false
    }

    private static func isShellAssignmentWord(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "=") else { return false }
        let name = word[..<equals]
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber } &&
            !name.first!.isNumber
    }

    private static func isFNMVariableExecutable(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard lower.first == "$" else { return false }
        if lower.hasPrefix("${") {
            guard let close = lower.firstIndex(of: "}") else { return false }
            let contents = lower[lower.index(after: lower.startIndex)..<close]
            let name = contents.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return name.contains("fnm")
        }
        var name = ""
        for character in lower.dropFirst() {
            guard character == "_" || character.isLetter || character.isNumber else { break }
            name.append(character)
        }
        return name.contains("fnm")
    }

    private static func removingShellComment(from line: String) -> String {
        var activeQuote: Character?
        for index in line.indices {
            let character = line[index]
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == "#" && (index == line.startIndex || line[line.index(before: index)].isWhitespace) {
                return String(line[..<index]).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }

    private static func containsShellToken(_ token: String, in line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: ";", with: " ")
        return (shellWords(normalized) ?? []).contains { $0.lowercased() == token }
    }

    private static func hasOpeningBrace(_ line: String) -> Bool {
        line.contains("{")
    }

    private static func braceDelta(in line: String, excludingFirstOpeningBrace: Bool = false) -> Int {
        var activeQuote: Character?
        var opens = 0
        var closes = 0
        var skippedOpening = !excludingFirstOpeningBrace
        for character in line {
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == "{" {
                if skippedOpening { opens += 1 } else { skippedOpening = true }
            } else if character == "}" {
                closes += 1
            }
        }
        return opens - closes
    }

    private static func conditionalOpenCount(in line: String) -> Int {
        let lower = line.lowercased()
        return (lower.hasPrefix("if ") || lower.hasPrefix("if\t") ||
                lower.hasPrefix("for ") || lower.hasPrefix("for\t") ||
                lower.hasPrefix("while ") || lower.hasPrefix("while\t") ||
                lower.hasPrefix("case ") || lower.hasPrefix("case\t")) ? 1 : 0
    }

    private static func conditionalCloseCount(in line: String) -> Int {
        ["fi", "done", "esac"].reduce(into: 0) { count, token in
            if containsShellToken(token, in: line) { count += 1 }
        }
    }

    private static func hasRecognizedFNMInitialization(in text: String) -> Bool {
        classifyExternalInitialization(text) == .recognized
    }

    private static func isKnownExternalInitializer(_ line: String) -> Bool {
        guard line.hasPrefix("eval \"$("), line.hasSuffix(")\"") else { return false }
        let bodyStart = line.index(line.startIndex, offsetBy: 8)
        let bodyEnd = line.index(line.endIndex, offsetBy: -2)
        guard bodyStart < bodyEnd else { return false }
        let body = String(line[bodyStart..<bodyEnd])
        guard let words = shellWords(body), words.count >= 4,
              words[1] == "env" else { return false }
        let executable = words[0]
        guard executable == "fnm" || (executable.hasPrefix("/") && executable.hasSuffix("/fnm") && !executable.contains("$")) else {
            return false
        }

        var index = 2
        var hasShell = false
        while index < words.count {
            switch words[index] {
            case "--use-on-cd":
                index += 1
            case "--shell":
                guard index + 1 < words.count, words[index + 1] == "zsh", !hasShell else { return false }
                hasShell = true
                index += 2
            default:
                return false
            }
        }
        return hasShell
    }

    private static func shellWords(_ text: String) -> [String]? {
        var words = [String]()
        var word = ""
        var activeQuote: Character?
        var hasWord = false
        for character in text {
            if let quoted = activeQuote {
                if character == quoted {
                    activeQuote = nil
                } else {
                    word.append(character)
                }
                continue
            }
            if character == "'" || character == "\"" {
                activeQuote = character
                hasWord = true
            } else if character == "\\" {
                return nil
            } else if character.isWhitespace {
                if hasWord {
                    words.append(word)
                    word = ""
                    hasWord = false
                }
            } else {
                word.append(character)
                hasWord = true
            }
        }
        guard activeQuote == nil else { return nil }
        if hasWord { words.append(word) }
        return words
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
