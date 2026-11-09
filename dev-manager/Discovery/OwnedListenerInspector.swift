import Darwin
import Foundation

nonisolated struct OwnedListenerInspection: Sendable {
    let processes: [OwnedProcessIdentitySnapshot]
    let listeners: [LocalSiteListener]
}

nonisolated enum OwnedListenerInspectionError: LocalizedError, Sendable {
    case invalidRoot
    case ambiguousRoot(String)
    case descendantInspectionFailed(String)
    case lsofMissing(String)
    case lsofFailed(String)
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            return "The managed process identity is no longer valid; no listener was attributed."
        case let .ambiguousRoot(message):
            return "The managed process could not be safely inspected: \(message)"
        case let .descendantInspectionFailed(message):
            return "Owned descendant inspection failed: \(message)"
        case let .lsofMissing(path):
            return "The listener inspection tool is missing at \(path)."
        case let .lsofFailed(message):
            return "Listener inspection failed: \(message)"
        case .timedOut:
            return "Owned listener inspection timed out."
        case .cancelled:
            return "Owned listener inspection was cancelled."
        }
    }
}

/// Synchronous, off-main-actor inspection of one managed process tree. Callers
/// should invoke this from detached work; this type never starts or stops the
/// managed process itself.
nonisolated enum OwnedListenerInspector {
    private static let lsofPath = "/usr/sbin/lsof"
    private static let maximumProcesses = 4096
    private static let childBufferCapacity = 256
    private static let maximumLsofOutput = 2 * 1024 * 1024

    static func inspect(
        rootProcessIdentity: ProcessIdentity,
        timeout: TimeInterval = 2,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> OwnedListenerInspection {
        guard rootMatches(rootProcessIdentity) else { throw OwnedListenerInspectionError.invalidRoot }
        if shouldCancel() { throw OwnedListenerInspectionError.cancelled }

        let processes = try captureProcessTree(root: rootProcessIdentity, shouldCancel: shouldCancel)
        let pids = processes.map(\.processID)
        guard !pids.isEmpty else { throw OwnedListenerInspectionError.invalidRoot }
        let output = try runLsof(pids: pids, timeout: timeout, shouldCancel: shouldCancel)

        // A root that exits or is replaced while lsof is running invalidates the
        // complete result. Never publish a partial or port-only attribution.
        guard rootMatches(rootProcessIdentity) else { throw OwnedListenerInspectionError.invalidRoot }
        var currentByPID: [Int32: OwnedProcessIdentitySnapshot] = [:]
        for snapshot in processes {
            if let current = currentSnapshot(for: snapshot.processID), current == snapshot {
                currentByPID[snapshot.processID] = snapshot
            }
        }

        let listeners = parseListeners(output, owners: currentByPID)
        if shouldCancel() { throw OwnedListenerInspectionError.cancelled }
        return OwnedListenerInspection(processes: Array(currentByPID.values), listeners: listeners)
    }

    /// Read-only last-moment identity check for a previously published listener.
    static func revalidate(listener: LocalSiteListener) -> Bool {
        guard let current = currentSnapshot(for: listener.owner.processID) else { return false }
        return current == listener.owner
    }

    static func ownsMatchingPort(_ listener: LocalSiteListener, candidate: LocalURLCandidate) -> Bool {
        listener.matches(candidate)
    }

    private static func captureProcessTree(
        root: ProcessIdentity,
        shouldCancel: @Sendable () -> Bool
    ) throws -> [OwnedProcessIdentitySnapshot] {
        var pending = [root.processID]
        var visited = Set<Int32>()
        var snapshots: [OwnedProcessIdentitySnapshot] = []

        while let parent = pending.popLast() {
            guard visited.insert(parent).inserted else { continue }
            if visited.count > maximumProcesses {
                throw OwnedListenerInspectionError.descendantInspectionFailed("the process tree exceeded its bounded inspection limit")
            }
            if shouldCancel() { throw OwnedListenerInspectionError.cancelled }

            if parent == root.processID {
                guard rootMatches(root) else { throw OwnedListenerInspectionError.invalidRoot }
                snapshots.append(OwnedProcessIdentitySnapshot(root))
            } else if let snapshot = currentSnapshot(for: parent) {
                snapshots.append(snapshot)
            }

            var children = [pid_t](repeating: 0, count: childBufferCapacity)
            let result = children.withUnsafeMutableBufferPointer { buffer in
                dm_process_children(parent, buffer.baseAddress, buffer.count)
            }
            if result == -EOVERFLOW {
                throw OwnedListenerInspectionError.descendantInspectionFailed("too many direct children to inspect safely")
            }
            guard result >= 0 else {
                throw OwnedListenerInspectionError.descendantInspectionFailed("could not enumerate children of PID \(parent) (errno \(-result))")
            }
            for child in children.prefix(Int(result)) where child > 0 {
                // A stale child is normal during a scan. An ambiguous child is not
                // allowed to turn an unknown PID into an owned listener.
                var group: pid_t = 0
                var seconds: UInt64 = 0
                var micros: UInt32 = 0
                let identityResult = dm_process_identity(child, &group, &seconds, &micros)
                if identityResult == 0 { continue }
                guard identityResult == 1 else {
                    throw OwnedListenerInspectionError.descendantInspectionFailed("PID \(child) identity was ambiguous (errno \(-identityResult))")
                }
                pending.append(child)
            }
        }
        return snapshots
    }

    private static func rootMatches(_ expected: ProcessIdentity) -> Bool {
        guard let actual = currentSnapshot(for: expected.processID) else { return false }
        return actual.processGroupID == expected.processGroupID && actual.startTime == expected.startTime
    }

    private static func currentSnapshot(for processID: Int32) -> OwnedProcessIdentitySnapshot? {
        var group: pid_t = 0
        var seconds: UInt64 = 0
        var micros: UInt32 = 0
        guard dm_process_identity(processID, &group, &seconds, &micros) == 1 else { return nil }
        return OwnedProcessIdentitySnapshot(
            processID: processID,
            processGroupID: group,
            startTime: RunJournalEntry.ProcessStartTime(seconds: seconds, microseconds: micros)
        )
    }

    private static func runLsof(
        pids: [Int32],
        timeout: TimeInterval,
        shouldCancel: @Sendable () -> Bool
    ) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else {
            throw OwnedListenerInspectionError.lsofMissing(lsofPath)
        }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-nP", "-a", "-p", pids.map(String.init).joined(separator: ","),
                             "-iTCP", "-sTCP:LISTEN", "-F0pfnT"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputQueue = DispatchQueue(label: "dev-manager.discovery.lsof.stdout")
        let errorQueue = DispatchQueue(label: "dev-manager.discovery.lsof.stderr")
        let drainGroup = DispatchGroup()
        var stdout = Data()
        var stderr = Data()
        drainGroup.enter()
        outputQueue.async {
            stdout = Self.drain(outputPipe.fileHandleForReading, maximum: maximumLsofOutput)
            drainGroup.leave()
        }
        drainGroup.enter()
        errorQueue.async {
            stderr = Self.drain(errorPipe.fileHandleForReading, maximum: 64 * 1024)
            drainGroup.leave()
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            _ = drainGroup.wait(timeout: .now() + 1)
            throw OwnedListenerInspectionError.lsofMissing(lsofPath)
        }

        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        while process.isRunning {
            if shouldCancel() {
                terminateHelper(process)
                _ = drainGroup.wait(timeout: .now() + 1)
                throw OwnedListenerInspectionError.cancelled
            }
            if Date() >= deadline {
                terminateHelper(process)
                _ = drainGroup.wait(timeout: .now() + 1)
                throw OwnedListenerInspectionError.timedOut
            }
            usleep(20_000)
        }
        process.waitUntilExit()
        _ = drainGroup.wait(timeout: .now() + 1)

        if process.terminationStatus == 1 && stdout.isEmpty {
            // lsof uses status 1 for no matching open files. This is a normal
            // no-listener result; stderr is intentionally not promoted to a site.
            return Data()
        }
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OwnedListenerInspectionError.lsofFailed(detail.isEmpty ? "exit status \(process.terminationStatus)" : detail)
        }
        return stdout
    }

    private static func terminateHelper(_ process: Process) {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(0.25)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private static func drain(_ handle: FileHandle, maximum: Int) -> Data {
        var result = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if result.count < maximum {
                result.append(chunk.prefix(maximum - result.count))
            }
        }
        return result
    }

    private static func parseListeners(_ data: Data, owners: [Int32: OwnedProcessIdentitySnapshot]) -> [LocalSiteListener] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var pid: Int32?
        var listeners = Set<LocalSiteListener>()
        for fieldData in fields {
            let field = String(decoding: fieldData, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            guard let prefix = field.first else { continue }
            let value = String(field.dropFirst())
            if prefix == "p" {
                pid = Int32(value)
            } else if prefix == "n", let pid, let owner = owners[pid],
                      let endpoint = parseEndpoint(value) {
                listeners.insert(LocalSiteListener(owner: owner, port: endpoint.port, bindHost: endpoint.host))
            }
        }
        return listeners.sorted { ($0.port, $0.bindHost, $0.owner.processID) < ($1.port, $1.bindHost, $1.owner.processID) }
    }

    private static func parseEndpoint(_ value: String) -> (host: String, port: Int)? {
        let address: String
        let portText: String
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            address = String(value[value.index(after: value.startIndex)..<close])
            let after = value.index(after: close)
            guard after < value.endIndex, value[after] == ":" else { return nil }
            portText = String(value[value.index(after: after)...])
        } else {
            guard let colon = value.lastIndex(of: ":") else { return nil }
            address = String(value[..<colon])
            portText = String(value[value.index(after: colon)...])
        }
        guard let port = Int(portText), (1...65_535).contains(port) else { return nil }
        let host: String
        switch address.lowercased() {
        case "*", "0.0.0.0": host = "127.0.0.1"
        case "::": host = "::1"
        case "127.0.0.1": host = "127.0.0.1"
        case "::1": host = "::1"
        default: return nil
        }
        return (host, port)
    }
}
