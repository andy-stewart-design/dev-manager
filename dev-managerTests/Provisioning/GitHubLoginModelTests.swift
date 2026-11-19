import Foundation
import Combine
import Testing
@testable import dev_manager

@MainActor
@Suite("GitHub login model")
struct GitHubLoginModelTests {
    private func fullInspection() -> ProvisioningInspection {
        func ready(_ id: ProvisioningCheck.ID) -> ProvisioningCheck { .init(id: id, state: .ready("ready")) }
        let root = URL(fileURLWithPath: "/tmp/fnm")
        let bin = root.appendingPathComponent("node-versions/v22.14.0/installation/bin")
        let runtime = ProvisioningRuntimeContext(
            node: ProvisioningManagedNode.validated(reportedVersion: "v22.14.0", actualExecutablePath: bin.appendingPathComponent("node").path, selector: "v22.14.0", expectedExecutableURL: bin.appendingPathComponent("node"), root: root, executableAvailable: { _ in true }).node!,
            pnpm: .init(version: "10.15.0", executableURL: bin.appendingPathComponent("pnpm")),
            fnmExecutableURL: URL(fileURLWithPath: "/tmp/fnm-bin"), fnmSelector: "v22.14.0", chosenFNMDirectoryURL: root)
        return ProvisioningInspection(developerTools: ready(.developerTools), developerToolsExecutableURL: nil,
            homebrew: ready(.homebrew), fnm: ready(.fnm), fnmExecutableURL: runtime.fnmExecutableURL,
            chosenFNMDirectoryURL: root, node: ready(.node), pnpm: ready(.pnpm), runtimeContext: runtime,
            githubCLI: ready(.githubCLI), githubCLIContext: .init(executableURL: URL(fileURLWithPath: "/tmp/gh"), version: "2.101.0"))
    }


