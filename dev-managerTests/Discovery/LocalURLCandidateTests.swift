import Foundation
import Testing
@testable import dev_manager

@Suite("Local URL candidate parsing")
struct LocalURLCandidateTests {
    @Test("Vite and Next output keep only the local URL")
    func frameworkOutput() {
        let vite = parse("  Local:   http://localhost:3000/\n  Network: http://192.168.1.20:3000/\n")
        #expect(vite.map(\.absoluteString) == ["http://localhost:3000/"])

        let next = parse("- Local:        http://localhost:3000\n- Network:      http://172.16.48.137:3000\n")
        #expect(next.map(\.absoluteString) == ["http://localhost:3000/"])
    }

    @Test("ANSI, UTF-8 and arbitrary chunks are streamed safely")
    func splitOutput() {
        let input = "\u{1B}[32mLocal:\u{1B}[0m http://LOCALHOST:4321/docs/é?q=1\u{1B}[0m\n"
        let values = Array(input.utf8).chunked(into: 1)
        var parser = LocalURLParser()
        var result: [LocalURLCandidate] = []
        for chunk in values { result += parser.feed(Data(chunk), from: .stdout) }
        result += parser.finish(.stdout)
        #expect(result.map(\.absoluteString) == ["http://localhost:4321/docs/%C3%A9?q=1"])
    }

    @Test("loopback policy, ports, schemes, and paths")
    func policy() {
        let accepted = parse("http://127.0.0.1:8080/base?q=1 https://[::1]:8443/app")
        #expect(accepted.map(\.absoluteString) == ["http://127.0.0.1:8080/base?q=1", "https://[::1]:8443/app"])

        let rejected = parse("ws://localhost:1 http://localhost.example.com:2 http://example.com/localhost http://10.0.0.1:3 http://localhost:99999")
        #expect(rejected.isEmpty)
    }

    @Test("duplicate roots and meaningful paths collapse correctly")
    func deduplication() {
        let values = parse("http://localhost:3000 http://localhost:3000/ http://localhost:3000/base http://localhost:3000/base")
        #expect(values.map(\.absoluteString) == ["http://localhost:3000/", "http://localhost:3000/base"])
    }

    @Test("an incomplete URL is not emitted at a chunk boundary")
    func incompleteChunk() {
        var parser = LocalURLParser()
        #expect(parser.feed(Data("http://local".utf8), from: .stderr).isEmpty)
        #expect(parser.feed(Data("host:3000/path".utf8), from: .stderr).isEmpty)
        #expect(parser.finish(.stderr).map(\.absoluteString) == ["http://localhost:3000/path"])
    }

    private func parse(_ text: String) -> [LocalURLCandidate] {
        var parser = LocalURLParser()
        var result = parser.feed(Data(text.utf8), from: .stdout)
        result += parser.finish(.stdout)
        return result
    }
}

private extension Array where Element == UInt8 {
    func chunked(into size: Int) -> [[UInt8]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
