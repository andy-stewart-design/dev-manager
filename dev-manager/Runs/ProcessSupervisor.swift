import Foundation

@MainActor
final class ProcessSupervisor {
    private let configuredShellEnvironment: ShellEnvironment?
    private let stateHandler: (UUID, RunState) -> Void

    init(shellEnvironment: ShellEnvironment? = nil, stateHandler: @escaping (UUID, RunState) -> Void) {
        self.configuredShellEnvironment = shellEnvironment
        self.stateHandler = stateHandler
    }

    private final class ActiveRun {
        let projectID: UUID
        let runID: UUID
        var identity: ProcessIdentity?
        let logBuffer = LogBuffer()
        var phase: RunPhase = .launching
        var message: String? = "Initializing zsh login/interactive environment…"
        var cleanupError: String?
        var siteDiscoveryState: SiteDiscoveryState = .inactive
        var siteDiscovery: SiteDiscoveryCoordinator?
        var initialized = false
        var launcherExited = false
        var cleanupCompleted = false
        var stdoutClosed = false
        var stderrClosed = false
        let outputAccumulator = RunOutputAccumulator()
        var readers: [OutputReader] = []
        var outputInbox: OutputInbox?
        var initializationTask: Task<Void, Never>?
        var launchTask: Task<Void, Never>?
        var cleanupTask: Task<StopResult, Never>?
        var exit: ProcessExit?
        var stopRequested = false

        init(projectID: UUID, runID: UUID) {
            self.projectID = projectID
            self.runID = runID
        }
    }

    private var activeRuns: [UUID: ActiveRun] = [:]

    var activeProjectIDs: Set<UUID> { Set(activeRuns.keys) }

    func canStart(projectID: UUID) -> Bool {
        activeRuns[projectID] == nil
    }

    func canStop(projectID: UUID) -> Bool { activeRuns[projectID] != nil }

    func canRemove(projectID: UUID) -> Bool {
        activeRuns[projectID] == nil
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
        } catch {
            let runID = UUID()
            stateHandler(project.id, RunState(id: runID, processID: nil, processGroupID: nil, phase: .failed, logs: [], didTruncateLogs: false, message: actionableMessage(for: error), cleanupError: nil))
            return nil
        }

        // Reserve ownership and publish the pending identity before any potentially
        // blocking environment/spawn work leaves the main actor. Stop, Remove, and
        // Quit therefore observe this run immediately and cannot race a second start.
        let runID = UUID()
        let run = ActiveRun(projectID: project.id, runID: runID)
        activeRuns[project.id] = run
        stateHandler(project.id, RunState.pending(runID: runID, message: run.message))
        publish(run)

