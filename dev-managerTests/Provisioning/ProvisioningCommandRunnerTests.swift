#if DEBUG
import Darwin
import Foundation
import Testing
@testable import dev_manager

@Suite(.serialized)
struct ProvisioningCommandRunnerTests {
    @Test("bounded runner drains concurrent large stdout and stderr and preserves exact tails")
    func drainsLargeOutputWithoutPipeBackpressure() async throws {
        let command = "(yes O | head -c 200000; printf 'stdout-tail\\n') & stdout_pid=$!; (yes E | head -c 200000 >&2; printf 'stderr-tail\\n' >&2) & stderr_pid=$!; wait $stdout_pid; wait $stderr_pid"
        let result = await ProvisioningCommandRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            timeout: 5
        )

        #expect(result.succeeded)
        #expect(!result.timedOut)
        #expect(result.stdout.hasSuffix("stdout-tail\n"))
        #expect(result.stderr.hasSuffix("stderr-tail\n"))
        #expect(result.stdout.utf8.count <= 12_000)
        #expect(result.stderr.utf8.count <= 12_000)
    }

    @Test("leader exit with inherited pipes returns bounded timeout diagnostics and cleans its group")
    func descendantHoldingPipesCannotExtendCommandDeadline() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let groupFile = root.appendingPathComponent("group-id")
        let script = root.appendingPathComponent("holds-pipes.sh")
        try "#!/bin/sh\n(sleep 30) &\nprintf '%s\\n' \"$$\" > \"$PROVISIONING_GROUP_FILE\"\nprintf 'parent-diagnostic\\n'\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let started = Date()
        let result = await ProvisioningCommandRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path],
            environment: ["PROVISIONING_GROUP_FILE": groupFile.path],
            timeout: 0.5
        )
        let elapsed = Date().timeIntervalSince(started)
        let boundedElapsed = 0.5 + (2 * ProvisioningConfiguration.processCleanupGrace) +
            ProvisioningConfiguration.processDrainCancellationGrace + 5

        #expect(elapsed <= boundedElapsed)
        #expect(!result.succeeded)
        #expect(result.timedOut)
        #expect(result.stdout.contains("parent-diagnostic"))
        #expect(result.stderr.contains("Timed out"))
        #expect(result.stdout.utf8.count <= 12_000)
        #expect(result.stderr.utf8.count <= 12_000)

        try await waitForFile(groupFile)
        let groupID = Int32(try String(contentsOf: groupFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        var groupMembersGone = false
        for _ in 0..<20 {
            if !ProcessLauncher.isGroupAlive(groupID) {
                groupMembersGone = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // The leader has already exited/reaped by this point; isGroupAlive is the
        // sensible descendant-only assertion because its helper excludes the leader.
        #expect(groupMembersGone)
        #expect(!ProcessLauncher.isGroupAlive(groupID))
    }

    @Test("leader-only timeout signals and reaps the owned leader within the bound")
    func leaderOnlyTimeoutReapsLeader() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let leaderFile = root.appendingPathComponent("leader-id")
        let script = root.appendingPathComponent("leader-only.sh")
        try "#!/bin/sh\nprintf '%s\\n' \"$$\" > \"$PROVISIONING_LEADER_FILE\"\nexec sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let deadline: TimeInterval = 0.5
        let started = Date()
        let result = await ProvisioningCommandRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path],
            environment: ["PROVISIONING_LEADER_FILE": leaderFile.path],
            timeout: deadline
        )
        let elapsed = Date().timeIntervalSince(started)
        let boundedElapsed = deadline + (2 * ProvisioningConfiguration.processCleanupGrace) +
            ProvisioningConfiguration.processDrainCancellationGrace + 5

        #expect(result.timedOut)
        #expect(!result.succeeded)
        #expect(elapsed <= boundedElapsed)
        try await waitForFile(leaderFile)
        let leaderID = Int32(try String(contentsOf: leaderFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        #expect(kill(leaderID, 0) != 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-manager-provisioning-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func waitForFile(_ url: URL) async throws {
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for process-group marker")
    }
}
#endif
