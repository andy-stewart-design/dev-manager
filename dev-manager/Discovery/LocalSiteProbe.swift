import Foundation

nonisolated enum LocalSiteProbeError: Error, Equatable, Sendable {
    case invalidCandidate
    case timedOut
    case cancelled
    case redirectRefused
    case requestFailed(String)
}

nonisolated enum LocalSiteProbeStatus: Equatable, Sendable {
    /// Any HTTP response is responsive, including 401, 404, and 500.
    case responding(statusCode: Int)
    case failed(LocalSiteProbeError)
}

nonisolated struct LocalSiteProbeResult: Equatable, Sendable {
    let candidate: LocalURLCandidate
    let status: LocalSiteProbeStatus
}

/// A deliberately narrow local HTTP probe. It does not follow redirects, use a
/// proxy for loopback, download a response body, or weaken system TLS trust.
nonisolated enum LocalSiteProbe {
    static func parsedLocalURLCandidate(_ url: URL) -> LocalURLCandidate? {
        LocalURLCandidate(url: url)
    }

    static func parsedLocalURLCandidate(_ string: String) -> LocalURLCandidate? {
        LocalURLCandidate(string: string)
    }

    static func probe(
        _ candidate: LocalURLCandidate,
        timeout: TimeInterval = 2
    ) async -> LocalSiteProbeResult {
        await ProbeOperation(candidate: candidate, timeout: timeout).run()
    }

    static func probe(
        url: URL,
        timeout: TimeInterval = 2
    ) async -> LocalSiteProbeResult {
        guard let candidate = parsedLocalURLCandidate(url) else {
            // Preserve the supplied URL only for diagnostics; it cannot become a
            // local site candidate and no network request is made.
            let fallback = LocalURLCandidate(string: "http://127.0.0.1/")!
            return LocalSiteProbeResult(candidate: fallback, status: .failed(.invalidCandidate))
        }
        return await probe(candidate, timeout: timeout)
    }

    private final class ProbeOperation: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
        private let candidate: LocalURLCandidate
        private let timeout: TimeInterval
        private let lock = NSLock()
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var continuation: CheckedContinuation<LocalSiteProbeResult, Never>?
        private var completed = false
        private var timeoutWork: DispatchWorkItem?

        init(candidate: LocalURLCandidate, timeout: TimeInterval) {
            self.candidate = candidate
            self.timeout = max(0.1, timeout)
        }

        func run() async -> LocalSiteProbeResult {
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<LocalSiteProbeResult, Never>) in
                    start(continuation: continuation)
                }
            }, onCancel: {
                cancel()
            })
        }

        private func start(continuation: CheckedContinuation<LocalSiteProbeResult, Never>) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            // An empty proxy dictionary requests a direct connection rather than
            // inheriting HTTP(S)_PROXY settings for a loopback probe.
            configuration.connectionProxyDictionary = [:]
            configuration.httpShouldSetCookies = false
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            var request = URLRequest(url: candidate.url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = timeout

            lock.lock()
            guard !completed, !Task.isCancelled else {
                completed = true
                lock.unlock()
                session.invalidateAndCancel()
                continuation.resume(returning: LocalSiteProbeResult(candidate: candidate, status: .failed(.cancelled)))
                return
            }
            self.continuation = continuation
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            let work = DispatchWorkItem { [weak self] in self?.timedOut() }
            timeoutWork = work
            lock.unlock()

            task.resume()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: work)
        }

        func cancel() {
            finish(.failed(.cancelled))
        }

        private func timedOut() {
            finish(.failed(.timedOut))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse else {
                completionHandler(.cancel)
                finish(.failed(.requestFailed("The local endpoint did not return an HTTP response.")))
                return
            }
            // A response is sufficient for readiness. Cancel immediately so a
            // misbehaving server cannot make the probe download an unbounded body.
            completionHandler(.cancel)
            finish(.responding(statusCode: http.statusCode))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
            // The local server responded; refuse navigation but count its response.
            finish(.responding(statusCode: response.statusCode))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            guard let error else {
                finish(.failed(.requestFailed("The local request ended without an HTTP response.")))
                return
            }
            if (error as NSError).code == NSURLErrorCancelled { return }
            finish(.failed(.requestFailed(error.localizedDescription)))
        }

        private func finish(_ status: LocalSiteProbeStatus) {
            let continuation: CheckedContinuation<LocalSiteProbeResult, Never>?
            let session: URLSession?
            let task: URLSessionDataTask?
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            timeoutWork?.cancel()
            continuation = self.continuation
            self.continuation = nil
            session = self.session
            task = self.task
            lock.unlock()

            task?.cancel()
            session?.invalidateAndCancel()
            continuation?.resume(returning: LocalSiteProbeResult(candidate: candidate, status: status))
        }
    }
}
