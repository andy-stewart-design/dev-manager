import Foundation

nonisolated enum GitHubEnvironmentCredential: String, Equatable, Sendable {
    case ghToken = "GH_TOKEN", githubToken = "GITHUB_TOKEN"
    case ghEnterpriseToken = "GH_ENTERPRISE_TOKEN", githubEnterpriseToken = "GITHUB_ENTERPRISE_TOKEN"
}

nonisolated enum GitHubCredentialSource: Equatable, Sendable {
    case environment(GitHubEnvironmentCredential)
    case stored, keychain, unknown
}

nonisolated enum GitHubAuthFailure: Equatable, Sendable {
    case timeout, network, tls
}

nonisolated enum GitHubAuthUnsupportedReason: Equatable, Sendable {
    case invalidHost, cliVersion, capability
}

nonisolated enum GitHubAuthUnverifiedReason: Equatable, Sendable {
    case processFailure, malformedResponse, ambiguousAccounts, accountError, unknownState
}

nonisolated struct GitHubAuthStatus: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case checking, notSignedIn
        case authenticated(login: String, source: GitHubCredentialSource)
        case invalidCredentials
        case unavailable(reason: GitHubAuthFailure)
        case unsupported(reason: GitHubAuthUnsupportedReason)
        case unverified(reason: GitHubAuthUnverifiedReason)
    }
    let host: String
    let outcome: Outcome
    let environmentCredential: GitHubEnvironmentCredential?
}

