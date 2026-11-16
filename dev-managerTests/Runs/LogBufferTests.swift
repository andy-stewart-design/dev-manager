import Foundation
import Testing
@testable import dev_manager

@Suite(.serialized)
struct LogBufferTests {
    @Test("complete lines do not create partial rows")
    @MainActor
    func completeLinesAndEntryBound() {
        let buffer = LogBuffer()
        let accumulator = RunOutputAccumulator()
        let runID = UUID()
        let data = Data(String(repeating: "x\n", count: 100_000).utf8)

        accumulator.consume(data: data, stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.finish(stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)

        #expect(buffer.entries.count <= LogBuffer.maximumEntries)
        #expect(buffer.entries.reduce(0) { $0 + $1.text.utf8.count } <= LogBuffer.maximumBytes)
        #expect(buffer.didTruncate)
        #expect(buffer.entries.contains { $0.text.contains("truncated") })
    }

    @Test("evicted payloads are released before storage compaction")
    @MainActor
    func evictedPayloadsAreReleasedBeforeCompaction() {
        let buffer = LogBuffer()
        let runID = UUID()
        let payload = String(repeating: "x", count: 16 * 1024)

        for index in 0..<200 {
            buffer.append(runID: runID, stream: .stdout, phase: .command, text: "\(index)-\(payload)\n")
        }

        let (snapshot, didTruncate) = buffer.snapshot()
        let mirror = Mirror(reflecting: buffer)
        let storage = mirror.children.first { $0.label == "storage" }?.value as? [RunLogEntry]
        let headIndex = mirror.children.first { $0.label == "headIndex" }?.value as? Int
        #expect(snapshot.count < 200)
        #expect(didTruncate)
        #expect(headIndex ?? 0 > 0)
        #expect(headIndex ?? 1024 < 1024)
        #expect(storage?.prefix(headIndex ?? 0).allSatisfy { $0.text.isEmpty } == true)
    }

    @Test("unterminated partial output has a bounded explanatory marker")
    @MainActor
    func unterminatedLineIsBounded() {
        let buffer = LogBuffer()
        let accumulator = RunOutputAccumulator()
        let runID = UUID()

        accumulator.consume(data: Data(repeating: UInt8(ascii: "x"), count: 131_072), stream: .stderr, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.finish(stream: .stderr, phase: .command, runID: runID, logBuffer: buffer)

        #expect(buffer.entries.reduce(0) { $0 + $1.text.utf8.count } <= LogBuffer.maximumBytes)
        #expect(buffer.entries.contains { $0.text.contains("unterminated") || $0.text.contains("truncated") })
    }

    @Test("partial lines preserve split UTF8 CR progress blanks and stream order")
    @MainActor
    func partialLineSemantics() {
        let buffer = LogBuffer()
        let accumulator = RunOutputAccumulator()
        let runID = UUID()

        accumulator.consume(data: Data("one\n\nprogress 1\r".utf8), stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.consume(data: Data("progress 2\rfinal\n".utf8), stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.consume(data: Data("err\n".utf8), stream: .stderr, phase: .command, runID: runID, logBuffer: buffer)
        let smile = Array("🙂\n".utf8)
        accumulator.consume(data: Data(smile.prefix(2)), stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.consume(data: Data(smile.dropFirst(2)), stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.finish(stream: .stdout, phase: .command, runID: runID, logBuffer: buffer)
        accumulator.finish(stream: .stderr, phase: .command, runID: runID, logBuffer: buffer)

        let output = buffer.entries
        #expect(output.filter { $0.stream == .stdout }.contains { $0.text == "one\n" })
        #expect(output.contains { $0.text == "\n" })
        #expect(output.contains { $0.stream == .stdout && $0.text == "final\n" })
        #expect(output.contains { $0.stream == .stderr && $0.text == "err\n" })
        #expect(output.contains { $0.text == "🙂\n" })
        #expect(output.filter { $0.text.contains("progress") }.count <= 1)
    }
}
