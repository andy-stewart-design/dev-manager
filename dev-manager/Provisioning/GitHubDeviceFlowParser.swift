import Foundation

nonisolated enum GitHubDeviceFlowStream: Sendable { case stdout, stderr }
nonisolated enum GitHubDeviceFlowEvent: Equatable, Sendable {
    case deviceCode(String), clipboardCopied, verificationURL(URL), plaintextStorageWarning, authenticationComplete
}
nonisolated enum GitHubLoginFailure: Error, Equatable, Sendable, LocalizedError {
    case unsupportedCLI, unsupportedOutput, invalidVerificationURL, expired, processFailed
    case deadlineExceeded, outputLimitExceeded, cancelled, unavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedCLI: "This GitHub CLI version is not supported."
        case .unsupportedOutput: "GitHub CLI returned unrecognized login output."
        case .invalidVerificationURL: "GitHub CLI returned an invalid verification URL."
        case .expired: "The device login expired."
        case .processFailed: "GitHub CLI could not complete login."
        case .deadlineExceeded: "The login timed out."
        case .outputLimitExceeded: "GitHub CLI produced too much output."
        case .cancelled: "The login was cancelled."
        case .unavailable: "GitHub login is unavailable."
        }
    }
}

nonisolated struct GitHubDeviceFlowParser {
    private let hostname: GitHubHostname
    private var stdout = Data()
    private var stderr = Data()
    private var received = 0
    private var code: String?
    private var url: URL?
    private var diagnosticStream: GitHubDeviceFlowStream?

    init(hostname: GitHubHostname) { self.hostname = hostname }

    mutating func consume(_ data: Data, stream: GitHubDeviceFlowStream) throws -> [GitHubDeviceFlowEvent] {
        guard data.count <= 65_536 - received else { throw GitHubLoginFailure.outputLimitExceeded }
        received += data.count
        var pending: Data
        switch stream {
        case .stdout: pending = stdout; stdout.removeAll()
        case .stderr: pending = stderr; stderr.removeAll()
        }
        pending.append(data)
        var events: [GitHubDeviceFlowEvent] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            events += try parse(line, stream: stream)
        }
        switch stream {
        case .stdout: stdout = pending
        case .stderr: stderr = pending
        }
        return events
    }

    mutating func finish() throws -> [GitHubDeviceFlowEvent] {
        var events: [GitHubDeviceFlowEvent] = []
        if !stdout.isEmpty { events += try parse(stdout, stream: .stdout); stdout.removeAll() }
        if !stderr.isEmpty { events += try parse(stderr, stream: .stderr); stderr.removeAll() }
        guard diagnosticStream == nil, code != nil, url != nil else { throw GitHubLoginFailure.unsupportedOutput }
        return events
    }

    private mutating func parse(_ data: Data, stream: GitHubDeviceFlowStream) throws -> [GitHubDeviceFlowEvent] {
        guard var line = String(data: data, encoding: .utf8) else { throw GitHubLoginFailure.unsupportedOutput }
        if line.hasSuffix("\r") { line.removeLast() }
        // Only SGR formatting is accepted, not arbitrary terminal control sequences.
        var clean = ""
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 27 {
                index += 1
                guard index < scalars.count, scalars[index].value == 91 else { throw GitHubLoginFailure.unsupportedOutput }
                index += 1
                while index < scalars.count && ((48...57).contains(scalars[index].value) || scalars[index].value == 59) { index += 1 }
                guard index < scalars.count, scalars[index].value == 109 else { throw GitHubLoginFailure.unsupportedOutput }
            } else {
                guard scalar.value >= 32 && scalar.value != 127 && !(128...159).contains(scalar.value) else { throw GitHubLoginFailure.unsupportedOutput }
                clean.unicodeScalars.append(scalar)
            }
            index += 1
        }
        if diagnosticStream == stream {
            diagnosticStream = nil
            guard clean.hasPrefix(" "), !clean.trimmingCharacters(in: .whitespaces).isEmpty else { throw GitHubLoginFailure.unsupportedOutput }
            return []
        }
        if clean == "! Failed to copy one-time code to clipboard" {
            diagnosticStream = stream
            return []
        }
        if clean.isEmpty { return [] }
        for prefix in ["! ", "✓ ", "✔ ", "√ "] where clean.hasPrefix(prefix) {
            clean.removeFirst(prefix.count)
            break
        }
        let codePrefix = "First copy your one-time code: "
        let copiedPrefix = "One-time code ("
        var candidate: String?
        var copied = false
        if clean.hasPrefix(codePrefix) {
            candidate = String(clean.dropFirst(codePrefix.count))
        } else if clean.hasPrefix(copiedPrefix) {
            let suffix = ") copied to clipboard"
            guard clean.hasSuffix(suffix), clean.count >= copiedPrefix.count + suffix.count else { throw GitHubLoginFailure.unsupportedOutput }
            candidate = String(clean.dropFirst(copiedPrefix.count).dropLast(suffix.count))
            copied = true
        }
        if let candidate {
            let bytes = Array(candidate.utf8)
            guard (4...32).contains(bytes.count), bytes.first != 45, bytes.last != 45,
                  bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }),
                  !candidate.contains("--") else { throw GitHubLoginFailure.unsupportedOutput }
            if let code { guard code == candidate else { throw GitHubLoginFailure.unsupportedOutput }; return copied ? [.clipboardCopied] : [] }
            code = candidate
            return copied ? [.deviceCode(candidate), .clipboardCopied] : [.deviceCode(candidate)]
        }
        let urlPrefix = "Open this URL to continue in your web browser: "
        if clean.hasPrefix(urlPrefix) {
            let candidate = String(clean.dropFirst(urlPrefix.count))
            guard let parsed = URL(string: candidate), parsed.absoluteString == candidate, hostname.validatesDeviceURL(parsed) else { throw GitHubLoginFailure.invalidVerificationURL }
            if let url { guard url.absoluteString == parsed.absoluteString else { throw GitHubLoginFailure.unsupportedOutput }; return [] }
            url = parsed
            return [.verificationURL(parsed)]
        }
        if clean == "Authentication complete." { return [.authenticationComplete] }
        if clean == "Authentication credentials saved in plain text" { return [.plaintextStorageWarning] }
        if clean == "Configured git protocol" || clean == "You were already logged in to this account" ||
            clean == "Host issues expiring refreshable token" || clean == "Received expiring refreshable token" ||
            clean == "Host did not issue an expiring refreshable token" { return [] }
        let configPrefix = "- gh config set -h "
        if clean.hasPrefix(configPrefix) {
            guard clean == configPrefix + hostname.value + " git_protocol https" else { throw GitHubLoginFailure.unsupportedOutput }
            return []
        }
        let loginPrefix = "Logged in as "
        if clean.hasPrefix(loginPrefix) {
            let login = String(clean.dropFirst(loginPrefix.count))
            let bytes = Array(login.utf8)
            guard (1...39).contains(bytes.count), bytes.first != 45, bytes.last != 45, !login.contains("--"),
                  bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { throw GitHubLoginFailure.unsupportedOutput }
            return []
        }
        if clean.hasPrefix("failed to authenticate via web browser:") { throw GitHubLoginFailure.processFailed }
        throw GitHubLoginFailure.unsupportedOutput
    }
}
