import Foundation

/// Main-actor-owned retained output. It never writes to disk and is capped per project.
@MainActor
final class LogBuffer {
    static let maximumBytes = 2 * 1024 * 1024
    /// A byte cap alone is not enough for output made of thousands of tiny lines.
    /// Keep the retained representation bounded by both bytes and entry metadata.
    static let maximumEntries = 16_384

    private static let truncationMarker = "[Dev Manager truncated retained output to stay within its bounded log buffer.]\n"

    private var storage: [RunLogEntry] = []
    private var headIndex = 0
    private var entryIndices: [UUID: Int] = [:]
    private var truncationMarkerID: UUID?
    private var byteCount = 0
    private(set) var didTruncate = false

    var entries: [RunLogEntry] {
        Array(storage[headIndex..<storage.endIndex])
    }

    func append(runID: UUID, stream: RunOutputStream, phase: RunOutputPhase, text: String) {
        guard !text.isEmpty else { return }
        appendRaw(RunLogEntry(runID: runID, stream: stream, phase: phase, text: text))
        trimIfNeeded(runID: runID, stream: stream, phase: phase)
    }

    @discardableResult
    func upsertPartial(runID: UUID, stream: RunOutputStream, phase: RunOutputPhase, text: String, entryID: UUID?) -> UUID {
        guard !text.isEmpty else { return entryID ?? UUID() }
        if let entryID, let index = entryIndices[entryID], index >= headIndex {
            let oldText = storage[index].text
            storage[index] = RunLogEntry(id: entryID, runID: runID, stream: stream, phase: phase, text: text)
            byteCount += text.utf8.count - oldText.utf8.count
            trimIfNeeded(runID: runID, stream: stream, phase: phase)
            if let currentIndex = entryIndices[entryID], currentIndex >= headIndex {
                return entryID
            }
        }

        let entry = RunLogEntry(runID: runID, stream: stream, phase: phase, text: text)
        appendRaw(entry)
        trimIfNeeded(runID: runID, stream: stream, phase: phase)
        // A newly appended row normally survives because trimming removes the
        // oldest rows. If an extreme bound evicts it, force the caller to start
        // a fresh partial row rather than accidentally reusing the marker ID.
        return entryIndices[entry.id] == nil ? UUID() : entry.id
    }

    @discardableResult
    func finishPartial(entryID: UUID) -> Bool {
        guard let index = entryIndices[entryID], index >= headIndex else { return false }
        let oldText = storage[index].text
        let text = oldText.hasSuffix("\n") ? oldText : oldText + "\n"
        storage[index] = RunLogEntry(id: entryID, runID: storage[index].runID, stream: storage[index].stream, phase: storage[index].phase, text: text)
        byteCount += text.utf8.count - oldText.utf8.count
        trimIfNeeded(runID: storage[index].runID, stream: storage[index].stream, phase: storage[index].phase)
        return entryIndices[entryID] != nil
    }

    func snapshot() -> ([RunLogEntry], Bool) {
        (entries, didTruncate)
    }

    private func appendRaw(_ entry: RunLogEntry) {
        storage.append(entry)
        entryIndices[entry.id] = storage.index(before: storage.endIndex)
        byteCount += entry.text.utf8.count
    }

    private func trimIfNeeded(runID: UUID, stream: RunOutputStream, phase: RunOutputPhase) {
        guard byteCount > Self.maximumBytes || activeEntryCount > Self.maximumEntries else { return }
        didTruncate = true

        // Reserve room for an explanatory marker before adding it. This also makes
        // the single-entry case useful: retain the tail of a huge write rather than
        // dropping the whole line just to make room for the marker.
        if truncationMarkerID == nil {
            trimRaw(byteLimit: max(0, Self.maximumBytes - Self.truncationMarker.utf8.count), entryLimit: max(1, Self.maximumEntries - 1))
            let marker = RunLogEntry(runID: runID, stream: stream, phase: phase, text: Self.truncationMarker)
            appendRaw(marker)
            truncationMarkerID = marker.id
        }

        trimRaw(byteLimit: Self.maximumBytes, entryLimit: Self.maximumEntries)
        // The marker can itself become the oldest retained entry after later output.
        // Reinsert it at the tail so the current snapshot always explains truncation.
        if truncationMarkerID == nil {
            trimRaw(byteLimit: max(0, Self.maximumBytes - Self.truncationMarker.utf8.count), entryLimit: max(1, Self.maximumEntries - 1))
            let marker = RunLogEntry(runID: runID, stream: stream, phase: phase, text: Self.truncationMarker)
            appendRaw(marker)
            truncationMarkerID = marker.id
            trimRaw(byteLimit: Self.maximumBytes, entryLimit: Self.maximumEntries)
        }
        compactIfUseful()
    }

