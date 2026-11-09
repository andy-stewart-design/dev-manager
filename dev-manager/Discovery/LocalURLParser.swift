import Foundation

/// Incremental, stream-local parser for URLs printed by development servers.
/// Feed instances from one serialized run; state is kept separately for stdout
/// and stderr and is bounded even when a command prints an unterminated line.
nonisolated struct LocalURLParser: Sendable {
    private enum ControlState: Sendable {
        case normal
        case escape
        case csi
        case osc
        case oscEscape
    }

    private struct StreamState: Sendable {
        var utf8Remainder = Data()
        var text = ""
        var controlState: ControlState = .normal
    }

    private var states: [RunOutputStream: StreamState] = [:]
    private var emitted = Set<LocalURLCandidate>()
    private let maximumPendingCharacters: Int
    private static let maximumCandidates = 256

    nonisolated init(maximumPendingCharacters: Int = 16_384) {
        self.maximumPendingCharacters = max(256, maximumPendingCharacters)
    }

    /// Feeds one output chunk and returns newly discovered candidates only.
    nonisolated mutating func feed(_ data: Data, from stream: RunOutputStream) -> [LocalURLCandidate] {
        guard !data.isEmpty else { return [] }
        var state = states[stream, default: StreamState()]
        state.utf8Remainder.append(data)
        let (complete, remainder) = Self.splitUTF8Remainder(state.utf8Remainder)
        state.utf8Remainder = remainder
        let text = String(decoding: complete, as: UTF8.self)
        state.text.append(Self.stripControls(text, state: &state.controlState))
        let candidates = extract(from: &state.text)
        states[stream] = state
        return candidates
    }

    /// Flushes both incomplete UTF-8 and a final unterminated URL token.
    nonisolated mutating func finish(_ stream: RunOutputStream) -> [LocalURLCandidate] {
        var state = states[stream, default: StreamState()]
        if !state.utf8Remainder.isEmpty {
            state.text.append(Self.stripControls(String(decoding: state.utf8Remainder, as: UTF8.self), state: &state.controlState))
            state.utf8Remainder.removeAll(keepingCapacity: false)
        }
        // An unfinished OSC/CSI cannot contain a useful URL after formatting is removed.
        let candidates = extract(from: &state.text, flush: true)
        states[stream] = state
        return candidates
    }

    private nonisolated mutating func extract(from text: inout String, flush: Bool = false) -> [LocalURLCandidate] {
        var found: [LocalURLCandidate] = []
        while !text.isEmpty {
            let http = text.range(of: "http://", options: [.caseInsensitive])
            let https = text.range(of: "https://", options: [.caseInsensitive])
            let start: Range<String.Index>?
            switch (http, https) {
            case let (a?, b?): start = a.lowerBound < b.lowerBound ? a : b
            case let (a?, nil): start = a
            case let (nil, b?): start = b
            case (nil, nil):
                if text.count > maximumPendingCharacters {
                    text = String(text.suffix(maximumPendingCharacters))
                }
                return found
            }

            text.removeSubrange(text.startIndex..<start!.lowerBound)
            guard let end = text.firstIndex(where: Self.isTokenDelimiter) else {
                if flush {
                    let token = Self.trimPunctuation(text)
                    text.removeAll(keepingCapacity: true)
                    appendIfEligible(token, to: &found)
                } else if text.count > maximumPendingCharacters {
                    text = String(text.suffix(maximumPendingCharacters))
                }
                return found
            }

            let token = Self.trimPunctuation(String(text[..<end]))
            text.removeSubrange(text.startIndex...end)
            appendIfEligible(token, to: &found)
        }
        return found
    }

    private nonisolated mutating func appendIfEligible(_ token: String, to found: inout [LocalURLCandidate]) {
        guard emitted.count < Self.maximumCandidates,
              let candidate = LocalURLCandidate(string: token),
              emitted.insert(candidate).inserted else { return }
        found.append(candidate)
    }

    private nonisolated static func isTokenDelimiter(_ scalar: Character) -> Bool {
        scalar.isWhitespace || "\"'<>\u{007B}\u{007D}|,;`".contains(scalar)
    }

    private nonisolated static func trimPunctuation(_ value: String) -> String {
        var result = value
        while let last = result.last, ".,;!".contains(last) { result.removeLast() }
        // A closing parenthesis is usually prose punctuation; preserve balanced URL path parentheses.
        while result.last == ")" && result.filter({ $0 == ")" }).count > result.filter({ $0 == "(" }).count {
            result.removeLast()
        }
        return result
    }

    private nonisolated static func stripControls(_ value: String, state: inout ControlState) -> String {
        var output = String()
        output.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch state {
            case .normal:
                if scalar.value == 0x1B { state = .escape }
                else if scalar.value == 0x9B { state = .csi }
                else if scalar.value == 0x9D { state = .osc }
                else { output.unicodeScalars.append(scalar) }
            case .escape:
                if scalar == "[" { state = .csi }
                else if scalar == "]" { state = .osc }
                else { state = .normal }
            case .csi:
                if (0x40...0x7E).contains(scalar.value) { state = .normal }
            case .osc:
                if scalar.value == 0x07 { state = .normal }
                else if scalar.value == 0x1B { state = .oscEscape }
            case .oscEscape:
                state = scalar == "\\" || scalar.value == 0x07 ? .normal : .osc
            }
        }
        return output
    }

    private nonisolated static func splitUTF8Remainder(_ data: Data) -> (Data, Data) {
        guard !data.isEmpty else { return (data, Data()) }
        var continuationCount = 0
        for byte in data.reversed() {
            guard (byte & 0xC0) == 0x80 else { break }
            continuationCount += 1
        }
        let leadOffset: Int
        if continuationCount == 0 {
            leadOffset = data.count - 1
        } else {
            guard continuationCount < data.count else { return (data, Data()) }
            leadOffset = data.count - continuationCount - 1
        }
        let lead = data[data.index(data.startIndex, offsetBy: leadOffset)]
        let expected: Int
        if lead >= 0xC0 && lead <= 0xDF { expected = 2 }
        else if lead >= 0xE0 && lead <= 0xEF { expected = 3 }
        else if lead >= 0xF0 && lead <= 0xF4 { expected = 4 }
        else { return (data, Data()) }
        guard continuationCount < expected - 1 else { return (data, Data()) }
        return (Data(data.prefix(leadOffset)), Data(data.suffix(continuationCount + 1)))
    }
}
