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
            entries.removeAll { $0 == entry }
            entries.append(entry)
        }
    }

    nonisolated static func remove(projectID: UUID, identity: ProcessIdentity) {
        update { entries in
            entries.removeAll {
                $0.projectID == projectID.uuidString &&
                $0.pid == identity.processID && $0.pgid == identity.processGroupID &&
                $0.OSprocessStartTime == identity.startTime
            }
        }
    }

    /// Performs all recovery inspection and bounded signaling away from the main actor.
    nonisolated static func recover() {
        guard var entries = load() else { return }
        var changed = false
        var removedEntries: [RunJournalEntry] = []
        for entry in entries {
            switch inspect(entry) {
            case .drop:
                removedEntries.append(entry)
                changed = true
            case .leave:
                continue
            case .recover:
                switch recover(entry) {
                case .removed:
                    removedEntries.append(entry)
                    changed = true
                case .leave:
                    continue
                }
            }
        }
        if changed {
            entries.removeAll { removedEntries.contains($0) }
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

    private struct RecoveryGroup {
        let pid: Int32
        let pgid: Int32
        let startTime: RunJournalEntry.ProcessStartTime
    }

    private enum GroupDiscovery { case groups([RecoveryGroup]), failed }

    private nonisolated static func recover(_ entry: RunJournalEntry) -> RecoveryResult {
        // This orphan is not our direct child and intentionally never enters
        // ProcessLauncher.stop()/waitpid cleanup. Discover its current descendant
        // tree while the verified launcher root still preserves the ancestry.
        let initialRoot = identityMatches(entry)
        guard initialRoot == .match else {
            return initialRoot == .ambiguous ? .leave : .removed
        }
        guard case let .groups(childGroups) = discoverDescendantGroups(rootPID: entry.pid, rootPGID: entry.pgid) else {
            return .leave
        }
        let beforeChildren = identityMatches(entry)
        guard beforeChildren == .match else {
            return beforeChildren == .ambiguous ? .leave : .removed
        }

        // Recheck the root before child groups, then recheck every captured group
        // leader immediately before each signal. A failed child check is left alone.
        for group in childGroups {
            guard groupIdentityMatches(group) else { continue }
            guard kill(-group.pgid, SIGTERM) == 0 else {
                if errno == ESRCH { continue }
                logger.warning("Could not SIGTERM verified descendant group \(group.pgid): errno \(errno); leaving recovery incomplete")
                return .leave
            }
        }
        let beforeRootTerm = identityMatches(entry)
        guard beforeRootTerm == .match else {
            return beforeRootTerm == .ambiguous ? .leave : .removed
        }
        guard kill(-entry.pgid, SIGTERM) == 0 else {
            if errno == ESRCH { return .removed }
            logger.warning("Could not SIGTERM journal process group \(entry.pgid): errno \(errno); leaving it alone")
            return .leave
        }

        // Preserve the existing finite TERM(2s)/KILL(1s) recovery phases. The
        // launcher root remains the authoritative stale-record identity.
        sleep(2)
        for group in childGroups {
            guard groupIdentityMatches(group) else { continue }
            guard kill(-group.pgid, SIGKILL) == 0 else {
                if errno == ESRCH { continue }
                logger.warning("Could not SIGKILL verified descendant group \(group.pgid): errno \(errno); leaving recovery incomplete")
                return .leave
            }
        }
        let beforeRootKill = identityMatches(entry)
        guard beforeRootKill == .match else {
            return beforeRootKill == .ambiguous ? .leave : .removed
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

    private nonisolated static func discoverDescendantGroups(rootPID: Int32, rootPGID: Int32) -> GroupDiscovery {
        var pending = [rootPID]
        var visited = Set<Int32>()
        var groups = [Int32: RecoveryGroup]()
        let maximumDescendants = 4096

        while let parent = pending.popLast() {
            guard visited.insert(parent).inserted else { continue }
            if visited.count > maximumDescendants {
                logger.warning("Journal descendant inspection exceeded its bounded process limit; leaving recovery alone")
                return .failed
            }
            var children = [pid_t](repeating: 0, count: 256)
            let result = children.withUnsafeMutableBufferPointer { buffer in
                dm_process_children(parent, buffer.baseAddress, buffer.count)
            }
            guard result >= 0 else {
                logger.warning("Could not inspect descendants of journal PID \(parent): errno \(-result); leaving recovery alone")
                return .failed
            }
            for child in children.prefix(Int(result)) where child > 0 {
                var currentGroup: pid_t = 0
                var seconds: UInt64 = 0
                var micros: UInt32 = 0
                let identityResult = dm_process_identity(child, &currentGroup, &seconds, &micros)
                if identityResult < 0 {
                    logger.warning("Could not inspect journal descendant PID \(child): errno \(-identityResult); leaving recovery alone")
                    return .failed
                }
                guard identityResult == 1 else { continue }
                if child == currentGroup, currentGroup != rootPGID {
                    groups[currentGroup] = RecoveryGroup(
                        pid: child,
                        pgid: currentGroup,
                        startTime: RunJournalEntry.ProcessStartTime(seconds: seconds, microseconds: micros)
                    )
                }
                pending.append(child)
            }
        }
        return .groups(Array(groups.values))
    }

    private nonisolated static func groupIdentityMatches(_ group: RecoveryGroup) -> Bool {
        var currentGroup: pid_t = 0
        var seconds: UInt64 = 0
        var micros: UInt32 = 0
        let result = dm_process_identity(group.pid, &currentGroup, &seconds, &micros)
        return result == 1 && currentGroup == group.pgid &&
            seconds == group.startTime.seconds && micros == group.startTime.microseconds
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
