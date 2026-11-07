import Combine
import Foundation

@MainActor
final class ProjectRunner: ObservableObject {
    @Published private(set) var states: [UUID: RunState] = [:]
    @Published private(set) var isTerminating = false
    private let configuredShellEnvironment: ShellEnvironment?

    init(shellEnvironment: ShellEnvironment? = nil) {
        self.configuredShellEnvironment = shellEnvironment
    }

    private final class ActiveRun {
        let projectID: UUID
        let runID: UUID
        let identity: ProcessIdentity
        let logBuffer = LogBuffer()
        var phase: RunPhase = .launching
        var message: String? = "Initializing zsh login/interactive environment…"
        var cleanupError: String?
        var initialized = false
        var launcherExited = false
        var cleanupCompleted = false
        var stdoutClosed = false
        var stderrClosed = false
        var partialLines: [RunOutputStream: Data] = [:]
        var partialLineDroppedBytes: [RunOutputStream: Int] = [:]
        var readers: [OutputReader] = []
        var outputInbox: OutputInbox?
        var initializationTask: Task<Void, Never>?
        var cleanupTask: Task<StopResult, Never>?
        var exit: ProcessExit?
        var stopRequested = false

        init(projectID: UUID, runID: UUID, process: SpawnedProcess) {
            self.projectID = projectID
            self.runID = runID
            self.identity = ProcessIdentity(processID: process.processID, processGroupID: process.processGroupID)
        }
    }

    private var activeRuns: [UUID: ActiveRun] = [:]
    private static let maximumIncompleteLineBytes = 64 * 1024

    func state(for projectID: UUID) -> RunState? { states[projectID] }

    var activeProjectIDs: Set<UUID> { Set(activeRuns.keys) }

    func canStart(projectID: UUID) -> Bool {
        !isTerminating && activeRuns[projectID] == nil
    }

    func canStop(projectID: UUID) -> Bool { activeRuns[projectID] != nil }

    func canRemove(projectID: UUID) -> Bool {
        !isTerminating && activeRuns[projectID] == nil
    }

    func beginTermination() -> Bool {
        guard !isTerminating else { return false }
        isTerminating = true
        return true
    }

    func finishTermination(success: Bool) {
        if !success { isTerminating = false }
    }

    @discardableResult
    func start(project: Project) -> UUID? {
        guard canStart(projectID: project.id) else {
            if let current = activeRuns[project.id] {
                current.message = "Start ignored: run \(current.runID.uuidString.prefix(8)) is still owned by Dev Manager. Stop it and wait for cleanup before starting another run."
                publish(current)
            }
            return nil
        }

        do {
            try Project.validate(folderURL: project.folderURL, command: project.command)
            let environment = try configuredShellEnvironment ?? ShellEnvironment.currentZsh()
            let runID = UUID()
            let process = try ProcessLauncher.spawn(shell: environment, folder: project.folderURL, command: project.command)
            let run = ActiveRun(projectID: project.id, runID: runID, process: process)
            activeRuns[project.id] = run
            states[project.id] = RunState.initial(runID: runID, processID: process.processID, processGroupID: process.processGroupID)

            let inbox = OutputInbox { [weak self] stream, data, eof, droppedBytes in
                self?.receive(data: data, stream: stream, eof: eof, droppedBytes: droppedBytes, projectID: project.id, runID: runID)
            }
            run.outputInbox = inbox
            let stdoutReader = OutputReader(handle: process.stdout, stream: .stdout) { stream, data, eof in
                inbox.enqueue(stream: stream, data: data, eof: eof)
            }
            let stderrReader = OutputReader(handle: process.stderr, stream: .stderr) { stream, data, eof in
                inbox.enqueue(stream: stream, data: data, eof: eof)
            }
            run.readers = [stdoutReader, stderrReader]

            Task.detached(priority: .utility) { [weak self] in
                switch ProcessLauncher.waitForExitObservation(processID: process.processID) {
                case .success:
                    await self?.launcherExited(projectID: project.id, runID: runID, exit: nil, error: nil)
                case let .failure(error):
                    await self?.launcherExited(projectID: project.id, runID: runID, exit: nil, error: error)
                }
            }
            run.initializationTask = Task.detached(priority: .utility) { [weak self] in
                let ready = ProcessLauncher.waitForReady(process.ready, timeout: 10)
                await self?.readyObserved(ready, projectID: project.id, runID: runID)
            }
            return runID
        } catch {
            let runID = UUID()
            states[project.id] = RunState(id: runID, processID: nil, processGroupID: nil, phase: .failed, logs: [], didTruncateLogs: false, message: actionableMessage(for: error), cleanupError: nil)
            return nil
        }
    }

