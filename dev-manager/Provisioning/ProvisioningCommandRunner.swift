#if DEBUG
import Darwin
import Foundation

nonisolated struct ProvisioningCommandResult: Sendable {
    let succeeded: Bool
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let timedOut: Bool
}

nonisolated struct ProvisioningInstallProcessResult: Sendable {
    let succeeded: Bool
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let timedOut: Bool
}

extension ProvisioningCommandResult {
    nonisolated func failureDescription(for command: String) -> String {
        if timedOut {
            return "\(command) timed out after \(Int(ProvisioningConfiguration.commandTimeout)) seconds"
        }
        let detail = stderr.firstNonEmptyLine ?? stdout.firstNonEmptyLine ?? "exit status \(terminationStatus)"
        return "\(command) failed: \(detail)"
    }
}

nonisolated private enum ProvisioningInstallProcessError: LocalizedError, Sendable {
    case pipeFailed(String)
    case spawnFailed(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .pipeFailed(detail): return "Could not create installer output pipes: \(detail)"
        case let .spawnFailed(detail): return "Could not launch the installer: \(detail)"
        }
    }
}

nonisolated private final class ProvisioningInstallOutputCollector: @unchecked Sendable {
    private nonisolated let lock = NSLock()
    private var stdoutStorage = ""
    private var stderrStorage = ""

    nonisolated var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutStorage
    }

    nonisolated var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrStorage
    }

    nonisolated func append(_ text: String, stream: String) {
        lock.lock()
        defer { lock.unlock() }
        if stream == "stdout" {
            stdoutStorage.append(text)
        } else {
            stderrStorage.append(text)
        }
        if stdoutStorage.count > 12_000 { stdoutStorage = String(stdoutStorage.suffix(12_000)) }
        if stderrStorage.count > 12_000 { stderrStorage = String(stderrStorage.suffix(12_000)) }
    }
}

nonisolated private final class ProvisioningCommandCompletion: @unchecked Sendable {
    private nonisolated let lock = NSLock()
    private var isFinished = false

    nonisolated func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}