    private var activeEntryCount: Int { storage.count - headIndex }

    private func trimRaw(byteLimit: Int, entryLimit: Int) {
        while activeEntryCount > entryLimit || byteCount > byteLimit {
            if activeEntryCount == 0 { return }
            if activeEntryCount == 1 {
                guard byteCount > byteLimit else {
                    removeOldest()
                    continue
                }
                let index = headIndex
                let entry = storage[index]
                let bytes = Array(entry.text.utf8.suffix(max(0, byteLimit)))
                let retained = String(decoding: bytes, as: UTF8.self)
                storage[index] = RunLogEntry(id: entry.id, runID: entry.runID, stream: entry.stream, phase: entry.phase, text: retained)
                byteCount = retained.utf8.count
                return
            }
            removeOldest()
        }
    }

    private func removeOldest() {
        guard headIndex < storage.endIndex else { return }
        let removed = storage[headIndex]
        entryIndices.removeValue(forKey: removed.id)
        if truncationMarkerID == removed.id { truncationMarkerID = nil }
        byteCount -= removed.text.utf8.count
        // Keep the tombstone's metadata for amortized compaction, but release the
        // potentially large payload as soon as the entry leaves the active window.
        storage[headIndex] = RunLogEntry(id: removed.id, runID: removed.runID, stream: removed.stream, phase: removed.phase, text: "")
        headIndex += 1
        compactIfUseful()
    }

    private func compactIfUseful() {
        guard headIndex > 1024, headIndex * 2 >= storage.count else { return }
        storage.removeFirst(headIndex)
        headIndex = 0
        entryIndices.removeAll(keepingCapacity: true)
        for index in storage.indices { entryIndices[storage[index].id] = index }
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
            var delimiter = cursor
            while delimiter < data.endIndex, data[delimiter] != 10, data[delimiter] != 13 {
                delimiter = data.index(after: delimiter)
            }
            remainder.append(data[cursor..<delimiter])

            if delimiter == data.endIndex {
                break
            }

            if data[delimiter] == 10 {
                if remainder.isEmpty {
                    if let entryID = partialEntryIDs.removeValue(forKey: stream) {
                        _ = logBuffer.finishPartial(entryID: entryID)
                    } else {
                        // LF still represents a real blank output line.
                        appendLine(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                    }
                } else if partialEntryIDs[stream] != nil {
                    // A CR or an earlier chunk exposed this as progress. Update that
                    // one entry once, then finish it; do not create a second row.
                    publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                    _ = finishCurrentPartial(stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                } else {
                    // Complete LF-terminated lines do not need a temporary upsert.
                    appendLine(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                }
                remainder.removeAll(keepingCapacity: true)
            } else {
                // CR is a progress update. Keep its latest text in one stream-local
                // entry until a later LF or EOF supplies the terminating newline.
                if !remainder.isEmpty {
                    publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                }
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
        if !remainder.isEmpty {
            publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
        }
    }

    func finish(stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        if let remainder = partialLines.removeValue(forKey: stream), !remainder.isEmpty {
            if partialEntryIDs[stream] != nil {
                publishPartial(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
                _ = finishCurrentPartial(stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
            } else {
                appendLine(remainder, stream: stream, phase: phase, runID: runID, logBuffer: logBuffer)
            }
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

    private func finishCurrentPartial(stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) -> Bool {
        guard let entryID = partialEntryIDs.removeValue(forKey: stream) else { return false }
        if logBuffer.finishPartial(entryID: entryID) { return true }
        return false
    }

    private func appendLine(_ data: Data, stream: RunOutputStream, phase: RunOutputPhase, runID: UUID, logBuffer: LogBuffer) {
        var line = String(decoding: data, as: UTF8.self)
        if line.last == "\r" { line.removeLast() }
        logBuffer.append(runID: runID, stream: stream, phase: phase, text: line + "\n")
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
}
