import AppKit
import Combine
import Foundation

@MainActor
final class ProjectRunner: ObservableObject {
    @Published private(set) var states: [UUID: RunState] = [:]
    @Published private(set) var isTerminating = false
    @Published private(set) var isRecovering = true
    private var supervisor: ProcessSupervisor!
    private var recoveryTask: Task<Void, Never>?

    init(shellEnvironment: ShellEnvironment? = nil) {
        self.supervisor = ProcessSupervisor(shellEnvironment: shellEnvironment) { [weak self] projectID, state in
            self?.states[projectID] = state
        }
    }

    func state(for projectID: UUID) -> RunState? { states[projectID] }
    var activeProjectIDs: Set<UUID> { supervisor.activeProjectIDs }
    func canStart(projectID: UUID) -> Bool { !isTerminating && !isRecovering && supervisor.canStart(projectID: projectID) }
    func canStop(projectID: UUID) -> Bool { supervisor.canStop(projectID: projectID) }
    func canRemove(projectID: UUID) -> Bool { !isTerminating && supervisor.canRemove(projectID: projectID) }

    func recoverStaleRuns() async {
        guard isRecovering else { return }
        if let recoveryTask {
            await recoveryTask.value
            return
        }
        let task = Task.detached(priority: .utility) {
            RunJournal.recover()
        }
        recoveryTask = task
        await task.value
        recoveryTask = nil
        isRecovering = false
    }

    func beginTermination() -> Bool {
        guard !isTerminating else { return false }
        isTerminating = true
        return true
    }

    func finishTermination(success: Bool) { if !success { isTerminating = false } }

    @discardableResult
    func start(project: Project) -> UUID? {
        guard !isTerminating else { return nil }
        return supervisor.start(project: project)
    }

    func stop(projectID: UUID) { supervisor.stop(projectID: projectID) }

    /// The view supplies only the currently displayed ready site. All freshness,
    /// ownership, and run-identity checks happen again in the facade/supervisor
    /// before this synchronous AppKit call.
    func openWebsite(projectID: UUID, site: LocalSite) async {
        guard !isTerminating,
              let initial = states[projectID], initial.phase == .running,
              initial.siteState.phase == .responding,
              initial.siteState.sites.contains(site), !initial.isOpeningWebsite else { return }
        let runID = initial.id
        let preparation = await supervisor.prepareWebsiteOpening(projectID: projectID, runID: runID, site: site)
        guard case .ready = preparation else {
            supervisor.finishWebsiteOpening(projectID: projectID, runID: runID, error: nil)
            return
        }

        // No await occurs between this last current-run check and NSWorkspace.
        guard !isTerminating,
              let current = states[projectID], current.id == runID,
              current.phase == .running, current.isOpeningWebsite,
              current.siteState.phase == .responding,
              current.siteState.sites.contains(site) else {
            supervisor.finishWebsiteOpening(projectID: projectID, runID: runID, error: nil)
            return
        }
        let opened = NSWorkspace.shared.open(site.candidate.url)
        supervisor.finishWebsiteOpening(
            projectID: projectID,
            runID: runID,
            error: opened ? nil : "The default browser could not open \(site.candidate.absoluteString)."
        )
    }

    func stopAll() async -> Bool { await supervisor.stopAll() }
}

enum ProjectRunnerError: LocalizedError, Sendable {
    case projectBusy

    var errorDescription: String? {
        switch self {
        case .projectBusy: return "This project still has an owned process run. Stop it and wait for cleanup before removing the project."
        }
    }
}
