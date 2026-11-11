#if DEBUG
import Darwin
import Foundation

nonisolated struct ProvisioningProcessResult: Sendable {
    let succeeded: Bool
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let timedOut: Bool
}

extension ProvisioningProcessResult {
    nonisolated func failureDescription(for command: String, timeout: TimeInterval) -> String {
        if timedOut {
            return "\(command) timed out after \(Int(timeout)) seconds"
        }
        let detail = stderr.firstNonEmptyLine ?? stdout.firstNonEmptyLine ?? "exit status \(terminationStatus)"
        return "\(command) failed: \(detail)"
    }
}

nonisolated private enum ProvisioningProcessError: LocalizedError, Sendable {
    case pipeFailed(String)
    case spawnFailed(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .pipeFailed(detail): return "Could not create provisioning output pipes: \(detail)"
        case let .spawnFailed(detail): return "Could not launch the provisioning command: \(detail)"
        }
    }
}

nonisolated private final class ProvisioningOutputCollector: @unchecked Sendable {
    private static let maximumBytes = 12_000
    private let lock = NSLock()
    private var stdoutStorage = ""
    private var stderrStorage = ""

    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutStorage
    }

    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrStorage
    }

    func append(_ data: Data, stream: OutputStream) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        defer { lock.unlock() }
        switch stream {
        case .stdout:
            stdoutStorage = boundedTail(stdoutStorage + text)
        case .stderr:
            stderrStorage = boundedTail(stderrStorage + text)
        }
    }

    private func boundedTail(_ text: String) -> String {
        guard text.utf8.count > Self.maximumBytes else { return text }
        return String(decoding: Array(text.utf8.suffix(Self.maximumBytes)), as: UTF8.self)
    }

    enum OutputStream {
        case stdout
        case stderr
    }
}

nonisolated private final class ProvisioningDrainCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

