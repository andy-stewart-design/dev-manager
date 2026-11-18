import Foundation
import Testing
@testable import dev_manager

private actor AuthGate {
    private var continuation: CheckedContinuation<GitHubAuthStatus, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    func wait() async -> GitHubAuthStatus {
        calls += 1
        started?.resume()
        started = nil
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func resolve(_ status: GitHubAuthStatus) { continuation?.resume(returning: status); continuation = nil }
}

@MainActor
@Suite("GitHub authentication model")
struct GitHubAuthModelTests {
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
            githubCLI: ready(.githubCLI), githubCLIContext: .init(executableURL: URL(fileURLWithPath: "/tmp/gh"), version: "2.80.0"))
    }

    @Test("local inspection finishes independently of a suspended account check")
    func localInspectionIsIndependent() async {
        let gate = AuthGate()
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { _, _ in await gate.wait() }, inspect: { fixture }, inspectTarget: { id in
            ProvisioningTargetedInspection(checks: [ProvisioningCheck(id: id, state: .ready("ready"))], fnmExecutableURL: fixture.fnmExecutableURL, chosenFNMDirectoryURL: fixture.chosenFNMDirectoryURL, runtimeContext: fixture.runtimeContext)
        }))
        await model.checkAgain()
        await gate.waitUntilStarted()
        #expect(model.hasCompletedCheck && model.hasLoadedInitialInspection)
        #expect(!model.isBusy && model.operationState == nil)
        #expect(model.allRuntimeToolsReady)
        await model.checkTool(.node)
        #expect(await gate.calls == 1)
        #expect(model.allRuntimeToolsReady)
        await gate.resolve(.init(host: "github.com", outcome: .unavailable(reason: .network), environmentCredential: nil))
    }

    @Test("losing the verified CLI clears a pending account check")
    func missingContextClearsStatus() async {
        let gate = AuthGate()
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { _, _ in await gate.wait() }, inspect: { fixture }, inspectTarget: { _ in
            ProvisioningTargetedInspection(checks: [.init(id: .githubCLI, state: .missing("missing"))], fnmExecutableURL: nil, runtimeContext: nil)
        }))
        await model.checkAgain()
        await gate.waitUntilStarted()
        await model.checkTool(.githubCLI)
        #expect(model.gitHubAuthStatus == nil)
        #expect(!model.isCheckingGitHubAuth)
        await gate.resolve(.init(host: "github.com", outcome: .notSignedIn, environmentCredential: nil))
        for _ in 0..<20 { await Task.yield() }
        #expect(model.gitHubAuthStatus == nil && !model.isCheckingGitHubAuth)
    }
    @Test("superseded account checks cannot publish late results")
    func supersededCheck() async {
        let first = AuthGate()
        let second = AuthGate()
        let counter = AuthSequence(first: first, second: second)
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { _, _ in await counter.wait() }, inspect: { fixture }))
        await model.checkAgain()
        await first.waitUntilStarted()
        model.refreshGitHubAuthStatus()
        await second.waitUntilStarted()
        let expected = GitHubAuthStatus(host: "github.com", outcome: .notSignedIn, environmentCredential: nil)
        await second.resolve(expected)
        for _ in 0..<100 where model.isCheckingGitHubAuth { await Task.yield() }
        #expect(model.gitHubAuthStatus == expected)
        await first.resolve(.init(host: "github.com", outcome: .authenticated(login: "old", source: .stored), environmentCredential: nil))
        for _ in 0..<20 { await Task.yield() }
        #expect(model.gitHubAuthStatus == expected)
        #expect(model.allRuntimeToolsReady && !model.isBusy)
    }

    @Test("changed binary context rejects a late old result")
    func changedBinaryContext() async {
        let first = AuthGate(), second = AuthGate()
        let fixture = fullInspection()
        let contextB = ProvisioningGitHubCLIContext(executableURL: URL(fileURLWithPath: "/tmp/gh-b"), version: "2.103.0")
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { context, _ in
            await (context == contextB ? second : first).wait()
        }, inspect: { fixture }, inspectTarget: { _ in
            ProvisioningTargetedInspection(checks: [.init(id: .githubCLI, state: .ready("ready"))], fnmExecutableURL: nil, runtimeContext: nil, githubCLI: .init(id: .githubCLI, state: .ready("ready")), githubCLIContext: contextB)
        }))
        await model.checkAgain()
        await first.waitUntilStarted()
        await model.checkTool(.githubCLI)
        await second.waitUntilStarted()
        let expected = GitHubAuthStatus(host: "github.com", outcome: .authenticated(login: "new", source: .stored), environmentCredential: nil)
        await second.resolve(expected)
        for _ in 0..<100 where model.isCheckingGitHubAuth { await Task.yield() }
        #expect(model.gitHubAuthStatus == expected && model.githubCLIContext == contextB)
        await first.resolve(.init(host: "github.com", outcome: .notSignedIn, environmentCredential: nil))
        for _ in 0..<20 { await Task.yield() }
        #expect(model.gitHubAuthStatus == expected && model.githubCLIContext == contextB)
    }

    @Test("read-only refresh never invokes installation or logging", arguments: [
        GitHubAuthStatus.Outcome.notSignedIn, .unavailable(reason: .network), .authenticated(login: "user", source: .stored)
    ])
    func refreshDoesNotInstall(outcome: GitHubAuthStatus.Outcome) async {
        let gate = AuthGate()
        let calls = InstallationCalls()
        let fixture = fullInspection()
        let result = ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "", terminationStatus: 1, timedOut: false)
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { _, _ in await gate.wait() }, inspect: { fixture },
            requestCommandLineTools: { _ in calls.increment() },
            downloadHomebrew: { _ in calls.increment(); return URL(fileURLWithPath: "/tmp/unused") },
            openHomebrewPackage: { _ in calls.increment(); return false },
            installFNM: { calls.increment(); return result },
            installNode: { _, _ in calls.increment(); return result },
            installPnpm: { _ in calls.increment(); return result },
            installGitHubCLI: { calls.increment(); return result },
            recordInstallation: { _, _ in calls.increment(); return .failed("unexpected") }))
        await model.checkAgain()
        await gate.waitUntilStarted()
        await gate.resolve(.init(host: "github.com", outcome: outcome, environmentCredential: nil))
        for _ in 0..<100 where model.isCheckingGitHubAuth { await Task.yield() }
        #expect(model.gitHubAuthStatus?.outcome == outcome)
        #expect(calls.count == 0)
    }

    @Test("non-success account outcomes leave runtime readiness unchanged", arguments: [
        GitHubAuthStatus.Outcome.notSignedIn, .invalidCredentials, .unavailable(reason: .network),
        .unsupported(reason: .cliVersion), .unverified(reason: .unknownState)
    ])
    func outcomesAreIndependent(outcome: GitHubAuthStatus.Outcome) async {
        let gate = AuthGate()
        let fixture = fullInspection()
        let model = ProvisioningModel(dependencies: .init(inspectGitHubAuth: { _, _ in await gate.wait() }, inspect: { fixture }))
        await model.checkAgain()
        await gate.waitUntilStarted()
        let node = model.checks.first(where: { $0.id == .node })?.state
        #expect(model.allRuntimeToolsReady && !model.isBusy)
        await gate.resolve(.init(host: "github.com", outcome: outcome, environmentCredential: nil))
        for _ in 0..<100 where model.isCheckingGitHubAuth { await Task.yield() }
        #expect(model.gitHubAuthStatus?.outcome == outcome)
        #expect(model.checks.first(where: { $0.id == .node })?.state == node && model.allRuntimeToolsReady && !model.isBusy)
    }

}

private actor AuthSequence {
    let first: AuthGate
    let second: AuthGate
    var calls = 0
    init(first: AuthGate, second: AuthGate) { self.first = first; self.second = second }
    func wait() async -> GitHubAuthStatus {
        calls += 1
        return await (calls == 1 ? first : second).wait()
    }
}

private final class InstallationCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