nonisolated enum ProvisioningCommandRunner {
    nonisolated static func run(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async -> ProvisioningCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            let completion = ProvisioningCommandCompletion()

            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = error
            process.terminationHandler = { process in
                guard completion.claim() else { return }
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProvisioningCommandResult(
                    succeeded: process.terminationReason == .exit && process.terminationStatus == 0,
                    stdout: stdout,
                    stderr: stderr,
                    terminationStatus: process.terminationStatus,
                    timedOut: false
                ))
            }

            let timeoutWork = DispatchWorkItem {
                guard completion.claim() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(returning: ProvisioningCommandResult(
                    succeeded: false,
                    stdout: "",
                    stderr: "",
                    terminationStatus: -1,
                    timedOut: true
                ))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + ProvisioningConfiguration.commandTimeout, execute: timeoutWork)

            do {
                try process.run()
            } catch {
                guard completion.claim() else { return }
                continuation.resume(returning: ProvisioningCommandResult(
                    succeeded: false,
                    stdout: "",
                    stderr: error.localizedDescription,
                    terminationStatus: -1,
                    timedOut: false
                ))
            }
        }
    }

    nonisolated static func runInstallProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        label: String
    ) async -> ProvisioningInstallProcessResult {
        let timeout = ProvisioningConfiguration.installTimeout
        let mergedEnvironment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runInstallProcessSynchronously(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: mergedEnvironment,
                    label: label,
                    timeout: timeout
                ))
            }
        }
    }

    private nonisolated static func runInstallProcessSynchronously(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        label: String,
        timeout: TimeInterval
    ) -> ProvisioningInstallProcessResult {
        let collector = ProvisioningInstallOutputCollector()
        let spawned: InstallSpawn
        do {
            spawned = try spawnInstallProcess(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment
            )
        } catch {
            return ProvisioningInstallProcessResult(
                succeeded: false,
                stdout: "",
                stderr: "\(label): \(error.localizedDescription)",
                terminationStatus: -1,
                timedOut: false
            )
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(spawned.stdout, into: collector, stream: "stdout")
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            drain(spawned.stderr, into: collector, stream: "stderr")
            group.leave()
        }

        var timedOut = !waitForInstallExit(spawned.processID, timeout: timeout)
        if timedOut {
            collector.append("\nTimed out; terminating the installer process group.\n", stream: "stderr")
        }
        let groupWasClean = stopInstallGroup(
            spawned.processID,
            timeout: timedOut ? 5.0 : 2.0
        )
        let status = reapInstallProcess(spawned.processID, timeout: 2.0)
        if status == nil { timedOut = true }

        if group.wait(timeout: .now() + 2.0) == .timedOut {
            spawned.stdout.closeFile()
            spawned.stderr.closeFile()
            _ = group.wait(timeout: .now() + 1.0)
        } else {
            spawned.stdout.closeFile()
            spawned.stderr.closeFile()
        }

        let terminationStatus = status.map(installExitCode) ?? -1
        return ProvisioningInstallProcessResult(
            succeeded: !timedOut && groupWasClean && terminationStatus == 0,
            stdout: collector.stdout,
            stderr: collector.stderr,
            terminationStatus: terminationStatus,
            timedOut: timedOut
        )
    }

    nonisolated private struct InstallSpawn: Sendable {
        let processID: Int32
        let stdout: FileHandle
        let stderr: FileHandle
    }

    private nonisolated static func spawnInstallProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> InstallSpawn {
        let stdoutPipe = try makeInstallPipe()
        let stderrPipe: (read: Int32, write: Int32)
        do {
            stderrPipe = try makeInstallPipe()
        } catch {
            close(stdoutPipe.read)
            close(stdoutPipe.write)
            throw error
        }

        let stdinFD = open("/dev/null", O_RDONLY)
        guard stdinFD >= 0 else {
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw ProvisioningInstallProcessError.spawnFailed("/dev/null: \(String(cString: strerror(errno)))")
        }
        let normalizedStdin: Int32
        do {
            normalizedStdin = try normalizeInstallDescriptor(stdinFD)
        } catch {
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
            throw ProvisioningInstallProcessError.spawnFailed("could not initialize file actions")
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw ProvisioningInstallProcessError.spawnFailed("could not initialize process-group attributes")
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
            throw ProvisioningInstallProcessError.spawnFailed("could not configure the installer process group or output streams")
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
            throw ProvisioningInstallProcessError.spawnFailed(String(cString: strerror(result)))
        }

        return InstallSpawn(
            processID: processID,
            stdout: FileHandle(fileDescriptor: stdoutPipe.read, closeOnDealloc: true),
            stderr: FileHandle(fileDescriptor: stderrPipe.read, closeOnDealloc: true)
        )
    }

    private nonisolated static func makeInstallPipe() throws -> (read: Int32, write: Int32) {
        var fds = [Int32](repeating: -1, count: 2)
        guard pipe(&fds) == 0 else {
            throw ProvisioningInstallProcessError.pipeFailed(String(cString: strerror(errno)))
        }
        do {
            fds[0] = try normalizeInstallDescriptor(fds[0])
            fds[1] = try normalizeInstallDescriptor(fds[1])
            return (fds[0], fds[1])
        } catch {
            if fds[0] >= 0 { close(fds[0]) }
            if fds[1] >= 0 { close(fds[1]) }
            throw error
        }
    }

    private nonisolated static func normalizeInstallDescriptor(_ descriptor: Int32) throws -> Int32 {
        guard descriptor < 3 else { return descriptor }
        let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        guard replacement >= 0 else {
            throw ProvisioningInstallProcessError.pipeFailed("could not protect file descriptor: \(String(cString: strerror(errno)))")
        }
        close(descriptor)
        return replacement
    }

    private nonisolated static func waitForInstallExit(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var info = siginfo_t()
            let result = waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0, info.si_pid != 0 { return true }
            if result < 0, errno != EINTR { return false }
            usleep(100_000)
        }
        return false
    }

    private nonisolated static func stopInstallGroup(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let hasMembers = { dm_group_has_non_zombie_members(processID, processID) != 0 }
        guard hasMembers() else { return true }
        _ = kill(-processID, SIGTERM)
        let termDeadline = Date().addingTimeInterval(timeout)
        while hasMembers() && Date() < termDeadline { usleep(50_000) }
        if hasMembers() {
            _ = kill(-processID, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1.0)
            while hasMembers() && Date() < killDeadline { usleep(50_000) }
        }
        return !hasMembers()
    }

    private nonisolated static func reapInstallProcess(_ processID: Int32, timeout: TimeInterval) -> Int32? {
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

    private nonisolated static func installExitCode(_ status: Int32) -> Int32 {
        (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
    }

    private nonisolated static func drain(_ handle: FileHandle, into collector: ProvisioningInstallOutputCollector, stream: String) {
        while true {
            guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { break }
            collector.append(String(decoding: data, as: UTF8.self), stream: stream)
        }
    }
}
#endif
