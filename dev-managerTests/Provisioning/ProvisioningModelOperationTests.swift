#if DEBUG
import Foundation
import Testing
@testable import dev_manager

@MainActor
@Suite("Provisioning model operation state")
struct ProvisioningModelOperationTests {
    @Test("full and targeted inspections have distinct derived operation state")
    func inspectionTransitions() async {
        let fullGate = AsyncGate<ProvisioningInspection>()
        let targetGate = AsyncGate<ProvisioningTargetedInspection>()
        let target = ProvisioningCheck.ID.homebrew
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullGate.wait() },
            inspectTarget: { _ in await targetGate.wait() }
        )
        let model = ProvisioningModel(dependencies: dependencies)

        let fullTask = Task { await model.checkAgain() }
        await Task.yield()
        guard case let .inspection(_, activeTarget) = model.operationState else {
            Issue.record("full inspection was not active")
            return
        }
        #expect(activeTarget == nil)
        #expect(model.isChecking)
        await fullGate.resolve(inspection())
        await fullTask.value
        #expect(model.operationState == nil)

        let targetTask = Task { await model.checkTool(target) }
        await Task.yield()
        guard case let .inspection(_, activeTarget) = model.operationState else {
            Issue.record("targeted inspection was not active")
            return
        }
        #expect(activeTarget == target)
        #expect(model.activeInspectionTargetID == target)
        await targetGate.resolve(targetedInspection(target))
        await targetTask.value
        #expect(model.operationState == nil)
    }

    @Test("runtime installation nests preflight and post-install inspection")
    func nestedRuntimeInstallation() async {
        let fullGate = AsyncGate<ProvisioningInspection>()
        let preflightGate = AsyncGate<ProvisioningTargetedInspection>()
        let installGate = AsyncGate<ProvisioningProcessResult>()
        let recorder = InstallationRecorderBox()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullGate.wait() },
            inspectTarget: { _ in
                // The first and second runtime inspections are deliberately
                // controlled in order by the test's separate gates below.
                await preflightGate.wait()
            },
            installFNM: { await installGate.wait() },
            recordInstallation: recorder.record
        )
        let model = ProvisioningModel(dependencies: dependencies)
        let fullTask = Task { await model.checkAgain() }
        await Task.yield()
        await fullGate.resolve(inspection(fnmState: .missing("fnm missing"), nodeState: .missing("Node missing"), pnpmState: .unverified("Node required")))
        await fullTask.value

        let installTask = Task { await model.installRuntimeTool(.fnm) }
        await Task.yield()
        guard case let .tool(_, target, phase) = model.operationState else {
            Issue.record("runtime operation was not active")
            return
        }
        #expect(target == .fnm)
        guard case .preflight = phase else {
            Issue.record("runtime operation did not enter preflight")
            return
        }
        await preflightGate.resolve(targetedInspection(.fnm, fnmState: .missing("fnm still missing"), fnmURL: URL(fileURLWithPath: "/tmp/fnm")))
        await Task.yield()
        guard case let .tool(_, _, installPhase) = model.operationState else {
            Issue.record("runtime operation ended before installation")
            return
        }
        #expect(installPhase == .installing)
        await installGate.resolve(successfulProcess())
        // The simple dependency above supplies the preflight result each time;
        // replace the model's postflight gate by completing the same controlled
        // stream only after installation has begun.
        await preflightGate.resolve(targetedInspection(.fnm, fnmState: .ready("fnm ready"), fnmURL: URL(fileURLWithPath: "/tmp/fnm")))
        await installTask.value
        #expect(model.operationState == nil)
        #expect(await recorder.value == 1)
        #expect(model.installationLogURL == recorder.url)
    }

    @Test("cancelled full inspection can be replaced without stale publication")
    func cancelledFullInspectionCanBeReplaced() async {
        let staleGate = AsyncGate<ProvisioningInspection>()
        let currentGate = AsyncGate<ProvisioningInspection>()
        let calls = CallCounter()
        let dependencies = ProvisioningModelDependencies(
            inspect: {
                switch await calls.next() {
                case 0: return await staleGate.wait()
                default: return await currentGate.wait()
                }
            }
        )
        let model = ProvisioningModel(dependencies: dependencies)

        let staleTask = Task { await model.checkAgain() }
        await Task.yield()
        staleTask.cancel()
        await yieldUntilIdle(model)
        #expect(model.operationState == nil)

        let currentTask = Task { await model.checkAgain() }
        await Task.yield()
        await staleGate.resolve(inspection(developerToolsState: .ready("stale developer tools")))
        await staleTask.value
        #expect(model.checks.allSatisfy { $0.state == .checking })
        #expect(model.runtimeContext == nil)
        #expect(model.messagePresentation == .progress("Inspecting installed tools…"))

        await currentGate.resolve(inspection())
        await currentTask.value
        #expect(model.checks.first(where: { $0.id == .developerTools })?.state == .ready("developer tools"))
    }

    @Test("cancelled targeted inspection cannot publish over a newer full inspection")
    func cancelledTargetedInspectionIsStale() async {
        let staleGate = AsyncGate<ProvisioningTargetedInspection>()
        let currentGate = AsyncGate<ProvisioningInspection>()
        let fullCalls = CallCounter()
        let dependencies = ProvisioningModelDependencies(
            inspect: {
                switch await fullCalls.next() {
                case 0: return inspection()
                default: return await currentGate.wait()
                }
            },
            inspectTarget: { _ in await staleGate.wait() }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()

        let staleTask = Task { await model.checkTool(.fnm) }
        await Task.yield()
        staleTask.cancel()
        await yieldUntilIdle(model)
        #expect(model.operationState == nil)

        let currentTask = Task { await model.checkAgain() }
        await Task.yield()
        await staleGate.resolve(targetedInspection(.fnm, fnmState: .ready("stale fnm"), fnmURL: URL(fileURLWithPath: "/tmp/stale-fnm")))
        await staleTask.value
        #expect(model.checks.first(where: { $0.id == .fnm })?.state == .ready("fnm"))
        #expect(model.runtimeContext == nil)
        #expect(model.messagePresentation == .progress("Inspecting installed tools…"))

        await currentGate.resolve(inspection())
        await currentTask.value
    }

    @Test("cancelled installation keeps ownership until the installer returns")
    func cancelledInstallationKeepsBusyUntilDrain() async {
        let fullGate = AsyncGate<ProvisioningInspection>()
        let preflightGate = AsyncGate<ProvisioningTargetedInspection>()
        let installGate = AsyncGate<ProvisioningProcessResult>()
        let installCalls = CallCounter()
        let recorder = InstallationRecorderBox()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullGate.wait() },
            inspectTarget: { _ in await preflightGate.wait() },
            installFNM: {
                _ = await installCalls.next()
                return await installGate.wait()
            },
            recordInstallation: recorder.record
        )
        let model = ProvisioningModel(dependencies: dependencies)
        let fullTask = Task { await model.checkAgain() }
        await Task.yield()
        await fullGate.resolve(inspection(fnmState: .missing("fnm missing"), nodeState: .missing("Node missing"), pnpmState: .unverified("Node required")))
        await fullTask.value

        let cancelled = Task { await model.installRuntimeTool(.fnm) }
        await Task.yield()
        await preflightGate.resolve(targetedInspection(.fnm, fnmState: .missing("fnm still missing")))
        await Task.yield()
        #expect(model.isInstallingRuntime)
        cancelled.cancel()
        await Task.yield()
        #expect(model.isBusy)
        #expect(model.isInstallingRuntime)
        #expect(await installCalls.value == 1)

        // A second install is refused while the real installer is still suspended.
        await model.installRuntimeTool(.fnm)
        #expect(await installCalls.value == 1)
        #expect(model.isBusy)

        await installGate.resolve(successfulProcess())
        await cancelled.value
        #expect(model.operationState == nil)
        #expect(!model.isBusy)
        #expect(await recorder.value == 0)
        #expect(model.installationFailureLogURL == nil)
    }

    @Test("consent contributes to busy state and releasing it permits work")
    func consentBusyRelease() async {
        let gate = AsyncGate<ProvisioningInspection>()
        let model = ProvisioningModel(dependencies: ProvisioningModelDependencies(inspect: { await gate.wait() }))
        model.isShowingToolConsent = true
        #expect(model.isBusy)
        model.isShowingToolConsent = false
        let task = Task { await model.checkAgain() }
        await Task.yield()
        #expect(model.isChecking)
        await gate.resolve(inspection())
        await task.value
        #expect(!model.isBusy)
    }

    @Test("handoff completion leaves the check-needed flag distinct")
    func handoffWaitingFlag() async {
        let fullGate = AsyncGate<ProvisioningInspection>()
        let targetGate = AsyncGate<ProvisioningTargetedInspection>()
        let callbackBox = CallbackBox()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullGate.wait() },
            inspectTarget: { _ in await targetGate.wait() },
            requestCommandLineTools: { completion in
                Task { await callbackBox.set(completion) }
            }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        let fullTask = Task { await model.checkAgain() }
        await Task.yield()
        await fullGate.resolve(inspection(developerToolsState: .missing("developer tools missing")))
        await fullTask.value

        let requestTask = Task { await model.requestCommandLineTools() }
        await Task.yield()
        await targetGate.resolve(targetedInspection(.developerTools, developerToolsState: .missing("still missing")))
        await requestTask.value
        #expect(model.commandLineToolsRequestNeedsCheck)
        #expect(model.isBusy)
        await callbackBox.call(index: 0, status: 0)
        await Task.yield()
        #expect(!model.isBusy)
        #expect(model.commandLineToolsRequestNeedsCheck)

        let newerInspection = Task { await model.checkAgain() }
        await Task.yield()
        let currentMessage = model.messagePresentation
        let currentChecks = model.checks
        await callbackBox.call(index: 0, status: 1)
        await Task.yield()
        #expect(model.activeInspectionID != nil)
        #expect(model.messagePresentation == currentMessage)
        #expect(model.checks == currentChecks)
        #expect(model.installationFailureLogURL == nil)
        await fullGate.resolve(inspection())
        await newerInspection.value
    }

    @Test("cancelled inspection completion cannot publish over a newer inspection")
    func cancelledInspectionIsStale() async {
        let gate = AsyncGate<ProvisioningInspection>()
        let model = ProvisioningModel(dependencies: ProvisioningModelDependencies(inspect: { await gate.wait() }))
        let cancelled = Task { await model.checkAgain() }
        await Task.yield()
        cancelled.cancel()
        await gate.resolve(inspection(developerToolsState: .missing("stale")))
        await cancelled.value
        #expect(model.operationState == nil)
        #expect(model.checks.allSatisfy { $0.state == .checking })

        let current = Task { await model.checkAgain() }
        await Task.yield()
        await gate.resolve(inspection())
        await current.value
        #expect(model.hasCompletedCheck)
        #expect(model.checks.first(where: { $0.id == .developerTools })?.state == .ready("developer tools"))
    }

    @Test("failed runtime installation always returns to idle")
    func failedInstallationFinishes() async {
        let fullGate = AsyncGate<ProvisioningInspection>()
        let targetGate = AsyncGate<ProvisioningTargetedInspection>()
        let installGate = AsyncGate<ProvisioningProcessResult>()
        let recorder = InstallationRecorderBox()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullGate.wait() },
            inspectTarget: { _ in await targetGate.wait() },
            installFNM: { await installGate.wait() },
            recordInstallation: recorder.record
        )
        let model = ProvisioningModel(dependencies: dependencies)
        let fullTask = Task { await model.checkAgain() }
        await Task.yield()
        await fullGate.resolve(inspection(fnmState: .missing("fnm missing"), nodeState: .missing("Node missing"), pnpmState: .unverified("Node required")))
        await fullTask.value
        let installTask = Task { await model.installRuntimeTool(.fnm) }
        await Task.yield()
        await targetGate.resolve(targetedInspection(.fnm, fnmState: .missing("still missing")))
        await Task.yield()
        await installGate.resolve(failedProcess())
        await targetGate.resolve(targetedInspection(.fnm, fnmState: .missing("still missing")))
        await installTask.value
        #expect(model.operationState == nil)
        #expect(model.messagePresentation?.isError == true)
        #expect(await recorder.value == 1)
        #expect(model.installationFailureLogURL == recorder.url)
    }
}

