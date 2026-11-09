import Darwin
import Foundation

nonisolated struct SpawnedProcess: Sendable {
    let processID: Int32
    let processGroupID: Int32
    let stdout: FileHandle
    let stderr: FileHandle
    let ready: FileHandle
    let startTime: RunJournalEntry.ProcessStartTime
}

nonisolated struct ProcessIdentity: Sendable {
    let processID: Int32
    let processGroupID: Int32
    let startTime: RunJournalEntry.ProcessStartTime
}

nonisolated struct ProcessExit: Sendable {
    let status: Int32
    var exitCode: Int32? {
        if (status & 0x7f) == 0 { return (status >> 8) & 0xff }
        return nil
    }
    var signal: Int32? {
        let value = status & 0x7f
        return value == 0 ? nil : value
    }
}

enum ProcessLauncherError: LocalizedError, Sendable {
    case pipeFailed(String)
    case spawnFailed(String)
    case processGroupUnavailable
    case ownershipObservationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .pipeFailed(message): return "Could not create command output pipes: \(message)"
        case let .spawnFailed(message): return "Could not launch the command: \(message)"
        case .processGroupUnavailable:
            return "Dev Manager could not establish a dedicated process group for this run. The command was not accepted."
        case let .ownershipObservationFailed(message):
            return "Dev Manager could not verify owned process cleanup: \(message)"
        }
    }
}

enum ReadyResult: Sendable {
    case ready
    case closed
    case timedOut
}

enum ProcessLauncher {
    private nonisolated static let minimumDescriptor = Int32(3)

    nonisolated static func spawn(
        shell: ShellEnvironment,
        folder: URL,
        command: String
    ) throws -> SpawnedProcess {
        let stdoutPipe = try makePipe()
        var stderrPipe: (read: Int32, write: Int32)?
        var readyPipe: (read: Int32, write: Int32)?
        do {
            stderrPipe = try makePipe()
            readyPipe = try makePipe()
        } catch {
            close(stdoutPipe.read); close(stdoutPipe.write)
            if let stderrPipe { close(stderrPipe.read); close(stderrPipe.write) }
            throw error
        }
        let stderr = stderrPipe!
        let ready = readyPipe!

        let stdinFD: Int32
        let openedStdin = open("/dev/null", O_RDONLY)
        if openedStdin >= 0 {
            do {
                stdinFD = try normalizeDescriptor(openedStdin)
            } catch {
                close(stdoutPipe.read); close(stdoutPipe.write)
                close(stderr.read); close(stderr.write); close(ready.read); close(ready.write)
                throw error
            }
        } else {
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderr.read); close(stderr.write); close(ready.read); close(ready.write)
            throw ProcessLauncherError.pipeFailed("/dev/null: \(String(cString: strerror(errno)))")
        }

