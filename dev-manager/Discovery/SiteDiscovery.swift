import Foundation

/// Per-run coordinator for output candidates, owned listeners, and bounded HTTP
/// probes. It is main-actor owned only for its small value state; all blocking
/// listener inspection is performed by a cancellable detached task.
@MainActor
final class SiteDiscoveryCoordinator {
    private struct Target: Sendable {
        let candidate: LocalURLCandidate
        let listener: LocalSiteListener
        let announced: Bool
    }

    private struct ProbeBatchResult: Sendable {
        let target: Target
        let result: LocalSiteProbeResult
    }

    /// A successful startup verification belongs to both the exact URL and the
    /// complete listener identity. A URL alone is not sufficient when a port is
    /// recycled by another managed process.
    private struct VerificationKey: Hashable, Sendable {
        let candidate: LocalURLCandidate
        let listener: LocalSiteListener
    }

    private let identity: ProcessIdentity
    private let publish: (SiteDiscoveryState) -> Void
    private var parser = LocalURLParser()
    private var candidates = Set<LocalURLCandidate>()
    private var scanTask: Task<Void, Never>?
    private var startedAt: Date?
    private var latestDiagnostic: String?
    private var inspectorPorts = Set<Int>()
    private var announcementTails: [RunOutputStream: String] = [:]
    private var verifiedStartup: [VerificationKey: LocalSiteProbeResult] = [:]
    private var settledFallbackProtocol: [LocalSiteListener: String] = [:]
    private static let inspectorAnnouncement = try? NSRegularExpression(
        pattern: #"Debugger listening on wss?://(?:localhost|127\.0\.0\.1|\[::1\]):([0-9]+)(?:/|\s|$)"#
    )
    private var isInactive = false

    init(identity: ProcessIdentity, publish: @escaping (SiteDiscoveryState) -> Void) {
        self.identity = identity
        self.publish = publish
    }

    func receive(_ data: Data, from stream: RunOutputStream) {
        guard !isInactive else { return }
        observeInspectorAnnouncements(data, from: stream)
        candidates.formUnion(parser.feed(data, from: stream))
    }

    func finish(_ stream: RunOutputStream) {
        guard !isInactive else { return }
        candidates.formUnion(parser.finish(stream))
    }

    func startScanning() {
        guard scanTask == nil, !isInactive else { return }
        verifiedStartup.removeAll(keepingCapacity: true)
        settledFallbackProtocol.removeAll(keepingCapacity: true)
        startedAt = Date()
        publish(.discovering)
        scanTask = Task { [weak self] in
            await self?.scanLoop()
        }
    }

    /// Stop/exit invalidation is immediate. Late probe and inspection results
    /// cannot publish because the scan task is cancelled and this flag is set.
    func cancel() {
        guard !isInactive else { return }
        isInactive = true
        scanTask?.cancel()
        scanTask = nil
        verifiedStartup.removeAll()
        settledFallbackProtocol.removeAll()
        publish(.inactive)
    }

