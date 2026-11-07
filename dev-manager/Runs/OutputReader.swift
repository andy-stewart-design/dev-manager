import Foundation

/// A bounded handoff between pipe queues and the main actor. At most one main-actor
/// drain task exists per run, and old data is dropped with accounting under pressure.
final class OutputInbox: @unchecked Sendable {
    static let maximumPendingBytes = 256 * 1024

    private struct Chunk {
        let stream: RunOutputStream
        let data: Data
        let eof: Bool
        let droppedBytes: Int
    }

    private let lock = NSLock()
    private var queue: [Chunk] = []
    private var pendingBytes = 0
    private var droppedBytes: [RunOutputStream: Int] = [:]
    private var drainScheduled = false
    private let deliver: @MainActor (RunOutputStream, Data, Bool, Int) -> Void

    init(deliver: @escaping @MainActor (RunOutputStream, Data, Bool, Int) -> Void) {
        self.deliver = deliver
    }

    func enqueue(stream: RunOutputStream, data: Data, eof: Bool) {
        lock.lock()
        if !data.isEmpty {
            queue.append(Chunk(stream: stream, data: data, eof: false, droppedBytes: 0))
            pendingBytes += data.count
            while pendingBytes > Self.maximumPendingBytes {
                guard let index = queue.firstIndex(where: { !$0.data.isEmpty }) else { break }
                let removed = queue.remove(at: index)
                pendingBytes -= removed.data.count
                droppedBytes[removed.stream, default: 0] += removed.data.count + removed.droppedBytes
            }
        }
        if eof {
            queue.append(Chunk(stream: stream, data: Data(), eof: true, droppedBytes: 0))
        }
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        lock.unlock()

        if shouldSchedule {
            Task { @MainActor [weak self] in self?.drain() }
        }
    }

    @MainActor
    private func drain() {
        while true {
            lock.lock()
            guard !queue.isEmpty || !droppedBytes.isEmpty else {
                drainScheduled = false
                lock.unlock()
                return
            }
            let dropped = droppedBytes
            droppedBytes.removeAll(keepingCapacity: true)
            let chunk = queue.isEmpty ? nil : queue.removeFirst()
            if let chunk { pendingBytes -= chunk.data.count }
            lock.unlock()

            for (stream, count) in dropped {
                deliver(stream, Data(), false, count)
            }
            if let chunk {
                deliver(chunk.stream, chunk.data, chunk.eof, chunk.droppedBytes)
            }
        }
    }
}

/// Reads one pipe away from the main actor and coalesces output before delivery.
final class OutputReader: @unchecked Sendable {
    private let handle: FileHandle
    private let stream: RunOutputStream
    private let callback: @Sendable (RunOutputStream, Data, Bool) -> Void
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending = Data()
    private var flushWork: DispatchWorkItem?
    private var stopped = false

    init(handle: FileHandle, stream: RunOutputStream, callback: @escaping @Sendable (RunOutputStream, Data, Bool) -> Void) {
        self.handle = handle
        self.stream = stream
        self.callback = callback
        self.queue = DispatchQueue(label: "dev-manager.output.\(stream.rawValue)", qos: .utility)
        queue.async { [weak self] in self?.readLoop() }
    }

    func cancel() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        flushWork?.cancel()
        flushWork = nil
        let remainder = pending
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
        try? handle.close()
        if !remainder.isEmpty { callback(stream, remainder, true) }
    }

    private func readLoop() {
        while true {
            do {
                let data = try handle.read(upToCount: 64 * 1024) ?? Data()
                if data.isEmpty {
                    finish()
                    return
                }
                append(data)
            } catch {
                finish()
                return
            }
        }
    }

    private func append(_ data: Data) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        pending.append(data)
        let shouldFlush = pending.count >= 16 * 1024
        if shouldFlush {
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            flushWork?.cancel()
            flushWork = nil
            lock.unlock()
            callback(stream, batch, false)
        } else if flushWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            flushWork = work
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(50), execute: work)
        } else {
            lock.unlock()
        }
    }

    private func flush() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        flushWork = nil
        lock.unlock()
        if !batch.isEmpty { callback(stream, batch, false) }
    }

    private func finish() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        flushWork?.cancel()
        flushWork = nil
        let remainder = pending
        pending.removeAll(keepingCapacity: false)
        lock.unlock()
        try? handle.close()
        if !remainder.isEmpty { callback(stream, remainder, false) }
        callback(stream, Data(), true)
    }
}
