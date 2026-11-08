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

/// Keeps stream-local incomplete lines out of the lifecycle coordinator. It preserves
/// split UTF-8, treats CR as progress, and bounds unterminated output per stream.
@MainActor
final class RunOutputAccumulator {
    private static let maximumIncompleteLineBytes = 64 * 1024
    private var partialLines: [RunOutputStream: Data] = [:]
    private var partialEntryIDs: [RunOutputStream: UUID] = [:]
    private var partialLineDroppedBytes: [RunOutputStream: Int] = [:]

    func consume(data: Data, stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        var remainder = partialLines[stream] ?? Data()
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let delimiter = data[cursor...].firstIndex(where: { $0 == 10 || $0 == 13 }) else {
                remainder.append(data[cursor...])
                break
            }
            remainder.append(data[cursor..<delimiter])
            if data[delimiter] == 10 {
                if !remainder.isEmpty { publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer) }
                if remainder.isEmpty, let entryID = partialEntryIDs.removeValue(forKey: stream) {
                    _ = logBuffer.finishPartial(entryID: entryID)
                } else {
                    consumeLine(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                }
                remainder.removeAll(keepingCapacity: true)
            } else {
                publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                remainder.removeAll(keepingCapacity: true)
            }
            cursor = data.index(after: delimiter)
        }
        if remainder.count > Self.maximumIncompleteLineBytes {
            let excess = remainder.count - Self.maximumIncompleteLineBytes
            remainder = Data(remainder.suffix(Self.maximumIncompleteLineBytes))
            partialLineDroppedBytes[stream, default: 0] += excess
        }
        partialLines[stream] = remainder
        if !remainder.isEmpty { publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer) }
    }

    func finish(stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        if let remainder = partialLines.removeValue(forKey: stream), !remainder.isEmpty {
            consumeLine(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
        } else if let entryID = partialEntryIDs.removeValue(forKey: stream) {
            _ = logBuffer.finishPartial(entryID: entryID)
        }
        if let dropped = partialLineDroppedBytes.removeValue(forKey: stream), dropped > 0 {
            logBuffer.append(runID: runID, stream: stream, phase: phase, text: "[Dev Manager truncated \(dropped) bytes from an unterminated line.]\n")
        }
    }

    private func publishPartial(_ data: Data, stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        guard !data.isEmpty else { return }
        let text = partialDisplayText(data)
        guard !text.isEmpty else { return }
        let entryID = logBuffer.upsertPartial(runID: runID, stream: stream, phase: phase, text: text, entryID: partialEntryIDs[stream])
        partialEntryIDs[stream] = entryID
    }

    private func partialDisplayText(_ data: Data) -> String {
        let bytes = Array(data)
        var trailingStart = bytes.count
        var continuationCount = 0
        while trailingStart > 0, (bytes[trailingStart - 1] & 0xC0) == 0x80 {
            continuationCount += 1; trailingStart -= 1
        }
        var validEnd = bytes.count
        if trailingStart == 0 { validEnd = 0 } else {
            let lead = bytes[trailingStart - 1]
            let expectedCount: Int
            if lead & 0x80 == 0 { expectedCount = 0 }
            else if lead & 0xE0 == 0xC0 { expectedCount = 1 }
            else if lead & 0xF0 == 0xE0 { expectedCount = 2 }
            else if lead & 0xF8 == 0xF0 { expectedCount = 3 }
            else { expectedCount = 0 }
            if expectedCount > continuationCount { validEnd = trailingStart - 1 }
            else if expectedCount < continuationCount { validEnd = trailingStart }
        }
        return String(decoding: bytes.prefix(validEnd), as: UTF8.self)
    }

    private func consumeLine(_ data: Data, stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        var line = String(decoding: data, as: UTF8.self)
        if line.last == "\r" { line.removeLast() }
        if let entryID = partialEntryIDs.removeValue(forKey: stream) {
            if !logBuffer.finishPartial(entryID: entryID) {
                logBuffer.append(runID: runID, stream: stream, phase: phase, text: line + "\n")
            }
            return
        }
        logBuffer.append(runID: runID, stream: stream, phase: phase, text: line + "\n")
    }
}
