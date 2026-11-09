import Foundation

/// A process identity captured while inspecting a managed run.  It is deliberately
/// a value snapshot: a recycled PID can never compare equal to this value.
nonisolated struct OwnedProcessIdentitySnapshot: Hashable, Sendable {
    let processID: Int32
    let processGroupID: Int32
    let startTime: RunJournalEntry.ProcessStartTime

    init(processID: Int32, processGroupID: Int32, startTime: RunJournalEntry.ProcessStartTime) {
        self.processID = processID
        self.processGroupID = processGroupID
        self.startTime = startTime
    }

    init(_ identity: ProcessIdentity) {
        self.init(processID: identity.processID, processGroupID: identity.processGroupID,
                  startTime: identity.startTime)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(processID)
        hasher.combine(processGroupID)
        hasher.combine(startTime.seconds)
        hasher.combine(startTime.microseconds)
    }
}

/// A TCP listener attributed to one captured process identity.
nonisolated struct LocalSiteListener: Hashable, Sendable {
    let owner: OwnedProcessIdentitySnapshot
    let port: Int
    /// Always a loopback destination. Wildcard binds are normalized to a loopback
    /// address and are never exposed as 0.0.0.0 or ::.
    let bindHost: String

    init(owner: OwnedProcessIdentitySnapshot, port: Int, bindHost: String) {
        self.owner = owner
        self.port = port
        self.bindHost = bindHost
    }

    func matches(_ candidate: LocalURLCandidate) -> Bool {
        let effectivePort = candidate.port ?? (candidate.scheme == "https" ? 443 : 80)
        guard effectivePort == port else { return false }
        let host = candidate.host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return host == "localhost" || host == bindHost.lowercased()
    }
}

/// A local URL and the owned listener that justified it, when one is available.
/// This is discovery data, not a readiness or browser-action state.
nonisolated struct LocalSite: Hashable, Sendable {
    let candidate: LocalURLCandidate
    let listener: LocalSiteListener?

    init(candidate: LocalURLCandidate, listener: LocalSiteListener? = nil) {
        self.candidate = candidate
        self.listener = listener
    }
}

/// Website discovery is intentionally separate from the command lifecycle. A
/// running command may have no website, and a responding website never changes
/// the process phase.
nonisolated enum SiteDiscoveryPhase: Equatable, Sendable {
    case inactive
    case discovering
    case responding
    case noSite
    case diagnostic(String)
}

nonisolated struct SiteDiscoveryState: Equatable, Sendable {
    let phase: SiteDiscoveryPhase
    let sites: [LocalSite]

    static let inactive = SiteDiscoveryState(phase: .inactive, sites: [])
    static let discovering = SiteDiscoveryState(phase: .discovering, sites: [])

    init(phase: SiteDiscoveryPhase, sites: [LocalSite] = []) {
        self.phase = phase
        self.sites = sites
    }
}
