import Combine
import Foundation

@MainActor
final class ProjectRunner: ObservableObject {
    @Published private(set) var states: [UUID: RunState] = [:]
    @Published private(set) var isTerminating = false
    private var supervisor: ProcessSupervisor!

    init(shellEnvironment: ShellEnvironment? = nil) {
        self.supervisor = ProcessSupervisor(shellEnvironment: shellEnvironment) { [weak self] projectID, state in
            self?.states[projectID] = state
        }
    }

    func state(for projectID: UUID) -> RunState? { states[projectID] }
    var activeProjectIDs: Set<UUID> { supervisor.activeProjectIDs }
    func canStart(projectID: UUID) -> Bool { !isTerminating && supervisor.canStart(projectID: projectID) }
    func canStop(projectID: UUID) -> Bool { supervisor.canStop(projectID: projectID) }
    func canRemove(projectID: UUID) -> Bool { !isTerminating && supervisor.canRemove(projectID: projectID) }

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
