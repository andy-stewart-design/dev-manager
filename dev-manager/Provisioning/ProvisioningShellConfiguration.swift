import Darwin
import Foundation

/// The deliberately small optional shell configuration. It owns one marked block
/// in the current user's ~/.zshrc and never reads or edits ~/.zprofile.
enum ProvisioningShellConfiguration {
    static let targetFileName = ".zshrc"
    static let backupFileName = ".zshrc.dev-manager.backup"

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

    private typealias Record = ProvisioningShellPersistence.Record

    static func hasRecordedConfiguration(location: ProvisioningShellLocation = .production) -> Bool {
        let store = ProvisioningShellPersistence(location: location)
        return (try? store.readOptionalRecord()) != nil
    }

    /// Restore is offered only for a presently app-owned block or for the
    /// narrow, safe acknowledgement flows used by an active receipt. A
    /// restored receipt alone never makes unrelated external shell setup ours.
    static func canRestore(location: ProvisioningShellLocation = .production) -> Bool {
        let store = ProvisioningShellPersistence(location: location)
        do {
            guard let record = try store.readOptionalRecord() else { return false }
            try store.validateRecordPaths(record)
            try store.validateBackup(for: record)
            guard let snapshot = try store.readOptionalRegularFile(at: store.targetURL) else {
                return !record.originalFileExisted && record.restored != true
            }
            guard ProvisioningShellRecognizer.containsAnyMarker(in: snapshot.text) else {
                return record.restored != true
            }
            let block = try ProvisioningShellRecognizer.managedBlock(from: snapshot.text)
            guard isCanonicalManagedBlock(block), block == record.managedBlock,
                  ProvisioningShellRecognizer.countOccurrences(of: block, in: snapshot.text) == 1 else { return false }
            return true
        } catch {
            return false
        }
    }

