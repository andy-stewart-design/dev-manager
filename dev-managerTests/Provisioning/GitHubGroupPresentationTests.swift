import Testing
@testable import dev_manager

@MainActor
@Suite("GitHub group presentation")
struct GitHubGroupPresentationTests {
    private func status(_ outcome: GitHubAuthStatus.Outcome, host: String = "github.com") -> GitHubAuthStatus {
        .init(host: host, outcome: outcome, environmentCredential: nil)
    }

    @Test func aggregateStates() {
        let ready = ProvisioningCheck.State.ready("ready")
        let signedIn = status(.authenticated(login: "example", source: .stored))
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: signedIn) == .ready)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.notSignedIn)) == .setup)
        #expect(GitHubGroupPresentation.derive(cli: .missing("missing"), hasContext: true, auth: signedIn) == .setup)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: false, auth: signedIn) == .setup)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.authenticated(login: "x", source: .stored), host: "other")) == .setup)
        #expect(GitHubGroupPresentation.derive(cli: .checking, hasContext: true, auth: signedIn) == .checking)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.checking)) == .checking)
        #expect(GitHubGroupPresentation.derive(cli: .attention("broken"), hasContext: false, auth: nil) == .attention)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.invalidCredentials)) == .attention)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.unavailable(reason: .network))) == .attention)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.unsupported(reason: .capability))) == .attention)
        #expect(GitHubGroupPresentation.derive(cli: ready, hasContext: true, auth: status(.unverified(reason: .unknownState))) == .unverified)
    }
}
