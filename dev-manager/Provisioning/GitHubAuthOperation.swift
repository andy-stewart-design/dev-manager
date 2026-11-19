import Foundation

nonisolated struct GitHubAuthOperationResult: Equatable, Sendable {
    enum Completion: Equatable, Sendable { case exited(Int32), cancelled, failed(GitHubLoginFailure) }
    let completion: Completion
    let warnedAboutPlaintextStorage: Bool
}

nonisolated enum GitHubAuthOperation {
    typealias Runner = @Sendable (URL, [String], [String: String], TimeInterval, Int,
                                   @escaping @Sendable (ProvisioningOwnedProcess.Stream, Data) -> Bool) async -> ProvisioningOwnedProcess.Outcome

    static func run(using context: ProvisioningGitHubCLIContext, hostname: GitHubHostname,
                    onEvent: @escaping @Sendable (GitHubDeviceFlowEvent) -> Void,
                    environment: [String: String] = ProcessInfo.processInfo.environment,
                    run: @escaping Runner = { url, args, env, timeout, limit, output in
                        await ProvisioningOwnedProcess.run(executableURL: url, arguments: args, environment: env,
                            timeout: timeout, maximumOutputBytes: limit, onOutput: output)
                    }) async -> GitHubAuthOperationResult {
        func failure(_ failure: GitHubLoginFailure) -> GitHubAuthOperationResult {
            .init(completion: .failed(failure), warnedAboutPlaintextStorage: false)
        }
        if Task.isCancelled { return .init(completion: .cancelled, warnedAboutPlaintextStorage: false) }
        let parts = context.version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "2", let minor = Int(parts[1]), (101...105).contains(minor),
              parts[2] == "0" else { return failure(.unsupportedCLI) }
        let host = hostname.value
        let publicHost = host == "github.com" || host == "github.localhost" || host.hasSuffix(".ghe.com")
        let names = publicHost ? ["GH_TOKEN", "GITHUB_TOKEN"] : ["GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]
        // Check both the supplied snapshot and current inherited environment before spawning.
        guard !names.contains(where: { !(environment[$0] ?? "").isEmpty || !(ProcessInfo.processInfo.environment[$0] ?? "").isEmpty }) else {
            return failure(.unavailable)
        }
        var env = environment
        for (key, value) in ["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "GH_DEBUG": "", "DEBUG": "", "GH_FORCE_TTY": "", "NO_COLOR": "1", "CLICOLOR": "0", "CLICOLOR_FORCE": "0", "GH_BROWSER": "/usr/bin/true", "BROWSER": "/usr/bin/true"] { env[key] = value }
        let state = GitHubAuthParserState(hostname: hostname, onEvent: onEvent)
        let outcome = await run(context.executableURL,
            ["auth", "login", "--hostname", host, "--git-protocol", "https", "--web", "--clipboard=true"], env, 900, 65536) { stream, data in
                state.consume(data, stream: stream == .stdout ? .stdout : .stderr)
            }
        if case .exited = outcome { state.finish() }
        let (parserFailure, warned) = state.snapshot()
        let completion: GitHubAuthOperationResult.Completion
        switch outcome {
        case .cancelled: completion = .cancelled
        case .deadlineExceeded: completion = .failed(.deadlineExceeded)
        case .outputLimitExceeded: completion = .failed(.outputLimitExceeded)
        case .consumerStopped: completion = .failed(parserFailure ?? .unsupportedOutput)
        case .launchFailed, .cleanupFailed: completion = .failed(.unavailable)
        case .exited(let status):
            if let parserFailure { completion = .failed(parserFailure) }
            else { completion = .exited(status) }
        }
        return .init(completion: completion, warnedAboutPlaintextStorage: warned)
    }
}

// The process collector serializes callbacks, but finish and snapshot also synchronize
// with them so injected runners cannot race parser state.
nonisolated private final class GitHubAuthParserState: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: GitHubDeviceFlowParser
    private let onEvent: @Sendable (GitHubDeviceFlowEvent) -> Void
    private var failure: GitHubLoginFailure?
    private var warned = false
    init(hostname: GitHubHostname, onEvent: @escaping @Sendable (GitHubDeviceFlowEvent) -> Void) {
        parser = GitHubDeviceFlowParser(hostname: hostname); self.onEvent = onEvent
    }
    func consume(_ data: Data, stream: GitHubDeviceFlowStream) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return false }
        do { emit(try parser.consume(data, stream: stream)); return true }
        catch { failure = (error as? GitHubLoginFailure) ?? .unsupportedOutput; return false }
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return }
        do { emit(try parser.finish()) }
        catch { failure = (error as? GitHubLoginFailure) ?? .unsupportedOutput }
    }
    private func emit(_ events: [GitHubDeviceFlowEvent]) {
        for event in events {
            if event == .plaintextStorageWarning { warned = true }
            onEvent(event)
        }
    }
    func snapshot() -> (GitHubLoginFailure?, Bool) {
        lock.lock(); defer { lock.unlock() }; return (failure, warned)
    }
}