    static func inspect(location: ProvisioningShellLocation = .production) -> Inspection {
        let store = ProvisioningShellPersistence(location: location)
        do {
            let metadataKind = try store.pathKind(at: store.metadataURL)
            if case .missing = metadataKind {
                return try inspectUnownedTarget(using: store)
            }
            guard case .regular = metadataKind else {
                throw ConfigurationError.unsafePath(store.metadataURL.path)
            }

            let record = try store.readRecord()
            try store.validateRecordPaths(record)
            try store.validateBackup(for: record)
            let snapshot = try store.readOptionalRegularFile(at: store.targetURL)
            guard let snapshot else {
                guard !record.originalFileExisted else {
                    throw ConfigurationError.conflict("the recorded ~/.zshrc is missing; it was left unchanged")
                }
                guard record.restored == true else {
                    return .conflict("the recorded app-owned block is missing; press Restore once to acknowledge that it is intentionally absent, then Configure again")
                }
                return .notConfigured("The app-owned fnm block is restored. ~/.zshrc is not currently configured by Dev Manager.")
            }

            if ProvisioningShellRecognizer.containsAnyMarker(in: snapshot.text) {
                let block = try ProvisioningShellRecognizer.managedBlock(from: snapshot.text)
                guard isCanonicalManagedBlock(block), block == record.managedBlock else {
                    throw ConfigurationError.conflict("the app-owned fnm block was changed; it will not be rewritten")
                }
                guard ProvisioningShellRecognizer.countOccurrences(of: block, in: snapshot.text) == 1 else {
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

    private static func inspectUnownedTarget(using store: ProvisioningShellPersistence) throws -> Inspection {
        switch try store.pathKind(at: store.targetURL) {
        case .missing:
            return .notConfigured("No Dev Manager shell configuration is recorded and ~/.zshrc does not exist. The optional shell change has not been made.")
        case .regular:
            guard let snapshot = try store.readOptionalRegularFile(at: store.targetURL) else {
                return .notConfigured("No Dev Manager shell configuration is recorded. The optional ~/.zshrc change has not been made.")
            }
            if ProvisioningShellRecognizer.containsAnyMarker(in: snapshot.text) {
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

    static func configure(
        using fnmURL: URL,
        nodeVersion: String,
        fnmDirectoryURL: URL? = nil,
        location: ProvisioningShellLocation = .production,
        failureInjector: ProvisioningShellPersistence.FailureInjector? = nil
    ) throws -> String {
        let store = ProvisioningShellPersistence(location: location, failureInjector: failureInjector)
        if let fnmDirectoryURL, !fnmDirectoryURL.standardizedFileURL.path.hasPrefix("/") {
            throw ConfigurationError.unsupported("the selected fnm data root is not an absolute path")
        }
        let fnmPath = try store.resolvedExecutablePath(from: fnmURL)
        let block = makeManagedBlock(fnmPath: fnmPath, nodeVersion: nodeVersion, fnmDirectoryURL: fnmDirectoryURL)
        let existingRecord = try store.readOptionalRecord()

        if let existingRecord {
            try store.validateRecordPaths(existingRecord)
            try store.validateBackup(for: existingRecord)
        }

        let targetSnapshot = try store.readOptionalRegularFile(at: store.targetURL)
        if let existingRecord {
            if let targetSnapshot, ProvisioningShellRecognizer.containsAnyMarker(in: targetSnapshot.text) {
                try ProvisioningShellRecognizer.validateOwnedBlock(in: targetSnapshot.text, expected: existingRecord.managedBlock)
                guard existingRecord.managedBlock == block else {
                    throw ConfigurationError.conflict("the detected fnm executable differs from the owned block; it will not be rewritten")
                }
                let unrelatedText = targetSnapshot.text.replacingOccurrences(of: existingRecord.managedBlock, with: "")
                guard !ProvisioningShellRecognizer.hasEquivalentFNMInitialization(in: unrelatedText) else {
                    throw ConfigurationError.conflict("an additional fnm-related shell configuration was detected; it was not changed or duplicated")
                }
                return "The existing app-owned ~/.zshrc block is unchanged; no duplicate initialization was added."
            }

            if let targetSnapshot {
                if ProvisioningShellRecognizer.hasRecognizedFNMInitialization(in: targetSnapshot.text), existingRecord.restored == true {
                    return "A recognized external fnm initializer is already present in ~/.zshrc; no app-owned block or backup was added."
                }
                if ProvisioningShellRecognizer.hasEquivalentFNMInitialization(in: targetSnapshot.text) {
                    throw ConfigurationError.conflict("an existing fnm-related shell configuration was detected; it was not duplicated or changed")
                }
            }

            guard existingRecord.restored == true else {
                throw ConfigurationError.conflict("the recorded app-owned block is missing and ~/.zshrc may have been changed; press Restore once to acknowledge that the block is intentionally absent, then Configure again")
            }
        } else if let targetSnapshot {
            if ProvisioningShellRecognizer.containsAnyMarker(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("a managed marker already exists but is not an unchanged, recorded app-owned block")
            }
            if ProvisioningShellRecognizer.hasRecognizedFNMInitialization(in: targetSnapshot.text) {
                return "A recognized external fnm initializer is already present in ~/.zshrc; no app-owned block or backup was added."
            }
            if ProvisioningShellRecognizer.hasEquivalentFNMInitialization(in: targetSnapshot.text) {
                throw ConfigurationError.conflict("an existing fnm-related shell configuration was detected; it was not duplicated or changed")
            }
        }

        let originalFileExisted = targetSnapshot != nil
        let originalMode = targetSnapshot?.mode ?? 0o600
        let leadingSeparatorAdded = targetSnapshot.map { !$0.text.isEmpty && !$0.text.hasSuffix("\n") } ?? false
        if existingRecord == nil {
            switch try store.pathKind(at: store.legacyBackupURL) {
            case .missing: break
            case .regular: throw ConfigurationError.conflict("a legacy backup exists but its ownership record is unavailable; it was not overwritten")
            case .symlink, .directory, .other: throw ConfigurationError.unsafePath(store.legacyBackupURL.path)
            }
        }
        let startsNewCycle = existingRecord == nil || existingRecord?.restored == true
        let backupURL: URL
        if startsNewCycle {
            backupURL = store.generationBackupURL()
            if originalFileExisted {
                try store.ensureMetadataDirectory()
                guard case .missing = try store.pathKind(at: backupURL) else {
                    throw ConfigurationError.conflict("the new shell backup path is already occupied")
                }
            }
        } else {
            guard let existingRecord else {
                throw ConfigurationError.conflict("the shell ownership record is unavailable")
            }
            backupURL = URL(fileURLWithPath: existingRecord.backupPath)
        }

        let backupKind = try store.pathKind(at: backupURL)
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
                _ = try store.readRegularFile(at: backupURL)
            } else {
                guard case .missing = backupKind else {
                    throw ConfigurationError.conflict("an unexpected backup exists for an originally absent ~/.zshrc")
                }
            }
        }

        let recheckedTarget = try store.readOptionalRegularFile(at: store.targetURL)
        guard recheckedTarget?.data == targetSnapshot?.data,
              recheckedTarget?.mode == targetSnapshot?.mode else {
            throw ConfigurationError.conflict("~/.zshrc changed during the safety check; no file was edited")
        }

        var createdBackup = false
        if let targetSnapshot, case .missing = backupKind {
            try store.writeAtomically(targetSnapshot.data, to: backupURL, mode: targetSnapshot.mode, metadataSource: store.targetURL, operation: .backup)
            createdBackup = true
        }

        // Establish ownership before replacing ~/.zshrc. If the target write
        // fails, Restore can safely acknowledge the attempt before retrying.
        let record = Record(
            version: 1,
            targetPath: store.targetURL.path,
            backupPath: backupURL.path,
            originalFileExisted: originalFileExisted,
            originalMode: UInt16(originalMode & 0o7777),
            leadingSeparatorAdded: leadingSeparatorAdded,
            managedBlock: block,
            restored: false
        )
        do {
            try store.writeRecord(record)
        } catch {
            if createdBackup { _ = unlink(backupURL.path) }
            throw error
        }

        let currentText = targetSnapshot?.text ?? ""
        let updatedText = currentText + (leadingSeparatorAdded ? "\n" : "") + block
        do {
            try store.writeAtomically(Data(updatedText.utf8), to: store.targetURL, mode: originalMode, metadataSource: targetSnapshot == nil ? nil : store.targetURL, operation: .target)
        } catch {
            throw ConfigurationError.writeFailed(store.targetURL.path, "\(error.localizedDescription) Ownership metadata was retained. Press Restore to acknowledge this incomplete attempt, then retry Configure.")
        }
        return "Configured only ~/.zshrc with one marked fnm block. Future interactive Zsh sessions will select Node \(nodeVersion) when that installed version is available; project files are not changed by this action."
    }

    static func restore(
        location: ProvisioningShellLocation = .production,
        failureInjector: ProvisioningShellPersistence.FailureInjector? = nil
    ) throws -> String {
        let store = ProvisioningShellPersistence(location: location, failureInjector: failureInjector)
        // canRestore is intentionally conservative for UI enablement. Restore
        // still handles the explicit acknowledgement cases, but every such
        // case must first prove that the receipt and its backup are owned and
        // safe. In particular, a completed receipt is not trusted by itself.
        guard let record = try store.readOptionalRecord() else {
            throw ConfigurationError.conflict("there is no safely recoverable app-owned shell configuration; external shell setup was left unchanged")
        }
        try store.validateRecordPaths(record)
        try store.validateBackup(for: record)

        guard let snapshot = try store.readOptionalRegularFile(at: store.targetURL) else {
            guard !record.originalFileExisted else {
                throw ConfigurationError.conflict("the recorded ~/.zshrc is missing; it was left unchanged")
            }
            guard record.restored != true else {
                return "The app-owned fnm block is already restored; no shell file was changed."
            }
            var updatedRecord = record
            updatedRecord.restored = true
            try store.writeRecord(updatedRecord)
            return "The app-owned fnm block was already absent; the restore receipt was recorded and no shell file was changed."
        }

        guard ProvisioningShellRecognizer.containsAnyMarker(in: snapshot.text) else {
            let rechecked = try store.readRegularFile(at: store.targetURL)
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
            try store.writeRecord(updatedRecord)
            return "The app-owned fnm block was already absent; the restore receipt was recorded and ~/.zshrc was left unchanged. Configure can now start a new safe cycle."
        }

        let block = try ProvisioningShellRecognizer.managedBlock(from: snapshot.text)
        guard isCanonicalManagedBlock(block), block == record.managedBlock else {
            throw ConfigurationError.conflict("the app-owned fnm block was changed; it was not rewritten or removed")
        }
        guard ProvisioningShellRecognizer.countOccurrences(of: block, in: snapshot.text) == 1 else {
            throw ConfigurationError.conflict("the app-owned fnm block is duplicated; the file was left unchanged")
        }

        var restoredText = snapshot.text.replacingOccurrences(of: block, with: "")
        if record.leadingSeparatorAdded,
           record.originalFileExisted,
           let blockRange = snapshot.text.range(of: block),
           blockRange.lowerBound > snapshot.text.startIndex {
            let preceding = snapshot.text.index(before: blockRange.lowerBound)
            let prefix = String(snapshot.text[..<blockRange.lowerBound])
            let originalText = try store.readRegularFile(at: URL(fileURLWithPath: record.backupPath)).text
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

        let rechecked = try store.readRegularFile(at: store.targetURL)
        guard rechecked.data == snapshot.data,
              rechecked.mode == snapshot.mode else {
            throw ConfigurationError.conflict("~/.zshrc changed during restore; no file was edited")
        }

        if !record.originalFileExisted && restoredText.isEmpty {
            guard unlink(store.targetURL.path) == 0 else {
                throw ConfigurationError.writeFailed(store.targetURL.path, String(cString: strerror(errno)))
            }
        } else {
            try store.writeAtomically(Data(restoredText.utf8), to: store.targetURL, mode: snapshot.mode, metadataSource: store.targetURL, operation: .target)
        }

        // The target has been restored before this receipt is written. If the
        // metadata write fails, a retry sees the absent block and only records
        // this receipt; it does not touch the user's target again.
        var updatedRecord = record
        updatedRecord.restored = true
        try store.writeRecord(updatedRecord)
        return "Removed only the app-owned fnm block from ~/.zshrc. Unrelated content and permissions were preserved; the restore receipt was recorded and the backup remains available for inspection."
    }

    static func makeManagedBlock(fnmPath: String, nodeVersion: String, fnmDirectoryURL: URL?) -> String {
        ProvisioningShellRecognizer.makeManagedBlock(fnmPath: fnmPath, nodeVersion: nodeVersion, fnmDirectoryURL: fnmDirectoryURL)
    }

    static func isCanonicalManagedBlock(_ block: String) -> Bool {
        ProvisioningShellRecognizer.isCanonicalManagedBlock(block)
    }

    static func classifyExternalInitialization(_ text: String) -> ExternalInitializationClassification {
        ProvisioningShellRecognizer.classifyExternalInitialization(text)
    }
}