    func stop(projectID: UUID) {
        guard let run = activeRuns[projectID] else { return }
        run.stopRequested = true
        run.phase = .stopping
        run.message = "Stopping owned process group \(run.identity.processGroupID)…"
        run.initializationTask?.cancel()
        publish(run)
        let task = beginCleanup(run)
        Task { @MainActor [weak self] in
            let result = await task.value
            self?.apply(stopResult: result, projectID: run.projectID, runID: run.runID)
        }
    }

    /// Starts/join one cleanup operation per owned run. The blocking OS calls are
    /// explicitly detached; the main actor only coordinates state and completion.
    func stopAll() async -> Bool {
        let runs = Array(activeRuns.values)
        var work: [(ActiveRun, Task<StopResult, Never>)] = []
        for run in runs {
            run.stopRequested = true
            run.phase = .stopping
            run.message = "Stopping for application quit…"
            run.initializationTask?.cancel()
            publish(run)
            work.append((run, beginCleanup(run)))
        }

        var allSucceeded = true
        await withTaskGroup(of: (ActiveRun, StopResult).self) { group in
            for (run, task) in work {
                group.addTask {
                    (run, await task.value)
                }
            }
            for await (run, result) in group {
                apply(stopResult: result, projectID: run.projectID, runID: run.runID)
                allSucceeded = allSucceeded && result.groupGone && result.error == nil
            }
        }
        return allSucceeded && activeRuns.isEmpty
    }

    private func beginCleanup(_ run: ActiveRun) -> Task<StopResult, Never> {
        if let task = run.cleanupTask { return task }
        let task = Task.detached(priority: .userInitiated) {
            ProcessLauncher.stop(identity: run.identity)
        }
        run.cleanupTask = task
        Task { @MainActor [weak self] in
            let result = await task.value
            self?.apply(stopResult: result, projectID: run.projectID, runID: run.runID)
        }
        return task
    }

    private func readyObserved(_ result: ReadyResult, projectID: UUID, runID: UUID) {
        guard let run = activeRuns[projectID], run.runID == runID else { return }
        guard !run.initialized, !run.launcherExited, run.phase != .stopping else { return }
        switch result {
        case .ready:
            run.initialized = true
            run.phase = .running
            run.message = "Command is running."
            run.initializationTask = nil
            publish(run)
        case .timedOut:
            run.phase = .stopping
            run.stopRequested = true
            run.message = "Shell initialization exceeded 10 seconds. Stop was requested; inspect shell startup output for prompts or slow setup."
            publish(run)
            _ = beginCleanup(run)
        case .closed:
            run.message = "Shell initialization ended before Dev Manager's private readiness handshake. Check the shell output for startup-file errors."
            run.phase = .failed
            publish(run)
            _ = beginCleanup(run)
        }
    }

    private func receive(data: Data, stream: RunOutputStream, eof: Bool, droppedBytes: Int, projectID: UUID, runID: UUID) {
        guard let run = activeRuns[projectID], run.runID == runID else { return }
        if droppedBytes > 0 {
            run.logBuffer.append(runID: run.runID, stream: stream, phase: run.initialized ? .command : .shellInitialization, text: "[Dev Manager dropped \(droppedBytes) bytes of pending output to keep controls responsive.]\n")
        }
        if !data.isEmpty { consume(data: data, stream: stream, run: run) }
        if eof {
            if let remainder = run.partialLines.removeValue(forKey: stream), !remainder.isEmpty {
                consumeLine(remainder, stream: stream, run: run)
            }
            if let dropped = run.partialLineDroppedBytes.removeValue(forKey: stream), dropped > 0 {
                run.logBuffer.append(runID: run.runID, stream: stream, phase: run.initialized ? .command : .shellInitialization, text: "[Dev Manager truncated \(dropped) bytes from an unterminated line.]\n")
            }
            if stream == .stdout { run.stdoutClosed = true } else { run.stderrClosed = true }
            finalizeIfReady(run)
        }
        publish(run)
    }