private actor CallCounter {
    private var count = 0

    func next() -> Int {
        defer { count += 1 }
        return count
    }

    var value: Int { count }
}

private final class InstallationRecorderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var countStorage = 0
    let url = URL(fileURLWithPath: "/tmp/dev-manager-provisioning-test.log")

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return countStorage
    }

    func record(_ label: String, _ result: ProvisioningProcessResult) -> ProvisioningInstallationLog.AppendResult {
        lock.lock()
        countStorage += 1
        lock.unlock()
        return .wrote(url)
    }
}

@MainActor
private func yieldUntilIdle(_ model: ProvisioningModel) async {
    for _ in 0..<16 {
        guard model.operationState != nil else { return }
        await Task.yield()
    }
}

private actor CallbackBox {
    private var callbacks: [(@Sendable (Int32) -> Void)] = []

    func set(_ callback: @escaping @Sendable (Int32) -> Void) {
        callbacks.append(callback)
    }

    func call(index: Int, status: Int32) {
        guard callbacks.indices.contains(index) else { return }
        callbacks[index](status)
    }
}

private actor AsyncSignal {
    private var signaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        signaled = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor AsyncGate<Value: Sendable> {
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var pending: [Value] = []

    func wait() async -> Value {
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resolve(_ value: Value) {
        if !continuations.isEmpty {
            continuations.removeFirst().resume(returning: value)
        } else {
            pending.append(value)
        }
    }
}

private func inspection(
    developerToolsState: ProvisioningCheck.State = .ready("developer tools"),
    fnmState: ProvisioningCheck.State = .ready("fnm"),
    nodeState: ProvisioningCheck.State = .ready("Node"),
    pnpmState: ProvisioningCheck.State = .ready("pnpm")
) -> ProvisioningInspection {
    ProvisioningInspection(
        developerTools: ProvisioningCheck(id: .developerTools, state: developerToolsState),
        developerToolsExecutableURL: nil,
        homebrew: ProvisioningCheck(id: .homebrew, state: .ready("Homebrew")),
        fnm: ProvisioningCheck(id: .fnm, state: fnmState),
        fnmExecutableURL: fnmState.isReady ? URL(fileURLWithPath: "/tmp/fnm") : nil,
        chosenFNMDirectoryURL: nil,
        node: ProvisioningCheck(id: .node, state: nodeState),
        pnpm: ProvisioningCheck(id: .pnpm, state: pnpmState),
        runtimeContext: nil
    )
}

private func targetedInspection(
    _ target: ProvisioningCheck.ID,
    developerToolsState: ProvisioningCheck.State = .ready("developer tools"),
    fnmState: ProvisioningCheck.State = .ready("fnm"),
    fnmURL: URL? = URL(fileURLWithPath: "/tmp/fnm")
) -> ProvisioningTargetedInspection {
    let state: ProvisioningCheck.State
    switch target {
    case .developerTools: state = developerToolsState
    case .fnm: state = fnmState
    default: state = .ready(target.title)
    }
    return ProvisioningTargetedInspection(
        checks: [ProvisioningCheck(id: target, state: state)],
        fnmExecutableURL: fnmURL,
        runtimeContext: nil
    )
}

private func successfulProcess() -> ProvisioningProcessResult {
    ProvisioningProcessResult(succeeded: true, stdout: "", stderr: "", terminationStatus: 0, timedOut: false)
}

private func failedProcess() -> ProvisioningProcessResult {
    ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "failed", terminationStatus: 1, timedOut: false)
}
#endif
