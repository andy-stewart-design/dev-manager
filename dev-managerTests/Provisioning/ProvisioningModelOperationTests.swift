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

    @Test("cancelled full inspection retains ownership until drain")
    func cancelledFullInspectionRetainsOwnershipUntilDrain() async {
        let inspectionProbe = InspectionProbe<ProvisioningInspection>()
        await inspectionProbe.resolve(inspection(fnmState: .missing("initial fnm missing")))
        let targetProbe = InspectionProbe<ProvisioningTargetedInspection>()
        let calls = CallCounter()
        let installCalls = CallCounter()
        let dependencies = ProvisioningModelDependencies(
            inspect: {
                switch await calls.next() {
                case 0: return await inspectionProbe.wait()
                default: return await inspectionProbe.wait()
                }
            },
            inspectTarget: { _ in await targetProbe.wait() },
            installFNM: {
                _ = await installCalls.next()
                return successfulProcess()
            }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()
        let checksBeforeCancellation = model.checks
        let contextBeforeCancellation = model.runtimeContext
        let failureLogBeforeCancellation = model.installationFailureLogURL

        let cancelled = Task { await model.checkAgain() }
        await inspectionProbe.waitUntilStarted(2)
        let ownership = model.operationState
        cancelled.cancel()
        #expect(model.operationState == ownership)
        #expect(model.isBusy)

        // The old probe owns the model: neither a new check nor an eligible
        // install may reach its dependency while that probe is suspended.
        await model.checkAgain()
        await model.installRuntimeTool(.fnm)
        #expect(await inspectionProbe.calls == 2)
        #expect(await targetProbe.calls == 0)
        #expect(await installCalls.value == 0)

        await inspectionProbe.resolve(inspection(fnmState: .ready("stale returned fnm")))
        await cancelled.value
        #expect(model.operationState == nil)
        #expect(model.checks == checksBeforeCancellation)
        #expect(model.runtimeContext == contextBeforeCancellation)
        #expect(model.messagePresentation == .progress("Inspecting installed tools…"))
        #expect(model.installationFailureLogURL == failureLogBeforeCancellation)

        let current = Task { await model.checkAgain() }
        await inspectionProbe.waitUntilStarted(3)
        await inspectionProbe.resolve(inspection(fnmState: .ready("current fnm")))
        await current.value
        #expect(model.checks.first(where: { $0.id == .fnm })?.state == .ready("current fnm"))
    }

    @Test("cancelled targeted inspection retains ownership until drain")
    func cancelledTargetedInspectionRetainsOwnershipUntilDrain() async {
        let fullProbe = InspectionProbe<ProvisioningInspection>()
        await fullProbe.resolve(inspection(fnmState: .missing("fnm missing")))
        let targetProbe = InspectionProbe<ProvisioningTargetedInspection>()
        let target = ProvisioningCheck.ID.fnm
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullProbe.wait() },
            inspectTarget: { _ in await targetProbe.wait() }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()
        let checksBeforeCancellation = model.checks

        let cancelled = Task { await model.checkTool(target) }
        await targetProbe.waitUntilStarted()
        let ownership = model.operationState
        cancelled.cancel()
        #expect(model.operationState == ownership)
        #expect(model.isBusy)

        await model.checkAgain()
        await model.checkTool(target)
        await model.installRuntimeTool(target)
        #expect(await targetProbe.calls == 1)

        await targetProbe.resolve(targetedInspection(target, fnmState: .ready("stale returned fnm"), fnmURL: URL(fileURLWithPath: "/tmp/stale-fnm")))
        await cancelled.value
        #expect(model.operationState == nil)
        #expect(model.checks == checksBeforeCancellation)
        #expect(model.messagePresentation == .progress("Checking Fast Node Manager (fnm)…"))

        let current = Task { await model.checkTool(target) }
        await targetProbe.waitUntilStarted(2)
        await targetProbe.resolve(targetedInspection(target, fnmState: .ready("current fnm"), fnmURL: URL(fileURLWithPath: "/tmp/current-fnm")))
        await current.value
        #expect(model.checks.first(where: { $0.id == target })?.state == .ready("current fnm"))
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

    @Test("cancelled preflight retains parent tool ownership and never installs")
    func cancelledPreflightRetainsParentOwnership() async {
        let fullProbe = InspectionProbe<ProvisioningInspection>()
        await fullProbe.resolve(inspection(fnmState: .missing("fnm missing"), nodeState: .missing("Node missing"), pnpmState: .unverified("Node required")))
        let preflightProbe = InspectionProbe<ProvisioningTargetedInspection>()
        let installCalls = CallCounter()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullProbe.wait() },
            inspectTarget: { _ in await preflightProbe.wait() },
            installFNM: {
                _ = await installCalls.next()
                return successfulProcess()
            }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()

        let cancelled = Task { await model.installRuntimeTool(.fnm) }
        await preflightProbe.waitUntilStarted()
        let ownership = model.operationState
        cancelled.cancel()
        #expect(model.operationState == ownership)
        #expect(model.isBusy)
        await model.installRuntimeTool(.fnm)
        #expect(await installCalls.value == 0)

        await preflightProbe.resolve(targetedInspection(.fnm, fnmState: .missing("stale preflight")))
        await cancelled.value
        #expect(model.operationState == nil)
        #expect(await installCalls.value == 0)
    }

    @Test("cancelled postflight retains parent ownership and suppresses returned inspection")
    func cancelledPostflightRetainsParentOwnership() async {
        let fullProbe = InspectionProbe<ProvisioningInspection>()
        await fullProbe.resolve(inspection(fnmState: .missing("fnm missing"), nodeState: .missing("Node missing"), pnpmState: .unverified("Node required")))
        let targetProbe = InspectionProbe<ProvisioningTargetedInspection>()
        let installStarted = AsyncSignal()
        let recorder = InstallationRecorderBox()
        let dependencies = ProvisioningModelDependencies(
            inspect: { await fullProbe.wait() },
            inspectTarget: { _ in await targetProbe.wait() },
            installFNM: {
                await installStarted.signal()
                return successfulProcess()
            },
            recordInstallation: recorder.record
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()
        let installTask = Task { await model.installRuntimeTool(.fnm) }
        await targetProbe.waitUntilStarted()
        await targetProbe.resolve(targetedInspection(.fnm, fnmState: .missing("preflight missing")))
        await installStarted.wait()
        await targetProbe.waitUntilStarted(2)
        let checksBeforeCancellation = model.checks
        let ownership = model.operationState
        installTask.cancel()
        #expect(model.operationState == ownership)
        #expect(model.isBusy)

        await targetProbe.resolve(targetedInspection(.fnm, fnmState: .ready("stale postflight"), fnmURL: URL(fileURLWithPath: "/tmp/stale-postflight")))
        await installTask.value
        #expect(model.operationState == nil)
        #expect(model.checks == checksBeforeCancellation)
        #expect(model.checks.first(where: { $0.id == .fnm })?.state == .missing("preflight missing"))
        #expect(model.runtimeContext == nil)
        #expect(await recorder.value == 1)

        let current = Task { await model.checkTool(.fnm) }
        await targetProbe.waitUntilStarted(3)
        await targetProbe.resolve(targetedInspection(.fnm, fnmState: .ready("current fnm"), fnmURL: URL(fileURLWithPath: "/tmp/current-fnm")))
        await current.value
        #expect(model.checks.first(where: { $0.id == .fnm })?.state == .ready("current fnm"))
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

/// A deterministic, cancellation-agnostic dependency probe. It signals entry
/// before suspending, so tests never use a yield as a proxy for operation state.
private actor InspectionProbe<Value: Sendable> {
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var pending: [Value] = []
    private var startedCount = 0
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var calls: Int { startedCount }

    func wait() async -> Value {
        startedCount += 1
        let ready = startWaiters.filter { $0.0 <= startedCount }
        startWaiters.removeAll { $0.0 <= startedCount }
        ready.forEach { $0.1.resume() }
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted(_ expected: Int = 1) async {
        guard startedCount < expected else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expected, continuation))
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
