import Foundation

/// Main-actor-owned retained output. It never writes to disk and is capped per project.
@MainActor
final class LogBuffer {
    static let maximumBytes = 2 * 1024 * 1024

    private(set) var entries: [RunLogEntry] = []
    private(set) var didTruncate = false
    private var byteCount = 0

    func append(runID: UUID, stream: RunOutputStream, phase: RunOutputPhase, text: String) {
        guard !text.isEmpty else { return }
        let entry = RunLogEntry(runID: runID, stream: stream, phase: phase, text: text)
        entries.append(entry)
        byteCount += text.utf8.count
        trimIfNeeded()
    }

    func snapshot() -> ([RunLogEntry], Bool) {
        (entries, didTruncate)
    }

    private func trimIfNeeded() {
        while byteCount > Self.maximumBytes, entries.count > 1 {
            let removed = entries.removeFirst()
            byteCount -= removed.text.utf8.count
            didTruncate = true
        }

        // A single write can be larger than the cap. Retain its useful tail rather than
        // allowing one entry to defeat the bound.
        if let only = entries.first, entries.count == 1, only.text.utf8.count > Self.maximumBytes {
            let bytes = Array(only.text.utf8.suffix(Self.maximumBytes))
            let retained = String(decoding: bytes, as: UTF8.self)
            entries[0] = RunLogEntry(runID: only.runID, stream: only.stream, phase: only.phase, text: retained)
            byteCount = retained.utf8.count
            didTruncate = true
        }
    }
}
