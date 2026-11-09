import Foundation

/// The lifecycle of the current command. Website/discovery state deliberately does not live here.
enum RunPhase: Equatable, Sendable {
    case launching
    case running
    case stopping
    case exited
    case failed

    var title: String {
        switch self {
        case .launching: return "Launching"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .exited: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

enum RunOutputStream: String, Sendable {
    case stdout
    case stderr
}

enum RunOutputPhase: String, Sendable {
    case shellInitialization = "shell"
    case command = "command"
}

struct RunLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let runID: UUID
    let stream: RunOutputStream
    let phase: RunOutputPhase
    let text: String

    init(id: UUID = UUID(), runID: UUID, stream: RunOutputStream, phase: RunOutputPhase, text: String) {
        self.id = id
        self.runID = runID
        self.stream = stream
        self.phase = phase
        self.text = text
    }

    var label: String {
        "\(runID.uuidString.prefix(8)) \(stream.rawValue)/\(phase.rawValue)"
    }
}

struct RunState: Identifiable, Equatable, Sendable {
    let id: UUID
    let processID: Int32?
    let processGroupID: Int32?
    let phase: RunPhase
    let logs: [RunLogEntry]
    let didTruncateLogs: Bool
    let message: String?
    let cleanupError: String?
    let siteState: SiteDiscoveryState

    init(id: UUID, processID: Int32?, processGroupID: Int32?, phase: RunPhase,
         logs: [RunLogEntry], didTruncateLogs: Bool, message: String?, cleanupError: String?,
         siteState: SiteDiscoveryState = .inactive) {
        self.id = id
        self.processID = processID
        self.processGroupID = processGroupID
        self.phase = phase
        self.logs = logs
        self.didTruncateLogs = didTruncateLogs
        self.message = message
        self.cleanupError = cleanupError
        self.siteState = siteState
    }

    var isActive: Bool {
        switch phase {
        case .launching, .running, .stopping: return true
        case .exited, .failed: return false
        }
    }

    static func initial(runID: UUID, processID: Int32, processGroupID: Int32) -> RunState {
        RunState(
            id: runID,
            processID: processID,
            processGroupID: processGroupID,
            phase: .launching,
            logs: [],
            didTruncateLogs: false,
            message: "Initializing zsh login/interactive environment…",
            cleanupError: nil
        )
    }

    static func pending(runID: UUID, message: String?) -> RunState {
        RunState(
            id: runID,
            processID: nil,
            processGroupID: nil,
            phase: .launching,
            logs: [],
            didTruncateLogs: false,
            message: message,
            cleanupError: nil
        )
    }
}
