import Foundation
import Testing
@testable import dev_manager

@Suite(.serialized)
struct ProjectRunnerTests {

@Test("real run captures cwd and both streams and blocks duplicate start")
@MainActor
func realRunCapturesOutputAndBlocksDuplicateStart() async throws {
    let root = try makeRunnerTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = try makeProject(in: root, command: "printf 'cwd=%s\\n' \"$PWD\"; printf 'stdout-ok\\n'; printf 'stderr-ok\\n' >&2; sleep 30")
    let shell = try makeTestShell(in: root)
    let spawned = try ProcessLauncher.spawn(shell: shell, folder: project.folderURL, command: project.command)
    let stdoutTask = Task.detached { String(data: (try? spawned.stdout.readToEnd()) ?? Data(), encoding: .utf8) ?? "" }
    let stderrTask = Task.detached { String(data: (try? spawned.stderr.readToEnd()) ?? Data(), encoding: .utf8) ?? "" }
    try await Task.sleep(for: .milliseconds(200))
    let stopResult = await Task.detached { ProcessLauncher.stop(identity: ProcessIdentity(processID: spawned.processID, processGroupID: spawned.processGroupID)) }.value
    let stdout = await stdoutTask.value
    let stderr = await stderrTask.value
    #expect(stopResult.groupGone)
    #expect(stdout.contains("cwd=") && stdout.contains(project.folderURL.lastPathComponent))
    #expect(stdout.contains("stdout-ok"))
    #expect(stderr.contains("stderr-ok"))

    let runner = ProjectRunner(shellEnvironment: shell)
    _ = runner.start(project: project)
    #expect(runner.start(project: project) == nil)
    _ = await runner.stopAll()
}

@Test("stop owns ordinary children without touching a separate run")
@MainActor
func stopOwnsChildrenAndIsolatesRuns() async throws {
    let root = try makeRunnerTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let firstFolder = root.appendingPathComponent("first", isDirectory: true)
    let secondFolder = root.appendingPathComponent("second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: false)
    let childFile = root.appendingPathComponent("child.pid")
    let shell = try makeTestShell(in: root)
    let first = try ProcessLauncher.spawn(shell: shell, folder: firstFolder, command: "sleep 60 & child=$!; printf '%s\\n' \"$child\" > '\(childFile.path)'; wait $child")
    let second = try ProcessLauncher.spawn(shell: shell, folder: secondFolder, command: "sleep 60")
    defer {
        _ = ProcessLauncher.stop(identity: ProcessIdentity(processID: first.processID, processGroupID: first.processGroupID))
        _ = ProcessLauncher.stop(identity: ProcessIdentity(processID: second.processID, processGroupID: second.processGroupID))
    }

    try await waitForFile(childFile)
    let childPID = Int32(try String(contentsOf: childFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    _ = await Task.detached { ProcessLauncher.stop(identity: ProcessIdentity(processID: first.processID, processGroupID: first.processGroupID)) }.value
    // The child is the safety proof. macOS may briefly retain a killed group's
    // zombie bookkeeping after the finite escalation, which is reported rather
    // than hidden by the launcher.
    #expect(!ProcessLauncher.isGroupAlive(childPID))
    #expect(ProcessLauncher.isGroupAlive(second.processGroupID))
    _ = await Task.detached { ProcessLauncher.stop(identity: ProcessIdentity(processID: second.processID, processGroupID: second.processGroupID)) }.value
}

@Test("concurrent stop requests share one cleanup barrier")
@MainActor
func concurrentStopRequestsShareOneCleanupBarrier() async throws {
    let root = try makeRunnerTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = try makeProject(in: root, command: "sleep 30")
    let runner = ProjectRunner(shellEnvironment: try makeTestShell(in: root))

    _ = runner.start(project: project)
    runner.stop(projectID: project.id)
    runner.stop(projectID: project.id)
    #expect(await runner.stopAll())
    #expect(!runner.activeProjectIDs.contains(project.id))
}

@Test("unterminated high-rate output stays bounded")
@MainActor
func unterminatedHighRateOutputStaysBounded() async throws {
    let root = try makeRunnerTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = try makeProject(in: root, command: "yes x | head -c 500000; sleep 1")
    let runner = ProjectRunner(shellEnvironment: try makeTestShell(in: root))

    _ = runner.start(project: project)
    try await waitForInactiveState(runner, projectID: project.id)
    let state = runner.state(for: project.id)
    let retainedBytes = state?.logs.reduce(0) { $0 + $1.text.utf8.count } ?? 0
    #expect(retainedBytes <= LogBuffer.maximumBytes)
    #expect(state?.logs.contains { $0.text.contains("truncated") || $0.text.contains("dropped") } == true)
}

@Test("missing command reports an actionable launch result")
@MainActor
func missingCommandIsVisible() async throws {
    let root = try makeRunnerTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let project = try makeProject(in: root, command: "dev-manager-command-that-does-not-exist-\(UUID().uuidString)")
    let runner = ProjectRunner(shellEnvironment: try makeTestShell(in: root))

    _ = runner.start(project: project)
    try await waitForInactiveState(runner, projectID: project.id)
    let state = runner.state(for: project.id)
    #expect(state?.message?.contains("127") == true || state?.logs.contains { $0.text.contains("command not found") } == true)
    #expect(state?.logs.contains { $0.stream == .stderr } == true)
}
}

@MainActor
private func waitForInactiveState(_ runner: ProjectRunner, projectID: UUID) async throws {
    for _ in 0..<160 {
        if let state = runner.state(for: projectID), !state.isActive { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Timed out waiting for command exit")
}

@MainActor
private func waitForFile(_ url: URL) async throws {
    for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Timed out waiting for child PID file")
}

@MainActor
private func makeRunnerTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dev-manager-runner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

@MainActor
private func makeTestShell(in root: URL) throws -> ShellEnvironment {
    let zshDirectory = root.appendingPathComponent("empty-zsh", isDirectory: true)
    let homeDirectory = root.appendingPathComponent("empty-home", isDirectory: true)
    try FileManager.default.createDirectory(at: zshDirectory, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: false)
    return try ShellEnvironment.currentZsh(homeDirectory: homeDirectory, zdotdir: zshDirectory)
}

@MainActor
private func makeProject(in root: URL, command: String) throws -> Project {
    let folder = root.appendingPathComponent("project-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return try Project(folderURL: folder, command: command)
}