nonisolated enum ProvisioningCommandRunner {
    /// The timeout is an internal injection point for deterministic DEBUG tests. Production
    /// checks use the eight-second policy; installers use their separate fifteen-minute policy.
    nonisolated static func run(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = ProvisioningConfiguration.commandTimeout
    ) async -> ProvisioningProcessResult {
        let mergedEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runSynchronously(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: mergedEnvironment,
                    label: nil,
                    timeout: timeout
                ))
            }
        }
    }

    nonisolated static func runInstallProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        label: String
    ) async -> ProvisioningProcessResult {
        let mergedEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runSynchronously(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: mergedEnvironment,
                    label: label,
                    timeout: ProvisioningConfiguration.installTimeout
                ))
            }
        }
    }

    private nonisolated static func runSynchronously(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        label: String?,
        timeout: TimeInterval
    ) -> ProvisioningProcessResult {
        let spawned: ProvisioningSpawn
        do {
            spawned = try spawnProcess(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment
            )
        } catch {
            return ProvisioningProcessResult(
                succeeded: false,
                stdout: "",
                stderr: label.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription,
                terminationStatus: -1,
                timedOut: false
            )
        }

        let collector = ProvisioningOutputCollector()
        let cancellation = ProvisioningDrainCancellation()
        let drains = DispatchGroup()
        drains.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(spawned.stdout, into: collector, stream: .stdout, cancellation: cancellation)
            drains.leave()
        }
        drains.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(spawned.stderr, into: collector, stream: .stderr, cancellation: cancellation)
            drains.leave()
        }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        var leaderExited = false
        var outputCollected = false
        while Date() < deadline {
            if !leaderExited { leaderExited = hasObservedExit(spawned.processID) }
            outputCollected = drains.wait(timeout: .now()) == .success
            if leaderExited && outputCollected { break }
            usleep(20_000)
        }
        if !leaderExited { leaderExited = hasObservedExit(spawned.processID) }
        outputCollected = drains.wait(timeout: .now()) == .success

        var timedOut = !leaderExited || !outputCollected
        if timedOut {
            collector.append(Data("\nTimed out; terminating the provisioning process group.\n".utf8), stream: .stderr)
        }

        // Cleanup is always finite. On the timeout path it also closes descendants' inherited
        // pipe writers, allowing the drain workers to finish and preserving whatever tail exists.
        // The process-group cleanup is intentionally scoped to this spawned group; a detached
        // setsid descendant is not tracked or chased. Drain cancellation still bounds capture
        // even if such a process retains an inherited pipe writer.
        let groupWasClean = cleanupProcessGroup(
            processID: spawned.processID,
            grace: ProvisioningConfiguration.processCleanupGrace
        )
        if !groupWasClean { timedOut = true }

        if !outputCollected {
            if drains.wait(timeout: .now() + ProvisioningConfiguration.processCleanupGrace) == .success {
                outputCollected = true
            } else {
                cancellation.cancel()
                _ = drains.wait(timeout: .now() + ProvisioningConfiguration.processDrainCancellationGrace)
            }
        }
        if !outputCollected { timedOut = true }

        guard let status = reapProcess(
            spawned.processID,
            timeout: ProvisioningConfiguration.processCleanupGrace
        ) else {
            timedOut = true
            return ProvisioningProcessResult(
                succeeded: false,
                stdout: collector.stdout,
                stderr: collector.stderr,
                terminationStatus: -1,
                timedOut: true
            )
        }

        let terminationStatus = exitCode(status)
        return ProvisioningProcessResult(
            succeeded: !timedOut && outputCollected && groupWasClean && terminationStatus == 0,
            stdout: collector.stdout,
            stderr: collector.stderr,
            terminationStatus: terminationStatus,
            timedOut: timedOut
        )
    }

    private nonisolated struct ProvisioningSpawn: Sendable {
        let processID: Int32
        let stdout: Int32
        let stderr: Int32
    }

    private nonisolated static func spawnProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProvisioningSpawn {
        let stdoutPipe = try makePipe()
        let stderrPipe: (read: Int32, write: Int32)
        do {
            stderrPipe = try makePipe()
        } catch {
            close(stdoutPipe.read)
            close(stdoutPipe.write)
            throw error
        }

        let stdinFD = open("/dev/null", O_RDONLY)
        guard stdinFD >= 0 else {
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw ProvisioningProcessError.spawnFailed("/dev/null: \(String(cString: strerror(errno)))")
        }
        let normalizedStdin: Int32
        do {
            normalizedStdin = try normalizeDescriptor(stdinFD)
        } catch {
            // normalizeDescriptor leaves the original open when duplication fails.
            // Close it here; successful normalization has already closed the original.
            close(stdinFD)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw error
        }

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw ProvisioningProcessError.spawnFailed("could not initialize file actions")
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw ProvisioningProcessError.spawnFailed("could not initialize process-group attributes")
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        func closeParentDescriptors() {
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
        }

        let flags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, normalizedStdin, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdoutPipe.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderrPipe.write, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, normalizedStdin) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.write) == 0,
              posix_spawn_file_actions_addclose(&actions, stderrPipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stderrPipe.write) == 0 else {
            closeParentDescriptors()
            throw ProvisioningProcessError.spawnFailed("could not configure the provisioning process group or output streams")
        }

        let commandArguments = [executableURL.path] + arguments
        var argv = commandArguments.map { strdup($0) }
        argv.append(nil)
        defer { argv.compactMap { $0 }.forEach { free($0) } }
        var envp = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.compactMap { $0 }.forEach { free($0) } }

        var processID: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envBuffer in
                posix_spawn(
                    &processID,
                    executableURL.path,
                    &actions,
                    &attributes,
                    argvBuffer.baseAddress,
                    envBuffer.baseAddress
                )
            }
        }
        close(normalizedStdin)
        close(stdoutPipe.write)
        close(stderrPipe.write)
        guard result == 0 else {
            close(stdoutPipe.read)
            close(stderrPipe.read)
            throw ProvisioningProcessError.spawnFailed(String(cString: strerror(result)))
        }

        guard setNonBlocking(stdoutPipe.read), setNonBlocking(stderrPipe.read) else {
            _ = kill(-processID, SIGKILL)
            _ = reapProcess(processID, timeout: ProvisioningConfiguration.processCleanupGrace)
            close(stdoutPipe.read); close(stderrPipe.read)
            throw ProvisioningProcessError.spawnFailed("could not configure nonblocking output streams")
        }
        return ProvisioningSpawn(processID: processID, stdout: stdoutPipe.read, stderr: stderrPipe.read)
    }

    private nonisolated static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds = [Int32](repeating: -1, count: 2)
        guard pipe(&fds) == 0 else {
            throw ProvisioningProcessError.pipeFailed(String(cString: strerror(errno)))
        }
        do {
            fds[0] = try normalizeDescriptor(fds[0])
            fds[1] = try normalizeDescriptor(fds[1])
            return (fds[0], fds[1])
        } catch {
            if fds[0] >= 0 { close(fds[0]) }
            if fds[1] >= 0 { close(fds[1]) }
            throw error
        }
    }

    private nonisolated static func normalizeDescriptor(_ descriptor: Int32) throws -> Int32 {
        guard descriptor < 3 else { return descriptor }
        let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        guard replacement >= 0 else {
            throw ProvisioningProcessError.pipeFailed("could not protect file descriptor: \(String(cString: strerror(errno)))")
        }
        close(descriptor)
        return replacement
    }

    private nonisolated static func setNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private nonisolated static func hasObservedExit(_ processID: Int32) -> Bool {
        var info = siginfo_t()
        while true {
            let result = waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0 { return info.si_pid != 0 }
            if errno == EINTR { continue }
            return false
        }
    }

    private nonisolated static func cleanupProcessGroup(processID: Int32, grace: TimeInterval) -> Bool {
        // dm_group_has_non_zombie_members intentionally excludes its leader. Keep the
        // owned leader as the group anchor until it is dead, otherwise a timed-out
        // leader with no children would receive no signal and cleanup could claim success.
        let hasLiveOwnedProcess = {
            hasLiveLeader(processID: processID) || dm_group_has_non_zombie_members(processID, processID) != 0
        }
        guard hasLiveOwnedProcess() else { return true }
        _ = kill(-processID, SIGTERM)
        let termDeadline = Date().addingTimeInterval(grace)
        while hasLiveOwnedProcess() && Date() < termDeadline { usleep(50_000) }
        if hasLiveOwnedProcess() {
            _ = kill(-processID, SIGKILL)
            let killDeadline = Date().addingTimeInterval(grace)
            while hasLiveOwnedProcess() && Date() < killDeadline { usleep(50_000) }
        }
        return !hasLiveOwnedProcess()
    }

    private nonisolated static func hasLiveLeader(processID: Int32) -> Bool {
        var groupID: pid_t = 0
        var startSeconds: UInt64 = 0
        var startMicroseconds: UInt32 = 0
        // A negative inspection result is conservatively live/unknown: cleanup must
        // not return success while ownership of the unreaped leader is uncertain.
        return dm_process_identity(
            processID,
            &groupID,
            &startSeconds,
            &startMicroseconds
        ) != 0
    }

    private nonisolated static func reapProcess(_ processID: Int32, timeout: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while Date() < deadline {
            let result = waitpid(processID, &status, WNOHANG)
            if result == processID { return status }
            if result < 0, errno != EINTR { return nil }
            usleep(50_000)
        }
        return nil
    }

    private nonisolated static func exitCode(_ status: Int32) -> Int32 {
        (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
    }

    private nonisolated static func drain(
        _ descriptor: Int32,
        into collector: ProvisioningOutputCollector,
        stream: ProvisioningOutputCollector.OutputStream,
        cancellation: ProvisioningDrainCancellation
    ) {
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !cancellation.isCancelled {
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = poll(&pollDescriptor, 1, 100)
            if pollResult < 0 {
                if errno == EINTR { continue }
                return
            }
            guard pollResult > 0 else { continue }

            while !cancellation.isCancelled {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    collector.append(Data(buffer.prefix(count)), stream: stream)
                    continue
                }
                if count == 0 { return }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                return
            }
        }
    }
}
#endif