        let configuredShellEnvironment = self.configuredShellEnvironment
        run.launchTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if Task.isCancelled {
                    await self?.launchCompleted(process: nil, project: project, runID: runID, error: CancellationError())
                    return
                }
                let environment = try configuredShellEnvironment ?? ShellEnvironment.currentZsh()
                if Task.isCancelled {
                    await self?.launchCompleted(process: nil, project: project, runID: runID, error: CancellationError())
                    return
                }
                let process = try ProcessLauncher.spawn(shell: environment, folder: project.folderURL, command: project.command)
                await self?.launchCompleted(process: process, project: project, runID: runID, error: nil)
            } catch {
                await self?.launchCompleted(process: nil, project: project, runID: runID, error: error)
            }
        }
        return runID
    }

    private func launchCompleted(process: SpawnedProcess?, project: Project, runID: UUID, error: Error?) {
        guard let run = activeRuns[project.id], run.runID == runID else {
            // A run is normally retained until this callback. If that invariant is
            // ever broken after a successful spawn, clean only the created identity.
            if let process {
                _ = ProcessLauncher.stop(identity: ProcessIdentity(processID: process.processID, processGroupID: process.processGroupID, startTime: process.startTime))
            }
            return
        }

        guard let process else {
            run.launcherExited = true
            run.cleanupCompleted = true
            run.stdoutClosed = true
            run.stderrClosed = true
            run.phase = run.stopRequested ? .exited : .failed
            run.message = run.stopRequested ? "Start cancelled before a process was launched." : actionableMessage(for: error ?? CancellationError())
            publish(run)
            finalizeIfReady(run)
            return
        }

        run.identity = ProcessIdentity(processID: process.processID, processGroupID: process.processGroupID, startTime: process.startTime)
        RunJournal.record(projectID: project.id, identity: run.identity!)
        // Create discovery before the pipe readers so the first output chunk is retained.
        run.siteDiscovery = SiteDiscoveryCoordinator(identity: run.identity!) { [weak self, weak run] state in
            guard let self, let run, self.activeRuns[project.id]?.runID == runID else { return }
            run.siteDiscoveryState = state
            self.publish(run)
        }
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
        publish(run)

        Task.detached(priority: .utility) { [weak self] in
            switch ProcessLauncher.waitForExitObservation(processID: process.processID) {
            case .success:
                await self?.launcherExited(projectID: project.id, runID: runID, exit: nil, error: nil)
            case let .failure(error):
                await self?.launcherExited(projectID: project.id, runID: runID, exit: nil, error: error)
            }
        }

        if run.stopRequested {
            run.siteDiscovery?.cancel()
            run.phase = .stopping
            run.message = "Stopping the process group requested during launch…"
            publish(run)
            _ = beginCleanup(run)
        } else {
            run.initializationTask = Task.detached(priority: .utility) { [weak self] in
                let ready = ProcessLauncher.waitForReady(process.ready, timeout: 10)
                await self?.readyObserved(ready, projectID: project.id, runID: runID)
            }
        }
    }

    func stop(projectID: UUID) {
        guard let run = activeRuns[projectID] else { return }
        run.stopRequested = true
        run.siteDiscovery?.cancel()
        run.phase = .stopping
        run.message = run.identity.map { "Stopping owned process group \($0.processGroupID)…" } ?? "Cancelling pending launch…"
        run.initializationTask?.cancel()
        run.launchTask?.cancel()
        publish(run)
        guard let task = beginCleanup(run) else { return }
        Task { @MainActor [weak self] in
            let result = await task.value
            self?.apply(stopResult: result, projectID: run.projectID, runID: run.runID)
        }
    }

    /// Starts/join one cleanup operation per owned run. The blocking OS calls are
    /// explicitly detached; the main actor only coordinates state and completion.
    func stopAll() async -> Bool {
        let runs = Array(activeRuns.values)
        for run in runs {
            run.stopRequested = true
            run.siteDiscovery?.cancel()
            run.phase = .stopping
            run.message = "Stopping for application quit…"
            run.initializationTask?.cancel()
            run.launchTask?.cancel()
            publish(run)
        }

        // A pending launch must settle first. If it produces a process despite the
        // cancellation request, launchCompleted immediately transfers ownership to
        // the same cleanup path used by an already-running command.
        await withTaskGroup(of: Void.self) { group in
            for run in runs {
                if let launchTask = run.launchTask {
                    group.addTask { await launchTask.value }
                }
            }
        }

        var work: [(ActiveRun, Task<StopResult, Never>)] = []
        for run in runs {
            if let task = beginCleanup(run) {
                work.append((run, task))
            }
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

    private func beginCleanup(_ run: ActiveRun) -> Task<StopResult, Never>? {
        if let task = run.cleanupTask { return task }
        guard let identity = run.identity else { return nil }
        let task = Task.detached(priority: .userInitiated) {
            ProcessLauncher.stop(identity: identity)
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
            run.siteDiscovery?.startScanning()
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
        let phase: RunOutputPhase = run.initialized ? .command : .shellInitialization
        if !data.isEmpty {
            run.siteDiscovery?.receive(data, from: stream)
            run.outputAccumulator.consume(data: data, stream: stream, phase: phase, runID: run.runID, logBuffer: run.logBuffer)
        }
        if eof {
            run.siteDiscovery?.finish(stream)
            run.outputAccumulator.finish(stream: stream, phase: phase, runID: run.runID, logBuffer: run.logBuffer)
            if stream == .stdout { run.stdoutClosed = true } else { run.stderrClosed = true }
            finalizeIfReady(run)
        }
        publish(run)
    }

    private func launcherExited(projectID: UUID, runID: UUID, exit: ProcessExit?, error: Error?) {
        guard let run = activeRuns[projectID], run.runID == runID else { return }
        run.siteDiscovery?.cancel()
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
            if let identity = run.identity {
                RunJournal.remove(projectID: projectID, identity: identity)
            }
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
        run.siteDiscovery?.cancel()
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
        stateHandler(run.projectID, RunState(id: run.runID, processID: run.identity?.processID, processGroupID: run.identity?.processGroupID, phase: run.phase, logs: snapshot.0, didTruncateLogs: snapshot.1, message: run.message, cleanupError: run.cleanupError, siteState: run.siteDiscoveryState))
    }

    private func actionableMessage(for error: Error) -> String {
        if let projectError = error as? ProjectValidationError { return projectError.localizedDescription }
        if let shellError = error as? ShellEnvironmentError { return shellError.localizedDescription }
        if let launcherError = error as? ProcessLauncherError { return launcherError.localizedDescription }
        return "Could not start the command: \(error.localizedDescription)"
    }
}