    @Test("existing and unverifiable credentials block login")
    func blockedPreflight() async {
        let outcomes: [GitHubAuthStatus.Outcome] = [.authenticated(login: "existing", source: .stored), .unavailable(reason: .network), .unavailable(reason: .tls), .unverified(reason: .unknownState)]
        for outcome in outcomes {
            let fixture = fullInspection()
            let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, _, _ in
                Issue.record("login must not launch")
                return .init(completion: .failed(.unavailable), warnedAboutPlaintextStorage: false)
            }, inspectGitHubAuth: { _, host in .init(host: host, outcome: outcome, environmentCredential: nil) }, inspect: { fixture }))
            await model.checkAgain()
            model.presentLogin()
            model.continueLogin()
            for _ in 0..<1000 where model.operationState != nil { await Task.yield() }
            if case .blocked = model.loginState {} else { Issue.record("expected blocked state") }
        }
    }

    @Test("exit zero without verified credentials is not success")
    func postflightRequired() async {
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, host, _ in
            #expect(host.value == "enterprise.example")
            return .init(completion: .exited(0), warnedAboutPlaintextStorage: true)
        }, inspectGitHubAuth: { _, host in .init(host: host, outcome: .notSignedIn, environmentCredential: nil) }, inspect: { fixture }))
        await model.checkAgain()
        model.presentLogin()
        model.loginHostInput = "enterprise.example"
        model.continueLogin()
        for _ in 0..<1000 where model.operationState != nil { await Task.yield() }
        if case .error = model.loginState {} else { Issue.record("expected verification error") }
        #expect(model.selectedAuthHost == "enterprise.example")
        model.dismissLogin()
        model.presentLogin()
        #expect(model.loginHostInput == "github.com")
    }
    @Test("safe login failures are preserved without confirming plaintext")
    func safeFailure() async {
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, _, _ in
            .init(completion: .failed(.invalidVerificationURL), warnedAboutPlaintextStorage: true)
        }, inspectGitHubAuth: { _, host in .init(host: host, outcome: .notSignedIn, environmentCredential: nil) }, inspect: { fixture }))
        await model.checkAgain()
        model.presentLogin()
        model.continueLogin()
        for _ in 0..<1000 where model.operationState != nil { await Task.yield() }
        #expect(model.loginState == .error(GitHubLoginFailure.invalidVerificationURL.localizedDescription))
        #expect(model.plaintextWarningHosts.isEmpty)
    }

    @Test("closing displayed code clears public state while process drains")
    func closeClearsCode() async {
        let fixture = fullInspection()
        let gate = LoginGate()
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, _, event in
            event(.deviceCode("ABCD-1234"))
            event(.verificationURL(URL(string: "https://github.com/login/device")!))
            return await gate.wait()
        }, inspectGitHubAuth: { _, host in .init(host: host, outcome: .notSignedIn, environmentCredential: nil) }, inspect: { fixture }))
        await model.checkAgain()
        model.presentLogin()
        model.continueLogin()
        await gate.waitUntilStarted()
        for _ in 0..<1000 {
            if case .waiting(code: .some, url: .some) = model.loginState { break }
            await Task.yield()
        }
        if case .waiting(code: .some, url: .some) = model.loginState {} else { Issue.record("expected displayed device code") }
        model.dismissLogin()
        #expect(model.loginState == .cancelled)
        #expect(model.operationState != nil)
        model.copyLoginDeviceCode()
        model.openLoginBrowser()
        await gate.resolve(.init(completion: .cancelled, warnedAboutPlaintextStorage: false))
        for _ in 0..<1000 where model.operationState != nil { await Task.yield() }
        #expect(model.operationState == nil)
        #expect(model.loginState == .cancelled)
    }

    private func authIdle(_ model: ProvisioningModel) async {
        for await checking in model.$isCheckingGitHubAuth.values where !checking { return }
    }

    private func operationIdle(_ model: ProvisioningModel) async {
        for await state in model.$operationState.values where state == nil { return }
    }

    private func loginState(_ model: ProvisioningModel, matching predicate: (ProvisioningModel.LoginState) -> Bool) async {
        for await state in model.$loginState.values where predicate(state) { return }
    }

    @Test("cancelled login owns postflight and confirms saved credentials")
    func cancelledPostflightOwnership() async {
        let fixture = fullInspection()
        let store = LoginTestStore()
        let process = AsyncGate<GitHubAuthOperationResult>()
        let post = AsyncGate<GitHubAuthStatus>()
        let spies = LoginSpies()
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, _, callback in
            await store.setCallback(callback)
            return await process.wait()
        }, openLoginURL: { spies.urls.append($0); spies.events.append("open") }, copyLoginCode: { spies.codes.append($0); spies.events.append("copy") }, inspectGitHubAuth: { _, host in
            let count = await store.incrementStatus()
            if count == 3 { return await post.wait() }
            return .init(host: host, outcome: .notSignedIn, environmentCredential: nil)
        }, inspect: { await store.incrementInspection(); return fixture }))
        await model.checkAgain()
        await authIdle(model)
        model.presentLogin(); model.continueLogin()
        await process.waitUntilStarted()
        model.dismissLogin()
        #expect(model.loginState == .cancelled && model.isBusy)
        let owned = model.operationState
        await model.checkAgain()
        model.presentLogin(); model.refreshGitHubAuthStatus()
        #expect(model.operationState == owned && !model.isShowingLogin)
        #expect(await store.statusCount == 2)
        #expect(await store.inspectionCount == 1)
        await process.resolve(.init(completion: .cancelled, warnedAboutPlaintextStorage: true))
        await post.waitUntilStarted()
        #expect(model.operationState == owned && model.isBusy)
        #expect(model.gitHubAuthStatus?.outcome == .notSignedIn)
        await post.resolve(.init(host: "github.com", outcome: .authenticated(login: "saved", source: .stored), environmentCredential: nil))
        await operationIdle(model)
        #expect(model.gitHubAuthStatus?.outcome == .authenticated(login: "saved", source: .stored))
        #expect(model.plaintextWarningHosts.contains("github.com"))
        await store.emit(.deviceCode("TEST-1234"))
        await store.emit(.verificationURL(URL(string: "https://github.com/login/device")!))
        model.copyLoginDeviceCode(); model.openLoginBrowser()
        #expect(!model.isShowingLogin && model.loginState == .cancelled)
        #expect(spies.urls.isEmpty && spies.codes.isEmpty)
    }

    @Test("browser and copy follow device flow lifecycle")
    func browserCopyLifecycle() async {
        let fixture = fullInspection()
        let store = LoginTestStore()
        let gate = AsyncGate<GitHubAuthOperationResult>()
        let spies = LoginSpies()
        let url = URL(string: "https://github.com/login/device")!
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, _, callback in
            await store.setCallback(callback); return await gate.wait()
        }, openLoginURL: { spies.urls.append($0); spies.events.append("open") }, copyLoginCode: { spies.codes.append($0); spies.events.append("copy") }, inspectGitHubAuth: { _, host in
            let count = await store.incrementStatus()
            return .init(host: host, outcome: count >= 3 ? .authenticated(login: "saved", source: .stored) : .notSignedIn, environmentCredential: nil)
        }, inspect: { fixture }))
        await model.checkAgain(); await authIdle(model)
        model.presentLogin(); model.continueLogin(); await gate.waitUntilStarted()
        await store.emit(.deviceCode("TEST-1234"))
        await loginState(model) { $0 == .waiting(code: "TEST-1234", url: nil) }
        #expect(spies.urls.isEmpty && spies.codes.isEmpty)
        await store.emit(.verificationURL(url))
        await loginState(model) { $0 == .waiting(code: "TEST-1234", url: url) }
        #expect(spies.urls == [url] && spies.codes.isEmpty)
        #expect(spies.events == ["open"])
        #expect(!model.loginCodeCopied)
        await store.emit(.clipboardCopied)
        for _ in 0..<100 where !model.loginCodeCopied { await Task.yield() }
        #expect(model.loginCodeCopied)
        await store.emit(.verificationURL(url)); await store.emit(.deviceCode("TEST-1234"))
        model.openLoginBrowser(); model.copyLoginDeviceCode()
        model.dismissLogin()
        model.openLoginBrowser(); model.copyLoginDeviceCode()
        await store.emit(.deviceCode("OLD-0000")); await store.emit(.verificationURL(url)); await store.emit(.clipboardCopied)
        await gate.resolve(.init(completion: .cancelled, warnedAboutPlaintextStorage: false))
        await operationIdle(model)
        #expect(model.loginState == .cancelled && !model.isShowingLogin && !model.loginCodeCopied)
        #expect(spies.urls == [url, url] && spies.codes == ["TEST-1234"])
    }

    @Test("confirmed plaintext warnings survive blocked retry and other hosts")
    func plaintextWarningsPerHost() async {
        let fixture = fullInspection()
        let store = LoginTestStore()
        let model = ProvisioningModel(dependencies: .init(runGitHubLogin: { _, host, _ in
            await store.login(host.value)
            return .init(completion: .exited(0), warnedAboutPlaintextStorage: true)
        }, inspectGitHubAuth: { _, host in
            let authenticated = await store.hasCredential(host)
            if host == "unknown.example" { return .init(host: host, outcome: .unverified(reason: .unknownState), environmentCredential: nil) }
            return .init(host: host, outcome: authenticated ? .authenticated(login: "synthetic", source: .stored) : .notSignedIn, environmentCredential: nil)
        }, inspect: { fixture }))
        await model.checkAgain(); await authIdle(model)
        model.presentLogin(); model.continueLogin(); await operationIdle(model)
        if case .success = model.loginState {} else { Issue.record("expected success") }
        #expect(model.plaintextWarningHosts == ["github.com"])
        model.dismissLogin(); model.presentLogin(); model.continueLogin(); await operationIdle(model)
        if case .blocked = model.loginState {} else { Issue.record("expected blocked retry") }
        #expect(await store.loginCount == 1)
        #expect(model.plaintextWarningHosts == ["github.com"])
        model.chooseLoginHost(); model.loginHostInput = "enterprise.example"
        model.continueLogin(); await operationIdle(model)
        #expect(await store.loginCount == 2)
        #expect(model.plaintextWarningHosts == ["github.com", "enterprise.example"])
        model.chooseLoginHost(); model.loginHostInput = "unknown.example"
        model.continueLogin(); await operationIdle(model)
        if case .blocked = model.loginState {} else { Issue.record("expected unknown status to block") }
        #expect(await store.loginCount == 2)
        #expect(model.plaintextWarningHosts == ["github.com", "enterprise.example"])
    }

}

