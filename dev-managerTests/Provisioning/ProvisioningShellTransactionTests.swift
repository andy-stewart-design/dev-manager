#if DEBUG
import Foundation
import Testing
@testable import dev_manager

@Suite("Provisioning shell transactions")
@MainActor
struct ProvisioningShellTransactionTests {
    private struct Fixture {
        let root: URL
        let location: ProvisioningShellLocation
        let target: URL
        let support: URL
        let fnm: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("dev-manager-shell-\(UUID().uuidString)", isDirectory: true)
            let home = root.appendingPathComponent("home", isDirectory: true)
            support = root.appendingPathComponent("application-support", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            location = ProvisioningShellLocation(homeURL: home, applicationSupportURL: support)
            target = home.appendingPathComponent(ProvisioningShellConfiguration.targetFileName)
            fnm = home.appendingPathComponent("fnm")
            try Data("fake fnm".utf8).write(to: fnm)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fnm.path)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        func writeTarget(_ text: String, mode: Int = 0o600) throws {
            try Data(text.utf8).write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
        }

        func data(at url: URL) -> Data? {
            try? Data(contentsOf: url)
        }

        func mode(of url: URL) -> Int {
            let attributes = try! FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.posixPermissions] as! NSNumber).intValue
        }

        func receiptURL() -> URL {
            support.appendingPathComponent("Dev Manager", isDirectory: true)
                .appendingPathComponent(".provisioning-shell-configuration.json")
        }

        func backups() -> [URL] {
            let directory = support.appendingPathComponent("Dev Manager", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter {
                $0.lastPathComponent.hasPrefix(".zshrc.dev-manager.backup.")
            } ?? []
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try body(fixture)
    }

    @Test("missing target is configured, acknowledged, and restored to absence")
    func missingTargetRoundTrip() throws {
        try withFixture { fixture in
            _ = try ProvisioningShellConfiguration.configure(
                using: fixture.fnm,
                nodeVersion: "24.21.0",
                location: fixture.location
            )
            #expect(FileManager.default.fileExists(atPath: fixture.target.path))
            #expect(fixture.data(at: fixture.receiptURL()) != nil)
            #expect(fixture.mode(of: fixture.receiptURL()) == 0o600)
            #expect(fixture.backups().isEmpty) // no backup is needed for an originally absent target
            #expect(ProvisioningShellConfiguration.canRestore(location: fixture.location))

            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            #expect(!FileManager.default.fileExists(atPath: fixture.target.path))
            #expect(ProvisioningShellConfiguration.inspect(location: fixture.location).isAppManaged == false)
            #expect(try ProvisioningShellConfiguration.restore(location: fixture.location).contains("already restored"))
        }
    }

    @Test("existing CRLF content, separators, and permissions round trip byte-for-byte")
    func existingTargetRoundTrip() throws {
        try withFixture { fixture in
            let original = "export ORIGINAL=1\r\nlast-line"
            try fixture.writeTarget(original, mode: 0o640)
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            #expect(fixture.mode(of: fixture.target) == 0o640)
            #expect(fixture.backups().count == 1)
            #expect(fixture.mode(of: fixture.backups()[0]) == 0o640)
            #expect(fixture.mode(of: fixture.receiptURL()) == 0o600)
            #expect(fixture.data(at: fixture.backups()[0]) == Data(original.utf8))

            let configured = try #require(String(data: fixture.data(at: fixture.target)!, encoding: .utf8))
            #expect(configured.contains("# >>> Dev Manager managed fnm initialization >>>"))
            #expect(configured.contains("fnm use '24.21.0'"))
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            #expect(fixture.data(at: fixture.target) == Data(original.utf8))
            #expect(fixture.mode(of: fixture.target) == 0o640)

            let restoredTarget = try #require(fixture.data(at: fixture.target))
            let restoredTargetMode = fixture.mode(of: fixture.target)
            let restoredReceipt = try #require(fixture.data(at: fixture.receiptURL()))
            let restoredReceiptMode = fixture.mode(of: fixture.receiptURL())
            let backup = try #require(fixture.backups().first)
            let restoredBackup = try #require(fixture.data(at: backup))
            let restoredBackupMode = fixture.mode(of: backup)
            #expect(try ProvisioningShellConfiguration.restore(location: fixture.location).contains("already restored"))
            #expect(fixture.data(at: fixture.target) == restoredTarget)
            #expect(fixture.mode(of: fixture.target) == restoredTargetMode)
            #expect(fixture.data(at: fixture.receiptURL()) == restoredReceipt)
            #expect(fixture.mode(of: fixture.receiptURL()) == restoredReceiptMode)
            #expect(fixture.data(at: backup) == restoredBackup)
            #expect(fixture.mode(of: backup) == restoredBackupMode)
        }
    }

    @Test("repeated configure is idempotent")
    func repeatedConfigure() throws {
        try withFixture { fixture in
            try fixture.writeTarget("# user content\n", mode: 0o644)
            let first = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            let firstTarget = try #require(fixture.data(at: fixture.target))
            let firstReceipt = try #require(fixture.data(at: fixture.receiptURL()))
            let second = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            #expect(second.contains("unchanged"))
            #expect(fixture.data(at: fixture.target) == firstTarget)
            #expect(fixture.data(at: fixture.receiptURL()) == firstReceipt)
            #expect(first.contains("Configured"))
        }
    }

    @Test("unsafe target, backup, and receipt paths refuse without mutation")
    func unsafePaths() throws {
        try withFixture { fixture in
            let outside = fixture.root.appendingPathComponent("outside")
            try Data("outside".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: fixture.target, withDestinationURL: outside)
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            }
            #expect(fixture.data(at: outside) == Data("outside".utf8))
            #expect(fixture.data(at: fixture.receiptURL()) == nil)
        }

        try withFixture { fixture in
            try fixture.writeTarget("baseline")
            let legacyBackup = fixture.location.homeURL.appendingPathComponent(ProvisioningShellConfiguration.backupFileName)
            let outside = fixture.root.appendingPathComponent("backup-outside")
            try Data("keep".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: legacyBackup, withDestinationURL: outside)
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == Data("baseline".utf8))
            #expect(fixture.data(at: outside) == Data("keep".utf8))
        }

        try withFixture { fixture in
            let directory = fixture.support.appendingPathComponent("Dev Manager", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let outside = fixture.root.appendingPathComponent("receipt-outside")
            try Data("keep".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: fixture.receiptURL(), withDestinationURL: outside)
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            }
            #expect(fixture.data(at: outside) == Data("keep".utf8))
        }
    }

    @Test("edited or duplicated app block is a conflict and unrelated edits survive restore")
    func conflictAndUnrelatedEdit() throws {
        try withFixture { fixture in
            try fixture.writeTarget("user-before\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            let configured = try #require(String(data: fixture.data(at: fixture.target)!, encoding: .utf8))
            let block = ProvisioningShellConfiguration.makeManagedBlock(fnmPath: fixture.fnm.resolvingSymlinksInPath().path, nodeVersion: "24.21.0", fnmDirectoryURL: nil)
            let duplicated = configured + block
            try Data(duplicated.utf8).write(to: fixture.target)
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == Data(duplicated.utf8))

            try Data((configured + "\nuser-after\n").utf8).write(to: fixture.target)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            let restored = try #require(String(data: fixture.data(at: fixture.target)!, encoding: .utf8))
            #expect(restored.contains("user-before"))
            #expect(restored.contains("user-after"))
            #expect(!restored.contains("managed fnm initialization"))
        }
    }

    @Test("edited managed block is a conflict without mutating target, receipt, or backup")
    func editedBlockConflictDoesNotMutate() throws {
        try withFixture { fixture in
            try fixture.writeTarget("baseline\n", mode: 0o640)
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            let configured = try #require(String(data: fixture.data(at: fixture.target)!, encoding: .utf8))
            let edited = configured.replacingOccurrences(of: "fnm use '24.21.0'", with: "fnm use '24.21.1'")
            let receipt = try #require(fixture.data(at: fixture.receiptURL()))
            let receiptMode = fixture.mode(of: fixture.receiptURL())
            let backup = try #require(fixture.backups().first)
            let backupData = try #require(fixture.data(at: backup))
            let backupMode = fixture.mode(of: backup)
            try Data(edited.utf8).write(to: fixture.target)

            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == Data(edited.utf8))
            #expect(fixture.mode(of: fixture.target) == 0o640)
            #expect(fixture.data(at: fixture.receiptURL()) == receipt)
            #expect(fixture.mode(of: fixture.receiptURL()) == receiptMode)
            #expect(fixture.data(at: backup) == backupData)
            #expect(fixture.mode(of: backup) == backupMode)
        }
    }

    @Test("completed restore rejects tampered receipt paths and versions")
    func completedRestoreRejectsTamperedReceipt() throws {
        try withFixture { fixture in
            try fixture.writeTarget("baseline\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            let target = try #require(fixture.data(at: fixture.target))
            let receipt = try #require(fixture.data(at: fixture.receiptURL()))
            let backup = try #require(fixture.backups().first)
            let backupData = try #require(fixture.data(at: backup))
            var pathTamper = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
            pathTamper["targetPath"] = fixture.root.appendingPathComponent("outside").path
            let pathReceipt = try JSONSerialization.data(withJSONObject: pathTamper)
            try pathReceipt.write(to: fixture.receiptURL())
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == target)
            #expect(fixture.data(at: fixture.receiptURL()) == pathReceipt)
            #expect(fixture.data(at: backup) == backupData)

            try receipt.write(to: fixture.receiptURL())
            var backupPathTamper = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
            backupPathTamper["backupPath"] = fixture.root.appendingPathComponent("outside-backup").path
            let backupPathReceipt = try JSONSerialization.data(withJSONObject: backupPathTamper)
            try backupPathReceipt.write(to: fixture.receiptURL())
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == target)
            #expect(fixture.data(at: fixture.receiptURL()) == backupPathReceipt)
            #expect(fixture.data(at: backup) == backupData)

            try receipt.write(to: fixture.receiptURL())
            var versionTamper = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
            versionTamper["version"] = 99
            let versionReceipt = try JSONSerialization.data(withJSONObject: versionTamper)
            try versionReceipt.write(to: fixture.receiptURL())
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == target)
            #expect(fixture.data(at: fixture.receiptURL()) == versionReceipt)
            #expect(fixture.data(at: backup) == backupData)
        }
    }

    @Test("completed restore rejects a backup replaced by a symlink")
    func completedRestoreRejectsSymlinkBackup() throws {
        try withFixture { fixture in
            try fixture.writeTarget("baseline\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            let target = try #require(fixture.data(at: fixture.target))
            let receipt = try #require(fixture.data(at: fixture.receiptURL()))
            let backup = try #require(fixture.backups().first)
            let outside = fixture.root.appendingPathComponent("backup-outside")
            try Data("keep".utf8).write(to: outside)
            try FileManager.default.removeItem(at: backup)
            try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: outside)

            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == target)
            #expect(fixture.data(at: fixture.receiptURL()) == receipt)
            #expect(fixture.data(at: outside) == Data("keep".utf8))
            let symlinkDestination = try FileManager.default.destinationOfSymbolicLink(atPath: backup.path)
            #expect(symlinkDestination == outside.path)
        }
    }

    @Test("repeated restore of a missing originally-existing target remains a conflict")
    func repeatedRestoreMissingOriginalTargetConflicts() throws {
        try withFixture { fixture in
            try fixture.writeTarget("baseline\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            let receipt = try #require(fixture.data(at: fixture.receiptURL()))
            let backup = try #require(fixture.backups().first)
            let backupData = try #require(fixture.data(at: backup))
            try FileManager.default.removeItem(at: fixture.target)

            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location)
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.target.path))
            #expect(fixture.data(at: fixture.receiptURL()) == receipt)
            #expect(fixture.data(at: backup) == backupData)
        }
    }

    @Test("legacy receipt without restored is safely acknowledged with legacy backup")
    func legacyReceiptAcknowledgement() throws {
        try withFixture { fixture in
            let original = "legacy baseline\n"
            try fixture.writeTarget(original, mode: 0o640)
            let legacyBackup = fixture.location.homeURL.appendingPathComponent(ProvisioningShellConfiguration.backupFileName)
            try Data(original.utf8).write(to: legacyBackup)
            let block = ProvisioningShellConfiguration.makeManagedBlock(
                fnmPath: fixture.fnm.resolvingSymlinksInPath().path,
                nodeVersion: "24.21.0",
                fnmDirectoryURL: nil
            )
            let receipt: [String: Any] = [
                "version": 1,
                "targetPath": fixture.target.path,
                "backupPath": legacyBackup.path,
                "originalFileExisted": true,
                "originalMode": 0o640,
                "leadingSeparatorAdded": false,
                "managedBlock": block
            ]
            try FileManager.default.createDirectory(at: fixture.receiptURL().deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: receipt).write(to: fixture.receiptURL())

            let targetBefore = try #require(fixture.data(at: fixture.target))
            #expect(try ProvisioningShellConfiguration.restore(location: fixture.location).contains("already absent"))
            #expect(fixture.data(at: fixture.target) == targetBefore)
            #expect(fixture.data(at: legacyBackup) == Data(original.utf8))
            let acknowledged = try #require(JSONSerialization.jsonObject(with: fixture.data(at: fixture.receiptURL())!) as? [String: Any])
            #expect(acknowledged["restored"] as? Bool == true)
        }
    }

    @Test("oversized shell file is rejected without mutation")
    func oversizedShellFileRejected() throws {
        try withFixture { fixture in
            let oversized = Data(repeating: 0x61, count: 4 * 1024 * 1024 + 1)
            try oversized.write(to: fixture.target)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: fixture.target.path)
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            }
            #expect(fixture.data(at: fixture.target) == oversized)
            #expect(fixture.data(at: fixture.receiptURL()) == nil)
            #expect(fixture.backups().isEmpty)
        }
    }

    @Test("receipt and target failures leave a recoverable transaction")
    func persistenceFailures() throws {
        try withFixture { fixture in
            try fixture.writeTarget("baseline\n")
            let receiptFailure: ProvisioningShellPersistence.FailureInjector = { operation, _ in
                operation == .receipt ? ProvisioningShellConfiguration.ConfigurationError.writeFailed("receipt", "injected") : nil
            }
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location, failureInjector: receiptFailure)
            }
            #expect(fixture.data(at: fixture.target) == Data("baseline\n".utf8))
            #expect(fixture.backups().isEmpty)

            let targetFailure: ProvisioningShellPersistence.FailureInjector = { operation, _ in
                operation == .target ? ProvisioningShellConfiguration.ConfigurationError.writeFailed("target", "injected") : nil
            }
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location, failureInjector: targetFailure)
            }
            #expect(String(data: fixture.data(at: fixture.target)!, encoding: .utf8) == "baseline\n")
            #expect(fixture.data(at: fixture.receiptURL()) != nil)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            #expect(String(data: fixture.data(at: fixture.target)!, encoding: .utf8) == "baseline\n")
        }

        try withFixture { fixture in
            try fixture.writeTarget("restore-baseline\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            let targetFailure: ProvisioningShellPersistence.FailureInjector = { operation, _ in
                operation == .target ? ProvisioningShellConfiguration.ConfigurationError.writeFailed("target", "injected") : nil
            }
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location, failureInjector: targetFailure)
            }
            #expect(String(data: fixture.data(at: fixture.target)!, encoding: .utf8)!.contains("managed fnm initialization"))
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            #expect(fixture.data(at: fixture.target) == Data("restore-baseline\n".utf8))
        }

        try withFixture { fixture in
            try fixture.writeTarget("receipt-baseline\n")
            _ = try ProvisioningShellConfiguration.configure(using: fixture.fnm, nodeVersion: "24.21.0", location: fixture.location)
            let receiptFailure: ProvisioningShellPersistence.FailureInjector = { operation, _ in
                operation == .receipt ? ProvisioningShellConfiguration.ConfigurationError.writeFailed("receipt", "injected") : nil
            }
            #expect(throws: ProvisioningShellConfiguration.ConfigurationError.self) {
                try ProvisioningShellConfiguration.restore(location: fixture.location, failureInjector: receiptFailure)
            }
            #expect(fixture.data(at: fixture.target) == Data("receipt-baseline\n".utf8))
            #expect(ProvisioningShellConfiguration.inspect(location: fixture.location).isAppManaged == false)
            _ = try ProvisioningShellConfiguration.restore(location: fixture.location)
            #expect(ProvisioningShellConfiguration.inspect(location: fixture.location).isAppManaged == false)
        }
    }
}
#endif