    private func consume(data: Data, stream: RunOutputStream, run: ActiveRun) {
        var bytes = Data()
        bytes.append(run.partialLines[stream] ?? Data())
        bytes.append(data)
        var start = bytes.startIndex
        while let newline = bytes[start...].firstIndex(of: 10) {
            consumeLine(Data(bytes[start..<newline]), stream: stream, run: run)
            start = bytes.index(after: newline)
        }
        var remainder = Data(bytes[start...])
        if remainder.count > Self.maximumIncompleteLineBytes {
            let excess = remainder.count - Self.maximumIncompleteLineBytes
            remainder = Data(remainder.suffix(Self.maximumIncompleteLineBytes))
            run.partialLineDroppedBytes[stream, default: 0] += excess
        }
        run.partialLines[stream] = remainder
    }

    private func consumeLine(_ data: Data, stream: RunOutputStream, run: ActiveRun) {
        var line = String(decoding: data, as: UTF8.self)
        if line.last == "\r" { line.removeLast() }
        let phase: RunOutputPhase = run.initialized ? .command : .shellInitialization
        run.logBuffer.append(runID: run.runID, stream: stream, phase: phase, text: line + "\n")
    }

    private func launcherExited(projectID: UUID, runID: UUID, exit: ProcessExit?, error: Error?) {
        guard let run = activeRuns[projectID], run.runID == runID else { return }
        run.launcherExited = true
        if let error {
            run.phase = .failed
            run.message = "The launcher exit could not be observed safely: \(error.localizedDescription)"
        } else if !run.initialized && run.phase != .stopping {
            run.phase = .failed
            run.message = "Shell initialization ended before Dev Manager could start the command. Check the shell output for startup-file errors."
        } else if run.phase != .stopping {
            run.message = "Command exited; finishing owned-process cleanup."
        }
        publish(run)
        _ = beginCleanup(run)
    }

    private func apply(stopResult: StopResult, projectID: UUID, runID: UUID) {
        guard let run = activeRuns[projectID], run.runID == runID else { return }
        if stopResult.groupGone, let exit = stopResult.exit {
            run.cleanupCompleted = true
            run.exit = exit
            run.cleanupError = nil
            run.launcherExited = true
            run.message = run.stopRequested ? "Owned process group stopped." : exitMessage(exit)
        } else {
            run.cleanupError = stopResult.error ?? "Owned process cleanup did not complete."
            run.message = run.cleanupError
            run.phase = .stopping
        }
        publish(run)
        finalizeIfReady(run)
    }

    private func finalizeIfReady(_ run: ActiveRun) {
        guard run.cleanupCompleted, run.stdoutClosed, run.stderrClosed else { return }
        run.initializationTask?.cancel()
        run.readers.forEach { $0.cancel() }
        run.phase = run.cleanupError == nil && run.phase != .failed ? .exited : .failed
        if run.message == "Owned process group stopped." { run.message = "Stopped." }
        publish(run)
        activeRuns.removeValue(forKey: run.projectID)
    }

    private func exitMessage(_ exit: ProcessExit) -> String {
        if let code = exit.exitCode {
            if code == 127 { return "Command could not be found (exit 127). Check the command name and the zsh startup environment; no installation was attempted." }
            return "Command exited with status \(code)."
        }
        if let signal = exit.signal { return "Command exited after signal \(signal)." }
        return "Command exited."
    }

    private func publish(_ run: ActiveRun) {
        let snapshot = run.logBuffer.snapshot()
        states[run.projectID] = RunState(id: run.runID, processID: run.identity.processID, processGroupID: run.identity.processGroupID, phase: run.phase, logs: snapshot.0, didTruncateLogs: snapshot.1, message: run.message, cleanupError: run.cleanupError)
    }

    private func actionableMessage(for error: Error) -> String {
        if let projectError = error as? ProjectValidationError { return projectError.localizedDescription }
        if let shellError = error as? ShellEnvironmentError { return shellError.localizedDescription }
        if let launcherError = error as? ProcessLauncherError { return launcherError.localizedDescription }
        return "Could not start the command: \(error.localizedDescription)"
    }
}

enum ProjectRunnerError: LocalizedError, Sendable {
    case projectBusy

    var errorDescription: String? {
        switch self {
        case .projectBusy: return "This project still has an owned process run. Stop it and wait for cleanup before removing the project."
        }
    }
}
