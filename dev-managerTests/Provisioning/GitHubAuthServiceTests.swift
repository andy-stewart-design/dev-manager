import Foundation
import Testing
@testable import dev_manager

@MainActor
struct GitHubAuthServiceTests {
    private func result(_ stdout: String = "", stderr: String = "", success: Bool = true, timeout: Bool = false) -> ProvisioningProcessResult {
        ProvisioningProcessResult(succeeded: success, stdout: stdout, stderr: stderr, terminationStatus: success ? 0 : 1, timedOut: timeout)
    }

    private func parse(_ json: String, environment: [String: String] = [:]) -> GitHubAuthStatus {
        GitHubAuthService.parse(result(json), environment: environment)
    }

    @Test func actualSchemaAndPrivacy() {
        let json = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"monalisa","tokenSource":"GH_CONFIG_DIR/hosts.yml","token":"secret-token","gitProtocol":"https","scopes":"repo"}]}}"#
        let status = parse(json, environment: ["GH_TOKEN": "secret-value"])
        #expect(status.outcome == .authenticated(login: "monalisa", source: .stored))
        #expect(status.environmentCredential == .ghToken)
        #expect(!String(describing: status).contains("secret"))
        let unknown = json.replacingOccurrences(of: "GH_CONFIG_DIR/hosts.yml", with: "/secret/path")
        #expect(parse(unknown).outcome == .authenticated(login: "monalisa", source: .unknown))
        #expect(!String(describing: parse(unknown)).contains("/secret/path"))
    }

    @Test func accountsAndEmptyResults() {
        #expect(parse(#"{"hosts":{}}"#).outcome == .notSignedIn)
        #expect(parse(#"{"hosts":{"github.com":[]}}"#).outcome == .notSignedIn)
        let other = #"{"hosts":{"other.example":[{"state":"success","active":true,"host":"other.example","login":"other"}]}}"#
        #expect(parse(other).outcome == .unverified(reason: .processFailure))
        let inactive = #"{"hosts":{"github.com":[{"state":"success","active":false,"host":"github.com","login":"old"},{"state":"error","active":true,"host":"github.com"}]}}"#
        #expect(parse(inactive).outcome == .unverified(reason: .accountError))
        let multiple = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"one"},{"state":"success","active":true,"host":"github.com","login":"two"}]}}"#
        #expect(parse(multiple).outcome == .unverified(reason: .ambiguousAccounts))
        let mismatch = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"other.example","login":"one"}]}}"#
        #expect(parse(mismatch).outcome == .unverified(reason: .malformedResponse))
        #expect(parse("not json").outcome == .unverified(reason: .malformedResponse))
        #expect(GitHubAuthService.parse(result(#"{"hosts":{}}"#, success: false)).outcome == .unverified(reason: .processFailure))
    }

    @Test func unexpectedTopLevelFieldsFailClosed() {
        for json in [#"{"hosts":{},"errors":["secret-marker"]}"#,
                     #"{"hosts":{"github.com":[]},"error":"secret-marker"}"#,
                     #"{"hosts":{},"message":"secret-marker"}"#,
                     #"{"hosts":{},"unknown":true}"#] {
            let status = parse(json)
            #expect(status.outcome == .unverified(reason: .malformedResponse))
            #expect(!String(describing: status).contains("secret-marker"))
        }
    }

    @Test func failuresAreSafe() {
        let expired = #"{"hosts":{"github.com":[{"state":"refresh_expired","active":true,"host":"github.com"}]}}"#
        #expect(parse(expired).outcome == .invalidCredentials)
        #expect(GitHubAuthService.parse(result(stderr: "HTTP 401 secret", success: false)).outcome == .invalidCredentials)
        #expect(GitHubAuthService.parse(result(stderr: "HTTP 403 secret", success: false)).outcome == .unverified(reason: .processFailure))
        #expect(GitHubAuthService.parse(result(stderr: "x509: secret", success: false)).outcome == .unavailable(reason: .tls))
        #expect(GitHubAuthService.parse(result(stderr: "no such host: secret", success: false)).outcome == .unavailable(reason: .network))
        #expect(GitHubAuthService.parse(result(timeout: true)).outcome == .unavailable(reason: .timeout))
        #expect(GitHubAuthService.parse(result(stderr: "unknown flag: --no-refresh secret", success: false)).outcome == .unsupported(reason: .capability))
    }

    @Test func activeAccountDiagnosticsAndPrivacy() {
        let healthy = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"good"},{"state":"error","active":false,"host":"github.com","error":"HTTP 401 secret-marker"}]}}"#
        let healthyStatus = GitHubAuthService.parse(result(healthy, stderr: "HTTP 401 secret-marker"))
        #expect(healthyStatus.outcome == .authenticated(login: "good", source: .unknown))
        #expect(!String(describing: healthyStatus).contains("secret-marker"))
        #expect(GitHubAuthService.parse(result(healthy, stderr: "unknown flag", timeout: true)).outcome == .unavailable(reason: .timeout))
        #expect(GitHubAuthService.parse(result(healthy, stderr: "unknown flag")).outcome == .authenticated(login: "good", source: .unknown))
        let cases: [(String, GitHubAuthStatus.Outcome)] = [
            ("HTTP 401 secret-marker", .invalidCredentials),
            ("x509 certificate secret-marker", .unavailable(reason: .tls)),
            ("dial tcp: connection refused secret-marker", .unavailable(reason: .network)),
            ("generic secret-marker", .unverified(reason: .accountError)),
            ("HTTP 403 secret-marker", .unverified(reason: .accountError))
        ]
        for (message, expected) in cases {
            let json = #"{"hosts":{"github.com":[{"state":"error","active":true,"host":"github.com","error":"MESSAGE"},{"state":"success","active":false,"host":"github.com","login":"other"}]}}"#.replacingOccurrences(of: "MESSAGE", with: message)
            let status = GitHubAuthService.parse(result(json, stderr: "secret-marker"))
            #expect(status.outcome == expected)
            #expect(!String(describing: status).contains("secret-marker"))
        }
    }

    @Test func sourceHostAndPathSafety() {
        let json = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"good","tokenSource":"SOURCE"}]}}"#
        let path = json.replacingOccurrences(of: "SOURCE", with: "/secret-marker/config/hosts.yml")
        let stored = parse(path)
        #expect(stored.outcome == .authenticated(login: "good", source: .stored))
        #expect(!String(describing: stored).contains("secret-marker"))
        let wrongHost = json.replacingOccurrences(of: "SOURCE", with: "GH_ENTERPRISE_TOKEN")
        #expect(parse(wrongHost).outcome == .unverified(reason: .malformedResponse))
    }

    @Test func environmentPrecedence() {
        let env = ["GH_TOKEN": "one", "GITHUB_TOKEN": "two", "GH_ENTERPRISE_TOKEN": "three", "GITHUB_ENTERPRISE_TOKEN": "four", "GH_HOST": "evil.example"]
        let empty = result(#"{"hosts":{}}"#)
        #expect(GitHubAuthService.parse(empty, hostname: " GITHUB.COM ", environment: env).environmentCredential == .ghToken)
        #expect(GitHubAuthService.parse(empty, hostname: "team.ghe.com", environment: env).environmentCredential == .ghToken)
        #expect(GitHubAuthService.parse(empty, hostname: "github.localhost", environment: env).environmentCredential == .ghToken)
        #expect(GitHubAuthService.parse(empty, hostname: "enterprise.example", environment: env).environmentCredential == .ghEnterpriseToken)
        #expect(GitHubAuthService.parse(empty, environment: ["GH_TOKEN": "", "GITHUB_TOKEN": "x"]).environmentCredential == .githubToken)
    }

    @Test func versionArgumentsAndNoDowngrade() async {
        let recorder = AuthRecorder()
        let runner: GitHubAuthService.Runner = { url, args, env, timeout in
            await recorder.record(url, args, env, timeout)
            return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "unknown flag: --no-refresh", terminationStatus: 1, timedOut: false)
        }
        let url = URL(fileURLWithPath: "/fake/gh")
        let modern = ProvisioningGitHubCLIContext(executableURL: url, version: "2.103.0")
        let status = await GitHubAuthService.status(using: modern, hostname: " GITHUB.COM ", environment: ["GH_TOKEN": "value", "GH_DEBUG": "api", "GH_HOST": "elsewhere"], run: runner)
        #expect(status.outcome == .unsupported(reason: .capability))
        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls[0].arguments == ["auth", "status", "--hostname", "github.com", "--json", "hosts", "--no-refresh"])
        #expect(calls[0].url == url)
        #expect(calls[0].environment["GH_TOKEN"] == "value")
        #expect(calls[0].environment["GH_DEBUG"] == "")
        #expect(calls[0].environment["GH_PROMPT_DISABLED"] == "1")
        #expect(calls[0].timeout == ProvisioningConfiguration.commandTimeout)
        let old = ProvisioningGitHubCLIContext(executableURL: url, version: "2.81.0")
        _ = await GitHubAuthService.status(using: old, environment: [:], run: runner)
        let oldCalls = await recorder.calls
        #expect(oldCalls.last?.arguments == ["auth", "status", "--hostname", "github.com", "--json", "hosts"])
        for version in ["2.80.9", "2.103.0-rc1", "3.0.0", "bad", "02.103.0", "2.0103.0", "2.103.00", "2.103.999999999999999999999999"] {
            let context = ProvisioningGitHubCLIContext(executableURL: url, version: version)
            #expect(await GitHubAuthService.status(using: context, environment: [:], run: runner).outcome == .unsupported(reason: .cliVersion))
        }
        #expect(await GitHubAuthService.status(using: modern, hostname: "github.com;touch /tmp/pwn", environment: [:], run: runner).outcome == .unsupported(reason: .invalidHost))
        #expect(await recorder.calls.count == 2)
    }
}

private actor AuthRecorder {
    struct Call: Sendable {
        let url: URL
        let arguments: [String]
        let environment: [String: String]
        let timeout: TimeInterval
    }
    private(set) var calls: [Call] = []
    func record(_ url: URL, _ arguments: [String], _ environment: [String: String], _ timeout: TimeInterval) {
        calls.append(Call(url: url, arguments: arguments, environment: environment, timeout: timeout))
    }
}
