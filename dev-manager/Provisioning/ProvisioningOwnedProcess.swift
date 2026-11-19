import Foundation

nonisolated enum ProvisioningOwnedProcess {
    enum Stream: Sendable { case stdout, stderr }
    enum Outcome: Equatable, Sendable {
        case exited(Int32), cancelled, deadlineExceeded, outputLimitExceeded
        case consumerStopped, launchFailed, cleanupFailed
    }

    static func run(executableURL: URL, arguments: [String], environment: [String: String],
                    timeout: TimeInterval = 900, maximumOutputBytes: Int = 65536,
                    onOutput: @escaping @Sendable (Stream, Data) -> Bool) async -> Outcome {
        if Task.isCancelled { return .cancelled }
        let state = ProvisioningStreamingState(limit: maximumOutputBytes, callback: onOutput)
        return await ProvisioningCommandRunner.runOwned(executableURL: executableURL, arguments: arguments,
            environment: environment, timeout: timeout, state: state)
    }
}

// Drain workers serialize callbacks separately from state. When both locks are needed,
// acquire callbackLock first; cancellation only takes lock, including from a callback.
// No output bytes or per-chunk tasks are retained by this box.
nonisolated final class ProvisioningStreamingState: @unchecked Sendable {
    private let lock = NSLock()
    private let callbackLock = NSLock()
    private let limit: Int
    private let callback: @Sendable (ProvisioningOwnedProcess.Stream, Data) -> Bool
    private var count = 0
    private var stopped: ProvisioningOwnedProcess.Outcome?
    init(limit: Int, callback: @escaping @Sendable (ProvisioningOwnedProcess.Stream, Data) -> Bool) {
        self.limit = max(0, limit); self.callback = callback
    }
    var reason: ProvisioningOwnedProcess.Outcome? {
        lock.lock(); defer { lock.unlock() }; return stopped
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        if stopped == nil { stopped = .cancelled }
    }
    func cleanupFailed() {
        lock.lock(); defer { lock.unlock() }; stopped = .cleanupFailed
    }
    func append(_ data: Data, stream: ProvisioningOwnedProcess.Stream) {
        callbackLock.lock(); defer { callbackLock.unlock() }
        lock.lock()
        guard stopped == nil else { lock.unlock(); return }
        guard data.count <= limit - count else {
            stopped = .outputLimitExceeded
            lock.unlock()
            return
        }
        count += data.count
        lock.unlock()
        let shouldContinue = callback(stream, data)
        if !shouldContinue {
            lock.lock()
            if stopped == nil { stopped = .consumerStopped }
            lock.unlock()
        }
    }
}