nonisolated enum GitHubAuthService {
    typealias Runner = ProvisioningGitHubCLIInspector.Runner

    static func status(
        using context: ProvisioningGitHubCLIContext,
        hostname: String = "github.com",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        run: @escaping Runner = { executable, arguments, environment, timeout in
            await ProvisioningCommandRunner.run(executable, arguments: arguments, environment: environment, timeout: timeout)
        }
    ) async -> GitHubAuthStatus {
        guard let host = normalizedHost(hostname) else {
            return GitHubAuthStatus(host: "", outcome: .unsupported(reason: .invalidHost), environmentCredential: nil)
        }
        let credential = environmentCredential(host: host, environment: environment)
        guard let modern = supportsVersion(context.version) else {
            return GitHubAuthStatus(host: host, outcome: .unsupported(reason: .cliVersion), environmentCredential: credential)
        }
        var childEnvironment = environment
        // The runner merges its input over the inherited environment, so empty overrides
        // are necessary even when the caller supplies a restricted environment.
        childEnvironment["GH_DEBUG"] = ""
        childEnvironment["DEBUG"] = ""
        childEnvironment["GH_FORCE_TTY"] = ""
        childEnvironment["GH_PROMPT_DISABLED"] = "1"
        childEnvironment["GH_NO_UPDATE_NOTIFIER"] = "1"
        childEnvironment["NO_COLOR"] = "1"
        var arguments = ["auth", "status", "--hostname", host, "--json", "hosts"]
        if modern { arguments.append("--no-refresh") }
        let result = await run(context.executableURL, arguments, childEnvironment, ProvisioningConfiguration.commandTimeout)
        return parse(result, hostname: host, environment: environment)
    }

    /// Converts untrusted process output into a fixed vocabulary; no diagnostic text escapes.
    static func parse(_ result: ProvisioningProcessResult, hostname: String = "github.com", environment: [String: String] = [:]) -> GitHubAuthStatus {
        guard let host = normalizedHost(hostname) else {
            return GitHubAuthStatus(host: "", outcome: .unsupported(reason: .invalidHost), environmentCredential: nil)
        }
        let credential = environmentCredential(host: host, environment: environment)
        func status(_ outcome: GitHubAuthStatus.Outcome) -> GitHubAuthStatus {
            GitHubAuthStatus(host: host, outcome: outcome, environmentCredential: credential)
        }
        if result.timedOut { return status(.unavailable(reason: .timeout)) }
        guard let data = result.stdout.data(using: .utf8),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            let diagnostic = result.stderr.lowercased()
            if diagnostic.contains("unknown flag") || diagnostic.contains("unknown shorthand flag") {
                return status(.unsupported(reason: .capability))
            }
            if let failure = technicalFailure(diagnostic) { return status(failure) }
            return status(.unverified(reason: result.succeeded ? .malformedResponse : .processFailure))
        }
        // Case-insensitive duplicate keys are ambiguous, not multiple independent hosts.
        let matching = document.hosts.filter { $0.key.lowercased() == host }
        guard matching.count <= 1 else { return status(.unverified(reason: .ambiguousAccounts)) }
        guard let entries = matching.first?.value else {
            return status(result.succeeded && document.hosts.isEmpty ? .notSignedIn : .unverified(reason: .processFailure))
        }
        if entries.isEmpty { return status(result.succeeded ? .notSignedIn : .unverified(reason: .processFailure)) }
        let active = entries.filter(\.active)
        guard active.count == 1 else { return status(.unverified(reason: .ambiguousAccounts)) }
        let entry = active[0]
        guard normalizedHost(entry.host) == host else { return status(.unverified(reason: .malformedResponse)) }
        switch entry.state {
        case "refresh_expired": return status(.invalidCredentials)
        case "error": return status(technicalFailure(entry.error ?? "") ?? .unverified(reason: .accountError))
        case "timeout": return status(.unavailable(reason: .timeout))
        case "success":
            guard result.succeeded else { return status(.unverified(reason: .processFailure)) }
            guard let login = entry.login, !login.isEmpty, login.utf8.count <= 100,
                  login.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }) else {
                return status(.unverified(reason: .malformedResponse))
            }
            let credentialSource = source(entry.tokenSource)
            if case .environment(let token) = credentialSource {
                let publicHost = isPublicHost(host)
                let publicToken = token == .ghToken || token == .githubToken
                guard publicHost == publicToken else { return status(.unverified(reason: .malformedResponse)) }
            }
            return status(.authenticated(login: login, source: credentialSource))
        default: return status(.unverified(reason: .unknownState))
        }
    }

    private struct Document: Decodable {
        let hosts: [String: [Entry]]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            guard container.allKeys.map(\.stringValue) == ["hosts"] else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected top-level keys"))
            }
            hosts = try container.decode([String: [Entry]].self, forKey: DynamicKey(stringValue: "hosts")!)
        }
    }
    private struct DynamicKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        let intValue: Int? = nil
        init?(intValue: Int) { return nil }
    }
    private struct Entry: Decodable {
        let state: String
        let active: Bool
        let host: String
        let login: String?
        let tokenSource: String?
        let error: String?
    }

    private static func source(_ value: String?) -> GitHubCredentialSource {
        switch value {
        case "GH_TOKEN": return .environment(.ghToken)
        case "GITHUB_TOKEN": return .environment(.githubToken)
        case "GH_ENTERPRISE_TOKEN": return .environment(.ghEnterpriseToken)
        case "GITHUB_ENTERPRISE_TOKEN": return .environment(.githubEnterpriseToken)
        case "keyring", "keychain": return .keychain
        case "hosts.yml", "GH_CONFIG_DIR/hosts.yml": return .stored
        default:
            guard let value, value.hasPrefix("/"), value.hasSuffix("/hosts.yml"),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return .unknown }
            return .stored
        }
    }

    private static func technicalFailure(_ text: String) -> GitHubAuthStatus.Outcome? {
        let text = text.lowercased()
        if text.contains("http 401") || text.contains("http: 401") || text.contains("refresh_expired") { return .invalidCredentials }
        if text.contains("x509") || text.contains("tls") || text.contains("certificate") { return .unavailable(reason: .tls) }
        if ["dial tcp", "connect", "refused", "no such host", "network", "i/o timeout"].contains(where: text.contains) {
            return .unavailable(reason: .network)
        }
        return nil
    }

    private static func isPublicHost(_ host: String) -> Bool {
        host == "github.com" || host == "github.localhost" || host.hasSuffix(".ghe.com")
    }

    private static func environmentCredential(host: String, environment: [String: String]) -> GitHubEnvironmentCredential? {
        let publicHost = isPublicHost(host)
        let candidates: [GitHubEnvironmentCredential] = publicHost ? [.ghToken, .githubToken] : [.ghEnterpriseToken, .githubEnterpriseToken]
        return candidates.first { !(environment[$0.rawValue] ?? "").isEmpty }
    }

    private static func normalizedHost(_ value: String) -> String? {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, host.utf8.count <= 253, host.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return nil }
        return host
    }

    // Only known stable major version 2 is accepted; no prerelease or suffixes.
    private static func supportsVersion(_ value: String) -> Bool? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let major = Int(parts[0]), let minor = Int(parts[1]), Int(parts[2]) != nil,
              major == 2, minor >= 81 else { return nil }
        return minor >= 103
    }
}