        // The pipe ends use CLOEXEC for ordinary descriptor hygiene. Readiness is
        // deliberately different: give the child an explicit dup2 target above every
        // source descriptor. This avoids source/stdio aliasing and makes the one
        // private handshake descriptor inherited only by this spawn action.
        let maximumSourceDescriptor = max(stdinFD, stdoutPipe.read, stdoutPipe.write, stderr.read, stderr.write, ready.read, ready.write)
        let handshakeSource = fcntl(ready.write, F_DUPFD_CLOEXEC, maximumSourceDescriptor + 1)
        guard handshakeSource >= 0 else {
            close(stdinFD); close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderr.read); close(stderr.write); close(ready.read); close(ready.write)
            throw ProcessLauncherError.spawnFailed("could not reserve readiness descriptor: \(String(cString: strerror(errno)))")
        }
        let handshakeFD = handshakeSource + 1

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            close(stdinFD); close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderr.read); close(stderr.write); close(ready.read); close(ready.write); close(handshakeSource)
            throw ProcessLauncherError.spawnFailed("could not initialize file actions")
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            close(stdinFD); close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderr.read); close(stderr.write); close(ready.read); close(ready.write); close(handshakeSource)
            throw ProcessLauncherError.spawnFailed("could not initialize spawn attributes")
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        func closeCreatedDescriptors() {
            close(stdinFD)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderr.read); close(stderr.write)
            close(ready.read); close(ready.write); close(handshakeSource)
        }

        // Start closed by default: only the explicit dup2 targets below survive.
        // POSIX dup2 actions clear close-on-exec on stdin/stdout/stderr and the
        // private readiness target, while every unrelated parent descriptor stays closed.
        let groupFlags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_RESETIDS | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        guard posix_spawnattr_setflags(&attributes, groupFlags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            closeCreatedDescriptors()
            throw ProcessLauncherError.spawnFailed("could not configure process-group ownership")
        }

        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        guard posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setsigmask(&attributes, &emptyMask) == 0 else {
            closeCreatedDescriptors()
            throw ProcessLauncherError.spawnFailed("could not reset inherited signal state")
        }

        // All source descriptors are normalized above 2. Add dup actions before their
        // close actions; this remains correct even if the caller itself has sparse fds.
        guard posix_spawn_file_actions_addchdir_np(&actions, folder.path) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdinFD, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdoutPipe.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderr.write, STDERR_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, handshakeSource, handshakeFD) == 0,
              posix_spawn_file_actions_addclose(&actions, stdinFD) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stderr.read) == 0,
              posix_spawn_file_actions_addclose(&actions, ready.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.write) == 0,
              posix_spawn_file_actions_addclose(&actions, stderr.write) == 0,
              posix_spawn_file_actions_addclose(&actions, handshakeSource) == 0 else {
            closeCreatedDescriptors()
            throw ProcessLauncherError.spawnFailed("could not configure the project directory or output streams")
        }

        // Readiness is a private inherited pipe, not a line in either user-visible log.
        // The command itself is positional ($1), so startup files cannot replace an
        // environment variable and change what this invocation evaluates.
        // zsh requires parameter-based redirection for multi-digit descriptors.
        let script = "setopt no_monitor; print -nu \(handshakeFD) -- READY; _dev_manager_ready_fd=\(handshakeFD); exec {_dev_manager_ready_fd}>&-; unset _dev_manager_ready_fd; eval -- \"$1\""
        let arguments = [shell.shellURL.path, "-l", "-i", "-c", script, "--", command]
        var argv = arguments.map { strdup($0) }
        argv.append(nil)
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        let environmentValues = shell.environment
        var envp = environmentValues.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.compactMap { $0 }.forEach { free($0) } }

        var child: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envBuffer in
                posix_spawn(&child, shell.shellURL.path, &actions, &attributes, argvBuffer.baseAddress, envBuffer.baseAddress)
            }
        }

        close(stdinFD)
        close(stdoutPipe.write)
        close(stderr.write)
        close(ready.write)
        close(handshakeSource)
        guard result == 0 else {
            close(stdoutPipe.read); close(stderr.read); close(ready.read)
            throw ProcessLauncherError.spawnFailed(String(cString: strerror(result)))
        }

        // Never signal a group observed after a failed ownership check. The child PID
        // is still ours and unreaped here, so direct cleanup cannot target a reused PID.
        let observedGroup = getpgid(child)
        guard observedGroup == child else {
            _ = terminateAndReapCreatedChild(child)
            close(stdoutPipe.read); close(stderr.read); close(ready.read)
            if observedGroup > 0 {
                throw ProcessLauncherError.processGroupUnavailable
            }
            throw ProcessLauncherError.ownershipObservationFailed("the created launcher exited before its process group could be verified")
        }

        var currentGroup: pid_t = 0
        var startSeconds: UInt64 = 0
        var startMicros: UInt32 = 0
        // The child remains unreaped until normal supervision observes and reaps it.
        // Permit SZOMB here so a fast command still returns its pipes and exit status;
        // all recovery/stop readers continue to reject zombies.
        guard dm_created_process_identity(child, &currentGroup, &startSeconds, &startMicros) == 1,
              currentGroup == child else {
            _ = terminateAndReapCreatedChild(child)
            close(stdoutPipe.read); close(stderr.read); close(ready.read)
            throw ProcessLauncherError.ownershipObservationFailed("the created launcher start identity could not be read")
        }

        return SpawnedProcess(
            processID: child,
            processGroupID: child,
            stdout: FileHandle(fileDescriptor: stdoutPipe.read, closeOnDealloc: true),
            stderr: FileHandle(fileDescriptor: stderr.read, closeOnDealloc: true),
            ready: FileHandle(fileDescriptor: ready.read, closeOnDealloc: true),
            startTime: RunJournalEntry.ProcessStartTime(seconds: startSeconds, microseconds: startMicros)
        )
    }

    nonisolated static func waitForExitObservation(processID: Int32) -> Result<Void, Error> {
        var info = siginfo_t()
        while true {
            let result = waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0, info.si_pid != 0 { return .success(()) }
            if result < 0 {
                if errno == EINTR { continue }
                return .failure(ProcessLauncherError.ownershipObservationFailed("waitid failed: \(String(cString: strerror(errno)))"))
            }
            usleep(50_000)
        }
    }

    nonisolated static func waitForReady(_ handle: FileHandle, timeout: TimeInterval) -> ReadyResult {
        let fd = handle.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var byte = UInt8.zero
        while !Task.isCancelled && Date() < deadline {
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let waitMilliseconds = Int32(max(1, min(100, Int((deadline.timeIntervalSinceNow * 1000).rounded(.up)))))
            let result = poll(&pollFD, 1, waitMilliseconds)
            if result < 0 {
                if errno == EINTR { continue }
                return .closed
            }
            guard result > 0 else { continue }
            let readResult = read(fd, &byte, 1)
            if readResult == 1 { return byte == 82 ? .ready : .closed }
            if readResult == 0 { return .closed }
            if errno != EINTR { return .closed }
        }
        return .timedOut
    }

    nonisolated static func stop(identity: ProcessIdentity) -> StopResult {
        let groupID = identity.processGroupID
        if let error = ownershipError(groupID: groupID, leaderID: identity.processID) {
            return StopResult(groupGone: false, exit: nil, error: error)
        }
        let leaderExited = hasObservedExit(processID: identity.processID)
        guard stopGroup(groupID: groupID, leaderID: leaderExited ? identity.processID : -1) else {
            return StopResult(groupGone: false, exit: nil, error: "Owned process group \(groupID) did not disappear after the finite SIGINT/SIGTERM/SIGKILL escalation. Ownership is retained; no unrelated process was signaled.")
        }
        guard let exit = reap(processID: identity.processID) else {
            return StopResult(groupGone: false, exit: nil, error: "The owned launcher could not be reaped after cleanup; ownership is retained.")
        }
        return StopResult(groupGone: true, exit: exit, error: nil)
    }

    nonisolated static func isGroupAlive(_ groupID: Int32) -> Bool {
        hasNonZombieMembers(groupID: groupID, leaderID: groupID)
    }

    private nonisolated static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds = [Int32](repeating: -1, count: 2)
        guard pipe(&fds) == 0 else {
            throw ProcessLauncherError.pipeFailed(String(cString: strerror(errno)))
        }
        var normalizedRead: Int32 = -1
        var normalizedWrite: Int32 = -1
        do {
            normalizedRead = try normalizeDescriptor(fds[0])
            normalizedWrite = try normalizeDescriptor(fds[1])
            return (normalizedRead, normalizedWrite)
        } catch {
            if fds[0] >= 0 { close(fds[0]) }
            if fds[1] >= 0 { close(fds[1]) }
            if normalizedRead >= 0 && normalizedRead != fds[0] { close(normalizedRead) }
            if normalizedWrite >= 0 && normalizedWrite != fds[1] && normalizedWrite != normalizedRead { close(normalizedWrite) }
            throw error
        }
    }

    private nonisolated static func normalizeDescriptor(_ fd: Int32) throws -> Int32 {
        if fd >= minimumDescriptor { return fd }
        let replacement = fcntl(fd, F_DUPFD_CLOEXEC, minimumDescriptor)
        close(fd)
        guard replacement >= 0 else {
            throw ProcessLauncherError.pipeFailed("could not protect file descriptor: \(String(cString: strerror(errno)))")
        }
        return replacement
    }

    private nonisolated static func terminateAndReapCreatedChild(_ processID: Int32) -> Bool {
        _ = kill(processID, SIGKILL)
        var status: Int32 = 0
        while waitpid(processID, &status, 0) < 0 {
            if errno == EINTR { continue }
            return false
        }
        return true
    }

    private nonisolated static func hasObservedExit(processID: Int32) -> Bool {
        var info = siginfo_t()
        while true {
            let result = waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0 { return info.si_pid != 0 }
            if errno == EINTR { continue }
            return false
        }
    }

    private nonisolated static func reap(processID: Int32) -> ProcessExit? {
        var status: Int32 = 0
        while true {
            let result = waitpid(processID, &status, 0)
            if result == processID { return ProcessExit(status: status) }
            if result < 0, errno == EINTR { continue }
            return nil
        }
    }

    private nonisolated static func ownershipError(groupID: Int32, leaderID: Int32) -> String? {
        let result = dm_group_has_non_zombie_members(groupID, leaderID)
        guard result < 0 else { return nil }
        let code = Int32(-result)
        return ProcessLauncherError.ownershipObservationFailed("process-group inspection failed: \(String(cString: strerror(code)))").localizedDescription
    }

    private nonisolated static func hasNonZombieMembers(groupID: Int32, leaderID: Int32) -> Bool {
        // Inspection failure is conservatively treated as live/unknown. This prevents
        // a signal after the owned identity can no longer be verified.
        dm_group_has_non_zombie_members(groupID, leaderID) != 0
    }

    private nonisolated static func stopGroup(groupID: Int32, leaderID: Int32) -> Bool {
        if hasNonZombieMembers(groupID: groupID, leaderID: leaderID) {
            if send(signal: SIGINT, to: groupID, leaderID: leaderID), waitUntilGone(groupID: groupID, leaderID: leaderID, timeout: 3.0) == false {
                if send(signal: SIGTERM, to: groupID, leaderID: leaderID), waitUntilGone(groupID: groupID, leaderID: leaderID, timeout: 2.0) == false {
                    if send(signal: SIGKILL, to: groupID, leaderID: leaderID), waitUntilGone(groupID: groupID, leaderID: leaderID, timeout: 1.0) == false {
                        return false
                    }
                }
            }
        }
        return !hasNonZombieMembers(groupID: groupID, leaderID: leaderID)
    }

    private nonisolated static func send(signal: Int32, to groupID: Int32, leaderID: Int32) -> Bool {
        guard hasNonZombieMembers(groupID: groupID, leaderID: leaderID) else { return true }
        return kill(-groupID, signal) == 0 || errno == ESRCH
    }

    private nonisolated static func waitUntilGone(groupID: Int32, leaderID: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !hasNonZombieMembers(groupID: groupID, leaderID: leaderID) { return true }
            usleep(50_000)
        } while Date() < deadline
        return !hasNonZombieMembers(groupID: groupID, leaderID: leaderID)
    }
}

nonisolated struct StopResult: Sendable {
    let groupGone: Bool
    let exit: ProcessExit?
    let error: String?
}
