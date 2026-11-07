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

    @discardableResult
    func upsertPartial(runID: UUID, stream: RunOutputStream, phase: RunOutputPhase, text: String, entryID: UUID?) -> UUID {
        guard !text.isEmpty else { return entryID ?? UUID() }
        if let entryID, let index = entries.firstIndex(where: { $0.id == entryID }) {
            let oldText = entries[index].text
            entries[index] = RunLogEntry(id: entryID, runID: runID, stream: stream, phase: phase, text: text)
            byteCount += text.utf8.count - oldText.utf8.count
            trimIfNeeded()
            if entries.contains(where: { $0.id == entryID }) { return entryID }
        }
        let entry = RunLogEntry(runID: runID, stream: stream, phase: phase, text: text)
        entries.append(entry)
        byteCount += text.utf8.count
        trimIfNeeded()
        return entry.id
    }

    @discardableResult
    func finishPartial(entryID: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return false }
        let oldText = entries[index].text
        let text = oldText.hasSuffix("\n") ? oldText : oldText + "\n"
        entries[index] = RunLogEntry(id: entryID, runID: entries[index].runID, stream: entries[index].stream, phase: entries[index].phase, text: text)
        byteCount += text.utf8.count - oldText.utf8.count
        trimIfNeeded()
        return entries.contains(where: { $0.id == entryID })
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
            entries[0] = RunLogEntry(id: only.id, runID: only.runID, stream: only.stream, phase: only.phase, text: retained)
            byteCount = retained.utf8.count
            didTruncate = true
        }
    }
}
