#if DEBUG
import Foundation
import Testing
@testable import dev_manager

private final class OwnedTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<ProvisioningOwnedProcess.Outcome, Never>?
    func set(_ value: Task<ProvisioningOwnedProcess.Outcome, Never>) {
        lock.lock(); task = value; lock.unlock()
    }
    func cancel() {
        lock.lock(); let value = task; lock.unlock()
        value?.cancel()
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct GitHubAuthOperationTests {
    @Test("login uses the selected host and disables interactive helpers")
    func argumentsAndEnvironment() async throws {
        let host = try GitHubHostname("enterprise.example")
        let result = await GitHubAuthOperation.run(using: .init(executableURL: URL(fileURLWithPath: "/tmp/fake-gh"), version: "2.101.0"), hostname: host, onEvent: { _ in }, environment: [:]) { url, args, env, _, _, output in
            #expect(url.path == "/tmp/fake-gh")
            #expect(args == ["auth", "login", "--hostname", "enterprise.example", "--git-protocol", "https", "--web", "--clipboard=true"])
            #expect(env["GH_PROMPT_DISABLED"] == "1")
            #expect(env["GH_DEBUG"] == "" && env["DEBUG"] == "")
            #expect(env["GH_BROWSER"] == "/usr/bin/true" && env["BROWSER"] == "/usr/bin/true")
            #expect(output(.stdout, Data("First copy your one-time code: ABCD-1234\nOpen this URL to continue in your web browser: https://enterprise.example/login/device\n".utf8)))
            return .exited(0)
        }
        #expect(result.completion == .exited(0))
    }

    @Test("unsupported versions and environment credentials never launch")
    func blockedBeforeSpawn() async throws {
        let host = try GitHubHostname("enterprise.example")
        let runner: GitHubAuthOperation.Runner = { _, _, _, _, _, _ in
            Issue.record("unexpected child")
            return .launchFailed
        }
        let unsupported = await GitHubAuthOperation.run(using: .init(executableURL: URL(fileURLWithPath: "/tmp/fake-gh"), version: "2.106.0"), hostname: host, onEvent: { _ in }, environment: [:], run: runner)
        #expect(unsupported.completion == .failed(.unsupportedCLI))
        let token = await GitHubAuthOperation.run(using: .init(executableURL: URL(fileURLWithPath: "/tmp/fake-gh"), version: "2.101.0"), hostname: host, onEvent: { _ in }, environment: ["GH_ENTERPRISE_TOKEN": "fake"], run: runner)
        #expect(token.completion == .failed(.unavailable))
    }

    @Test("unknown output stops consumption with a fixed safe error")
    func unknownOutput() async throws {
        let host = try GitHubHostname("enterprise.example")
        let result = await GitHubAuthOperation.run(using: .init(executableURL: URL(fileURLWithPath: "/tmp/fake-gh"), version: "2.101.0"), hostname: host, onEvent: { _ in }, environment: [:]) { _, _, _, _, _, output in
            #expect(!output(.stderr, Data("unrecognized sensitive output\n".utf8)))
            return .consumerStopped
        }
        #expect(result.completion == .failed(.unsupportedOutput))
    }

    @Test("owned output is delivered before the child exits")
    func liveOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let received = directory.appendingPathComponent("received")
        let script = directory.appendingPathComponent("child.sh")
        try "printf 'hello\\n'\nwhile [ ! -e \"$GATE\" ]; do sleep 0.05; done\n".write(to: script, atomically: true, encoding: .utf8)
        let task = Task {
            await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path], environment: ["GATE": gate.path]) { _, data in
                if !data.isEmpty { FileManager.default.createFile(atPath: received.path, contents: nil) }
                return true
            }
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: received.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: received.path))
        FileManager.default.createFile(atPath: gate.path, contents: nil)
        #expect(await task.value == .exited(0))
    }

    @Test("output limit aborts a flooding child")
    func outputLimit() async {
        let outcome = await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes x"], environment: [:], timeout: 5, maximumOutputBytes: 65536) { _, _ in true }
        #expect(outcome == .outputLimitExceeded)
    }

    @Test("callback can synchronously cancel its own task")
    func callbackCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = directory.appendingPathComponent("gate")
        let pidFile = directory.appendingPathComponent("pid")
        let box = OwnedTaskBox()
        let task = Task {
            await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $$ > \"$PIDFILE\"; sleep 30 & while [ ! -e \"$GATE\" ]; do sleep 0.05; done; echo ready; wait"],
                environment: ["GATE": gate.path, "PIDFILE": pidFile.path], timeout: 5) { _, _ in
                    box.cancel()
                    return false
                }
        }
        box.set(task)
        FileManager.default.createFile(atPath: gate.path, contents: nil)
        #expect(await task.value == .cancelled)
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let group = try #require(pid)
        #expect(!ProcessLauncher.isGroupAlive(group))
    }

    @Test("inherited pipe writer is cleaned up after leader exit")
    func inheritedWriterDeadline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let start = Date()
        let outcome = await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $$ > \"$PIDFILE\"; sleep 30 & exit 0"],
            environment: ["PIDFILE": pidFile.path], timeout: 0.5) { _, _ in true }
        #expect(outcome == .deadlineExceeded)
        #expect(Date().timeIntervalSince(start) < 10)
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!ProcessLauncher.isGroupAlive(try #require(pid)))
    }

    @Test("pre-cancelled owned task never executes command")
    func cancellationBeforeSpawn() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            return await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "touch \"$MARKER\""], environment: ["MARKER": marker.path]) { _, _ in true }
        }
        task.cancel()
        gate.continuation.yield(())
        gate.continuation.finish()
        #expect(await task.value == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("consumer stop cleans up the owned group")
    func consumerStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let outcome = await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $$ > \"$PIDFILE\"; sleep 30 & echo unknown; wait"],
            environment: ["PIDFILE": pidFile.path], timeout: 5) { _, _ in false }
        #expect(outcome == .consumerStopped)
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!ProcessLauncher.isGroupAlive(try #require(pid)))
    }

    @Test("cancellation terminates an owned leader and pipe-holding child")
    func cancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let childFile = directory.appendingPathComponent("child")
        let task = Task {
            await ProvisioningOwnedProcess.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "echo $$ > \"$PIDFILE\"; sleep 30 & echo $! > \"$CHILDFILE\"; wait"],
                environment: ["PIDFILE": pidFile.path, "CHILDFILE": childFile.path]) { _, _ in true }
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: childFile.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let group = try #require(pid)
        #expect(ProcessLauncher.isGroupAlive(group))
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(!ProcessLauncher.isGroupAlive(group))
    }
}
#endif