private actor LoginGate {
    private var continuation: CheckedContinuation<GitHubAuthOperationResult, Never>?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    func wait() async -> GitHubAuthOperationResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resolve(_ result: GitHubAuthOperationResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}


private actor AsyncGate<Value: Sendable> {
    private var value: Value?
    private var waiter: CheckedContinuation<Value, Never>?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Value {
        started = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
        if let value { return value }
        return await withCheckedContinuation { waiter = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func resolve(_ value: Value) {
        self.value = value
        waiter?.resume(returning: value)
        waiter = nil
    }
}

private actor LoginTestStore {
    private(set) var statusCount = 0
    private(set) var inspectionCount = 0
    private(set) var loginCount = 0
    private var credentials: Set<String> = []
    private var callback: (@Sendable (GitHubDeviceFlowEvent) -> Void)?
    func incrementStatus() -> Int { statusCount += 1; return statusCount }
    func incrementInspection() { inspectionCount += 1 }
    func setCallback(_ callback: @escaping @Sendable (GitHubDeviceFlowEvent) -> Void) { self.callback = callback }
    func emit(_ event: GitHubDeviceFlowEvent) { callback?(event) }
    func login(_ host: String) { loginCount += 1; credentials.insert(host) }
    func hasCredential(_ host: String) -> Bool { credentials.contains(host) }
}

@MainActor private final class LoginSpies {
    var events: [String] = []
    var urls: [URL] = []
    var codes: [String] = []
}
