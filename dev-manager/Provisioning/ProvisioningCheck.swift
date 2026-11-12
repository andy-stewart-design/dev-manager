#if DEBUG
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
            case .node: return "Node \(ProvisioningConfiguration.nodeVersion)"
            case .pnpm: return "pnpm \(ProvisioningConfiguration.pnpmVersion)"
            }
        }
    }

    enum State: Equatable, Sendable {
        case checking
        case waiting(String)
        case unverified(String)
        case ready(String)
        case missing(String)
        case attention(String)

        nonisolated var isReady: Bool {
            if case .ready = self { return true }
            return false
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
    let node: ProvisioningCheck
    let pnpm: ProvisioningCheck
}

nonisolated struct ProvisioningTargetedInspection: Sendable {
    let checks: [ProvisioningCheck]
    let fnmExecutableURL: URL?
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
#endif
