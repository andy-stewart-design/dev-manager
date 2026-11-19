import Foundation
import Testing
@testable import dev_manager

@Suite("GitHub login values")
struct GitHubLoginValueTests {
    @Test func hostnameRootsAndRejections() throws {
        #expect(try GitHubHostname(" HTTPS://GitHub.COM/ \n").value == "github.com")
        #expect(try GitHubHostname("corp.ebay.github.com").value == "corp.ebay.github.com")
        #expect(try GitHubHostname("xn--bcher-kva.example").value == "xn--bcher-kva.example")
        for input in ["http://github.com", "https://@github.com", "https://user@github.com", "https://github.com:443", "https://github.com:", "https://github.com?", "https://github.com#", "https://github.com/repo", "[::1]", "a..com", "-a.com", "a-.com", "a b.com", "bücher.example", String(repeating: "a", count: 64) + ".com", String(repeating: "a.", count: 127) + "aa"] {
            #expect(throws: (any Error).self) { try GitHubHostname(input) }
        }
    }

    @Test func deviceURLPolicy() throws {
        let host = try GitHubHostname("github.com")
        for text in ["https://github.com/login/device", "https://github.com/login/device/"] {
            #expect(host.validatesDeviceURL(try #require(URL(string: text))))
        }
        for text in ["http://github.com/login/device", "https://other.com/login/device", "https://127.0.0.1/login/device", "https://@github.com/login/device", "https://github.com:443/login/device", "https://github.com:/login/device", "https://github.com/login/device?", "https://github.com/login/device#", "https://github.com/callback"] {
            #expect(!host.validatesDeviceURL(try #require(URL(string: text))))
        }
    }

    @Test func splitUTF8ANSIAndCRLF() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        let text = "\u{1b}[32m! First copy your one-time code: aB12-C9D0\u{1b}[0m\r\nOpen this URL to continue in your web browser: https://github.com/login/device\r\n✓ Authentication complete.\n! Authentication credentials saved in plain text\n"
        var events: [GitHubDeviceFlowEvent] = []
        for byte in text.utf8 { events += try parser.consume(Data([byte]), stream: .stderr) }
        events += try parser.finish()
        #expect(events == [.deviceCode("aB12-C9D0"), .verificationURL(try #require(URL(string: "https://github.com/login/device"))), .authenticationComplete, .plaintextStorageWarning])
    }

    @Test func streamBuffersAndDuplicates() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        _ = try parser.consume(Data("! First copy your ".utf8), stream: .stderr)
        _ = try parser.consume(Data("Open this URL to continue in your web browser: https://github.com/login/device\n".utf8), stream: .stdout)
        #expect(try parser.consume(Data("one-time code: ABC1-2345\n".utf8), stream: .stderr) == [.deviceCode("ABC1-2345")])
        #expect(try parser.consume(Data("! First copy your one-time code: ABC1-2345\nOpen this URL to continue in your web browser: https://github.com/login/device\n".utf8), stream: .stderr).isEmpty)
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try parser.consume(Data("! First copy your one-time code: OTHER-123\n".utf8), stream: .stderr) }
    }

    @Test func conflictsAndSafeFailures() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        _ = try parser.consume(Data("Open this URL to continue in your web browser: https://github.com/login/device\n".utf8), stream: .stderr)
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try parser.consume(Data("Open this URL to continue in your web browser: https://github.com/login/device/\n".utf8), stream: .stderr) }
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try parser.consume(Data("- gh config set -h other.com git_protocol https\n".utf8), stream: .stderr) }
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try parser.consume(Data("secret-token-value\n".utf8), stream: .stderr) }
        #expect(!GitHubLoginFailure.unsupportedOutput.localizedDescription.contains("secret-token-value"))
        #expect(throws: GitHubLoginFailure.invalidVerificationURL) { try parser.consume(Data("Open this URL to continue in your web browser: https://other.com/login/device\n".utf8), stream: .stderr) }
    }

    @Test func clipboardOutput() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        #expect(try parser.consume(Data("! One-time code (ABC1-2345) copied to clipboard\n".utf8), stream: .stderr) == [.deviceCode("ABC1-2345")])
        for bad in ["! One-time code (ABC1-2345) copied to clipboard extra", "! One-time code (ABC1-2345 copied to clipboard", "! One-time code (ABC1--2345) copied to clipboard"] {
            var invalid = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
            #expect(throws: GitHubLoginFailure.unsupportedOutput) { try invalid.consume(Data((bad + "\n").utf8), stream: .stderr) }
        }
    }

    @Test func clipboardFailureFallback() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        let text = "! Failed to copy one-time code to clipboard\n secret diagnostic\n! First copy your one-time code: ABC1-2345\nOpen this URL to continue in your web browser: https://github.com/login/device\n"
        let events = try parser.consume(Data(text.utf8), stream: .stderr) + parser.finish()
        #expect(events == [.deviceCode("ABC1-2345"), .verificationURL(try #require(URL(string: "https://github.com/login/device")))])
        var invalid = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try invalid.consume(Data(" unexpected\n".utf8), stream: .stderr) }
        #expect(!GitHubLoginFailure.unsupportedOutput.localizedDescription.contains("secret diagnostic"))
    }

    @Test func limitAndIncompleteFlow() throws {
        var parser = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        _ = try parser.consume(Data("! First copy your one-time code: AB12".utf8), stream: .stderr)
        #expect(throws: GitHubLoginFailure.unsupportedOutput) { try parser.finish() }
        var flood = GitHubDeviceFlowParser(hostname: try GitHubHostname("github.com"))
        _ = try flood.consume(Data(repeating: 10, count: 65_536), stream: .stdout)
        #expect(throws: GitHubLoginFailure.outputLimitExceeded) { try flood.consume(Data([10]), stream: .stderr) }
    }
}
