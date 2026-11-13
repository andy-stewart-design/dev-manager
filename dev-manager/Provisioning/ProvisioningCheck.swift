import Foundation

nonisolated struct ProvisioningCheck: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Identifiable, Sendable {
        case developerTools
        case homebrew
        case fnm
        case node
        case pnpm

        nonisolated var id: String { rawValue }

        nonisolated var title: String {
            switch self {
            case .developerTools: return "Apple developer tools"
            case .homebrew: return "Homebrew"
            case .fnm: return "Fast Node Manager (fnm)"
            case .node: return "Node"
            case .pnpm: return "pnpm"
            }
        }
    }

    enum State: Equatable, Sendable {
        case checking
        case waiting(String)
        case unverified(String)
        case ready(String)
        case notRequired(String)
        case missing(String)
        case attention(String)

        nonisolated var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        nonisolated var isSatisfied: Bool {
            switch self {
            case .ready, .notRequired: return true
            default: return false
            }
        }

        nonisolated var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }

        nonisolated var isUnverified: Bool {
            if case .unverified = self { return true }
            return false
        }
    }

    let id: ID
    let state: State

    /// Ready rows use the concrete version reported by the selected context;
    /// missing and attention rows intentionally retain the generic tool title.
    nonisolated var rowTitle: String {
        guard case let .ready(detail) = state, id == .node || id == .pnpm,
              let first = detail.firstNonEmptyLine else { return id.title }
        return first.split(separator: ";", maxSplits: 1).first.map(String.init) ?? id.title
    }

    nonisolated static var all: [ProvisioningCheck] {
        ID.allCases.map { ProvisioningCheck(id: $0, state: .checking) }
    }
}

nonisolated struct ProvisioningInspection: Sendable {
    let developerTools: ProvisioningCheck
    let developerToolsExecutableURL: URL?
    let homebrew: ProvisioningCheck
    let fnm: ProvisioningCheck
    let fnmExecutableURL: URL?
    let chosenFNMDirectoryURL: URL?
    let node: ProvisioningCheck
    let pnpm: ProvisioningCheck
    let runtimeContext: ProvisioningRuntimeContext?

    nonisolated init(
        developerTools: ProvisioningCheck,
        developerToolsExecutableURL: URL?,
        homebrew: ProvisioningCheck,
        fnm: ProvisioningCheck,
        fnmExecutableURL: URL?,
        chosenFNMDirectoryURL: URL?,
        node: ProvisioningCheck,
        pnpm: ProvisioningCheck,
        runtimeContext: ProvisioningRuntimeContext?
    ) {
        self.developerTools = developerTools
        self.developerToolsExecutableURL = developerToolsExecutableURL
        self.homebrew = homebrew
        self.fnm = fnm
        self.fnmExecutableURL = fnmExecutableURL
        self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
        self.node = node
        self.pnpm = pnpm
        self.runtimeContext = runtimeContext
    }
}

nonisolated struct ProvisioningTargetedInspection: Sendable {
    let checks: [ProvisioningCheck]
    let fnmExecutableURL: URL?
    let chosenFNMDirectoryURL: URL?
    let runtimeContext: ProvisioningRuntimeContext?

    nonisolated init(
        checks: [ProvisioningCheck],
        fnmExecutableURL: URL?,
        chosenFNMDirectoryURL: URL? = nil,
        runtimeContext: ProvisioningRuntimeContext?
    ) {
        self.checks = checks
        self.fnmExecutableURL = fnmExecutableURL
        self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
        self.runtimeContext = runtimeContext
    }
}

extension String {
    nonisolated var firstNonEmptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    nonisolated func containsToken(_ expected: String) -> Bool {
        components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            .contains(expected)
    }
}
