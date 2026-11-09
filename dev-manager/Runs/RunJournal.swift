import Darwin
import Foundation
import OSLog

/// A deliberately small, warning-only journal for the one supported app instance.
/// Concurrent app instances are unsupported; this is not a lock or an ownership marker.
nonisolated struct RunJournalEntry: Codable, Sendable, Equatable {
    nonisolated struct ProcessStartTime: Codable, Sendable, Equatable {
        let seconds: UInt64
        let microseconds: UInt32
    }

    let projectID: String
    let pid: Int32
    let pgid: Int32
    let OSprocessStartTime: ProcessStartTime
}

nonisolated enum RunJournal {
    private static let logger = Logger(subsystem: "design.andystew.dev-manager", category: "RunJournal")

    nonisolated static func journalURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dev Manager", isDirectory: true)
            .appendingPathComponent("runs.json", isDirectory: false)
    }

    nonisolated static func record(projectID: UUID, identity: ProcessIdentity) {
        let entry = RunJournalEntry(
            projectID: projectID.uuidString,
            pid: identity.processID,
            pgid: identity.processGroupID,
            OSprocessStartTime: identity.startTime
        )
        update { entries in
            entries.removeAll { $0.projectID == entry.projectID }
            entries.append(entry)
        }
    }

    nonisolated static func remove(projectID: UUID) {
        update { entries in entries.removeAll { $0.projectID == projectID.uuidString } }
    }

    /// Performs all recovery inspection and bounded signaling away from the main actor.
    nonisolated static func recover() {
        guard var entries = load() else { return }
        var changed = false
        var removedProjectIDs = Set<String>()
        for entry in entries {
            switch inspect(entry) {
            case .drop:
                removedProjectIDs.insert(entry.projectID)
                changed = true
            case .leave:
                continue
            case .recover:
                switch recover(entry) {
                case .removed:
                    removedProjectIDs.insert(entry.projectID)
                    changed = true
                case .leave:
                    continue
                }
            }
        }
        if changed {
            entries.removeAll { removedProjectIDs.contains($0.projectID) }
            save(entries)
        }
    }

    private enum Inspection { case drop, leave, recover }
    private enum RecoveryResult { case removed, leave }

    private nonisolated static func inspect(_ entry: RunJournalEntry) -> Inspection {
        guard entry.pid > 0, entry.pgid > 0 else { return .drop }
        switch identityMatches(entry) {
        case .match: return .recover
        case .stale: return .drop
        case .ambiguous: return .leave
        }
    }

    private enum IdentityResult { case match, stale, ambiguous }

    private nonisolated static func identityMatches(_ entry: RunJournalEntry) -> IdentityResult {
        var currentGroup: pid_t = 0
        var seconds: UInt64 = 0
        var micros: UInt32 = 0
        let result = dm_process_identity(entry.pid, &currentGroup, &seconds, &micros)
        guard result >= 0 else {
            logger.warning("Could not inspect journal PID \(entry.pid): errno \(-result); leaving process alone")
            return .ambiguous
        }
        guard result == 1 else { return .stale }
        guard seconds == entry.OSprocessStartTime.seconds,
              micros == entry.OSprocessStartTime.microseconds else { return .stale }
        guard entry.pid == entry.pgid, currentGroup == entry.pgid else {
            logger.warning("Journal PID \(entry.pid) is not leader of recorded PGID \(entry.pgid); leaving process alone")
            return .ambiguous
        }
        return .match
    }

    private nonisolated static func recover(_ entry: RunJournalEntry) -> RecoveryResult {
        // Recheck immediately before every signal. This orphan is not our child and
        // intentionally never enters ProcessLauncher.stop()/waitpid cleanup.
        let beforeTerm = identityMatches(entry)
        guard beforeTerm == .match else {
            if case .ambiguous = beforeTerm { return .leave }
            return .removed
        }
        guard kill(-entry.pgid, SIGTERM) == 0 else {
            if errno == ESRCH { return .removed }
            logger.warning("Could not SIGTERM journal process group \(entry.pgid): errno \(errno); leaving it alone")
            return .leave
        }

        // A leader exiting after SIGTERM is the deliberate dead-leader case: stop
        // escalating and drop the record rather than killing a bare reused PGID.
        sleep(2)
        let afterTerm = identityMatches(entry)
        guard afterTerm == .match else {
            if afterTerm == .stale { return .removed }
            return .leave
        }
        guard kill(-entry.pgid, SIGKILL) == 0 else {
            if errno == ESRCH { return .removed }
            logger.warning("Could not SIGKILL journal process group \(entry.pgid): errno \(errno); leaving it alone")
            return .leave
        }
        sleep(1)
        switch identityMatches(entry) {
        case .stale: return .removed
        case .match:
            logger.warning("Journal process group \(entry.pgid) remains after SIGKILL; retaining record")
            return .leave
        case .ambiguous: return .leave
        }
    }

    private nonisolated static func load() -> [RunJournalEntry]? {
        let url = journalURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([RunJournalEntry].self, from: Data(contentsOf: url))
        } catch {
            logger.error("Run journal could not be read; leaving it untouched: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func update(_ change: (inout [RunJournalEntry]) -> Void) {
        guard var entries = load() else { return }
        change(&entries)
        save(entries)
    }

    private nonisolated static func save(_ entries: [RunJournalEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            let url = journalURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Run journal write failed; project settings and processes were not changed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