    private func scanLoop() async {
        defer { scanTask = nil }
        while !Task.isCancelled && !isInactive {
            do {
                let inspection = try await inspectOwnedListeners()
                latestDiagnostic = nil
                invalidateVerification(for: inspection.listeners)
                let targets = makeTargets(listeners: inspection.listeners)
                let responses = await probeInBatches(targets)
                guard !Task.isCancelled && !isInactive else { return }

                // A second shared inspection is required after the network batch.
                // A PID check alone cannot prove that the same port is still owned.
                let current = try await inspectOwnedListeners()
                invalidateVerification(for: current.listeners)
                let ownedNow = Set(current.listeners)
                let verifiedHTTPSFallbacks = Set(responses.compactMap { item -> LocalSiteListener? in
                    guard !item.target.announced, item.result.candidate.scheme == "https",
                          case .responding = item.result.status else { return nil }
                    return item.target.listener
                })
                let sites = responses.compactMap { item -> LocalSite? in
                    guard case .responding = item.result.status,
                          ownedNow.contains(item.target.listener),
                          item.target.listener.matches(item.result.candidate) else { return nil }
                    if !item.target.announced, item.result.candidate.scheme == "http",
                       verifiedHTTPSFallbacks.contains(item.target.listener) { return nil }
                    return LocalSite(candidate: item.result.candidate, listener: item.target.listener)
                }
                let uniqueSites = deduplicate(sites)
                latestDiagnostic = responses.compactMap { item -> String? in
                    guard item.target.announced,
                          case let .failed(.requestFailed(message)) = item.result.status else { return nil }
                    return message
                }.first
                if uniqueSites.isEmpty {
                    if let startedAt, Date().timeIntervalSince(startedAt) >= 15 {
                        if let latestDiagnostic {
                            publish(SiteDiscoveryState(phase: .diagnostic(latestDiagnostic)))
                        } else {
                            publish(SiteDiscoveryState(phase: .noSite))
                        }
                    } else {
                        publish(.discovering)
                    }
                } else {
                    publish(SiteDiscoveryState(phase: .responding, sites: uniqueSites))
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled && !isInactive else { return }
                latestDiagnostic = error.localizedDescription
                publish(SiteDiscoveryState(phase: .diagnostic(error.localizedDescription)))
            }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func inspectOwnedListeners() async throws -> OwnedListenerInspection {
        let identity = self.identity
        let task = Task.detached(priority: .utility) {
            try OwnedListenerInspector.inspect(
                rootProcessIdentity: identity,
                timeout: 2,
                shouldCancel: { Task.isCancelled }
            )
        }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func makeTargets(listeners: [LocalSiteListener]) -> [Target] {
        let announced = candidates.filter { !isLikelyInspectorCandidate($0) }
        var targets: [Target] = []
        var covered = Set<LocalSiteListener>()

        for candidate in announced.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            guard let listener = listeners.first(where: { $0.matches(candidate) }) else { continue }
            // A new announced URL is stronger evidence than an old silent
            // fallback choice; let its advertised scheme/path be checked.
            settledFallbackProtocol.removeValue(forKey: listener)
            targets.append(Target(candidate: candidate, listener: listener, announced: true))
            covered.insert(listener)
        }

        // A silent server gets bounded HTTP and HTTPS fallback candidates. An
        // explicit announcement is never silently downgraded from HTTPS.
        for listener in listeners where !covered.contains(listener) && !isLikelyInspectorListener(listener) {
            let host = listener.bindHost == "::1" ? "[::1]" : listener.bindHost
            let schemes = settledFallbackProtocol[listener].map { [$0] } ?? ["http", "https"]
            for scheme in schemes {
                guard let candidate = LocalURLCandidate(string: "\(scheme)://\(host):\(listener.port)/") else { continue }
                targets.append(Target(candidate: candidate, listener: listener, announced: false))
            }
        }
        return deduplicateTargets(targets)
    }

    private func probeInBatches(_ targets: [Target]) async -> [ProbeBatchResult] {
        var results: [ProbeBatchResult] = []
        var pending: [Target] = []
        for target in targets {
            let key = VerificationKey(candidate: target.candidate, listener: target.listener)
            if let verified = verifiedStartup[key] {
                results.append(ProbeBatchResult(target: target, result: verified))
            } else {
                pending.append(target)
            }
        }

        var offset = 0
        while offset < pending.count && !Task.isCancelled {
            let batch = Array(pending[offset..<min(offset + 4, pending.count)])
            let batchResults = await withTaskGroup(of: ProbeBatchResult.self, returning: [ProbeBatchResult].self) { group in
                for target in batch {
                    group.addTask {
                        let result = await LocalSiteProbe.probe(target.candidate, timeout: 2)
                        return ProbeBatchResult(target: target, result: result)
                    }
                }
                var values: [ProbeBatchResult] = []
                for await value in group { values.append(value) }
                return values
            }
            guard !Task.isCancelled && !isInactive else { return results }
            for item in batchResults {
                if case .responding = item.result.status {
                    let key = VerificationKey(candidate: item.target.candidate, listener: item.target.listener)
                    verifiedStartup[key] = item.result
                    if !item.target.announced,
                       (settledFallbackProtocol[item.target.listener] == nil || item.target.candidate.scheme == "https") {
                        // Preserve the existing HTTPS-preferred fallback choice when
                        // both protocols happen to respond in one batch.
                        settledFallbackProtocol[item.target.listener] = item.target.candidate.scheme
                    }
                }
            }
            guard !Task.isCancelled && !isInactive else { return results }
            results.append(contentsOf: batchResults)
            offset += batch.count
        }
        return results
    }

    private func invalidateVerification(for listeners: [LocalSiteListener]) {
        let live = Set(listeners)
        verifiedStartup = verifiedStartup.filter { live.contains($0.key.listener) }
        settledFallbackProtocol = settledFallbackProtocol.filter { live.contains($0.key) }
    }

    private func deduplicateTargets(_ targets: [Target]) -> [Target] {
        var seen = Set<String>()
        return targets.filter { target in
            let key = "\(target.listener.owner.processID)|\(endpointKey(target.candidate))"
            guard seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func deduplicate(_ sites: [LocalSite]) -> [LocalSite] {
        var byKey: [String: LocalSite] = [:]
        for site in sites {
            let key = "\(site.listener?.owner.processID ?? 0)|\(endpointKey(site.candidate))"
            // Keep the announced/meaningful path and prefer localhost spelling
            // over a synthesized bind address when aliases meet.
            if let old = byKey[key], old.candidate.host == "localhost" { continue }
            byKey[key] = site
        }
        return byKey.values.sorted { $0.candidate.absoluteString < $1.candidate.absoluteString }
    }

    private func endpointKey(_ candidate: LocalURLCandidate) -> String {
        let port = candidate.port ?? (candidate.scheme == "https" ? 443 : 80)
        var path = candidate.url.path.isEmpty ? "/" : candidate.url.path
        if path.isEmpty { path = "/" }
        return "\(candidate.scheme.lowercased())|\(port)|\(path)|\(candidate.url.query ?? "")"
    }

    private func isLikelyInspectorCandidate(_ candidate: LocalURLCandidate) -> Bool {
        candidate.port.map(inspectorPorts.contains) ?? false
    }

    private func isLikelyInspectorListener(_ listener: LocalSiteListener) -> Bool {
        inspectorPorts.contains(listener.port)
    }

    private func observeInspectorAnnouncements(_ data: Data, from stream: RunOutputStream) {
        var text = (announcementTails[stream] ?? "") + String(decoding: data, as: UTF8.self)
        while let newline = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(text[..<newline])
            text.removeSubrange(text.startIndex...newline)
            guard inspectorPorts.count < 256, let pattern = Self.inspectorAnnouncement else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in pattern.matches(in: line, range: range) {
                guard inspectorPorts.count < 256,
                      let portRange = Range(match.range(at: 1), in: line),
                      let port = Int(line[portRange]), (1...65_535).contains(port) else { continue }
                inspectorPorts.insert(port)
            }
        }
        announcementTails[stream] = String(text.suffix(4096))
    }
}
