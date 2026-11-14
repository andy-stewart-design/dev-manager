import Combine
import Darwin
import Foundation

/// Host-facing work is kept behind small closures so model operation tests can
/// control completion without launching installers or probing the machine.
struct ProvisioningModelDependencies {
    typealias CommandLineToolsRequester = @Sendable (@escaping @Sendable (Int32) -> Void) throws -> Void
    typealias HomebrewDownloader = @Sendable (@escaping @Sendable @MainActor () -> Void) async throws -> URL
    typealias InstallationRecorder = @Sendable (String, ProvisioningProcessResult) -> ProvisioningInstallationLog.AppendResult

    let inspect: @Sendable () async -> ProvisioningInspection
    let inspectTarget: @Sendable (ProvisioningCheck.ID) async -> ProvisioningTargetedInspection
    let requestCommandLineTools: CommandLineToolsRequester
    let downloadHomebrew: HomebrewDownloader
    let openHomebrewPackage: @MainActor @Sendable (URL) -> Bool
    let installFNM: @Sendable () async -> ProvisioningProcessResult
    let installNode: @Sendable (URL, URL?) async -> ProvisioningProcessResult
    let installPnpm: @Sendable (ProvisioningRuntimeContext) async -> ProvisioningProcessResult
    let recordInstallation: InstallationRecorder

    nonisolated init(
        inspect: @escaping @Sendable () async -> ProvisioningInspection = { await ProvisioningInspector.inspect() },
        inspectTarget: @escaping @Sendable (ProvisioningCheck.ID) async -> ProvisioningTargetedInspection = { await ProvisioningInspector.inspect(target: $0) },
        requestCommandLineTools: @escaping CommandLineToolsRequester = ProvisioningModelDependencies.defaultCommandLineToolsRequester,
        downloadHomebrew: @escaping HomebrewDownloader = { try await HomebrewPackageInstaller.downloadPackage(onDownloadReady: $0) },
        openHomebrewPackage: @escaping @MainActor @Sendable (URL) -> Bool = { HomebrewPackageInstaller.openPackage($0) },
        installFNM: @escaping @Sendable () async -> ProvisioningProcessResult = { await ProvisioningRuntimeInstaller.installFNM() },
        installNode: @escaping @Sendable (URL, URL?) async -> ProvisioningProcessResult = { await ProvisioningRuntimeInstaller.installNode(using: $0, fnmDirectoryURL: $1) },
        installPnpm: @escaping @Sendable (ProvisioningRuntimeContext) async -> ProvisioningProcessResult = { await ProvisioningRuntimeInstaller.installPnpm(using: $0) },
        recordInstallation: @escaping InstallationRecorder = { label, result in
            ProvisioningInstallationLog.append(commandLabel: label, result: result)
        }
    ) {
        self.inspect = inspect
        self.inspectTarget = inspectTarget
        self.requestCommandLineTools = requestCommandLineTools
        self.downloadHomebrew = downloadHomebrew
        self.openHomebrewPackage = openHomebrewPackage
        self.installFNM = installFNM
        self.installNode = installNode
        self.installPnpm = installPnpm
        self.recordInstallation = recordInstallation
    }

    private static let defaultCommandLineToolsRequester: CommandLineToolsRequester = { completion in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        process.terminationHandler = { process in completion(process.terminationStatus) }
        try process.run()
    }
}

@MainActor
final class ProvisioningModel: ObservableObject {
    static var nodeVersion: String { ProvisioningRuntimePolicy.recommendedNodeVersion }
    static var pnpmVersion: String { ProvisioningRuntimePolicy.recommendedPnpmVersion }

    enum ToolPhase: Equatable {
        case preflight(UUID)
        case installing
        case reinspecting(UUID)
        case handoff
    }

    enum ShellOperation: Equatable {
        case configuring
        case verifying
        case restoring
    }

    private enum InspectionPhase {
        case preflight
        case reinspecting
    }

    /// One coordinator state is authoritative for all work. A tool operation
    /// owns a nested inspection token during preflight and post-install
    /// refresh, which is why inspection is not a mutually exclusive operation.
    enum OperationState: Equatable {
        case inspection(token: UUID, target: ProvisioningCheck.ID?)
        case tool(token: UUID, target: ProvisioningCheck.ID, phase: ToolPhase)
        case shell(token: UUID, kind: ShellOperation)
    }

    let dependencies: ProvisioningModelDependencies
    @Published private(set) var operationState: OperationState?
    @Published private(set) var checks: [ProvisioningCheck] = []
    @Published private(set) var installationLogURL: URL? = ProvisioningInstallationLog.existingLogURL()
    @Published private(set) var installationFailureLogURL: URL?
    @Published private(set) var installationLogWarning: String?
#if DEBUG
    @Published private(set) var fixtureURL: URL?
    @Published private(set) var fixtureCommand: String?
#endif
    /// The last atomically applied concrete context. It is cleared when a
    /// runtime refresh cannot establish a usable context.
    @Published private(set) var runtimeContext: ProvisioningRuntimeContext?

    enum MessagePresentation: Equatable {
        case progress(String)
        case error(String)

        var text: String {
            switch self {
            case let .progress(text), let .error(text): return text
            }
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    @Published private(set) var messagePresentation: MessagePresentation?
    @Published private(set) var shellConfigurationStatus = "The optional fnm shell configuration has not been checked."
    @Published private(set) var shellVerificationOutput = ""
    @Published var isShowingToolConsent = false
#if DEBUG
    @Published var isShowingFixtureConsent = false
#endif
    @Published var isShowingShellConfigurationConsent = false
    @Published var isShowingShellRestoreConsent = false

    @Published private(set) var hasCompletedCheck = false
    @Published private(set) var hasLoadedInitialInspection = false
    @Published private(set) var commandLineToolsRequestNeedsCheck = false
    @Published private(set) var homebrewHandoffNeedsCheck = false
    @Published private(set) var shellInspection = ProvisioningShellConfiguration.Inspection.notConfigured("The optional fnm shell configuration has not been checked.")

    // These computed properties preserve the view-facing API while deriving
    // status from the single operation state above.
    var activeToolID: ProvisioningCheck.ID? {
        guard case let .tool(_, target, _) = operationState else { return nil }
        return target
    }

    var activeInspectionID: UUID? {
        switch operationState {
        case let .inspection(token, _): return token
        case let .tool(_, _, phase):
            switch phase {
            case let .preflight(token), let .reinspecting(token): return token
            case .installing, .handoff: return nil
            }
        case .shell, nil: return nil
        }
    }

    var activeInspectionTargetID: ProvisioningCheck.ID? {
        switch operationState {
        case let .inspection(_, target): return target
        case let .tool(_, target, phase):
            switch phase {
            case .preflight, .reinspecting: return target
            case .installing, .handoff: return nil
            }
        case .shell, nil: return nil
        }
    }

    var isChecking: Bool { activeInspectionID != nil }
    var isRequestingCommandLineTools: Bool {
        if case .tool(_, target: .developerTools, _) = operationState { return true }
        return false
    }
    var isDownloadingHomebrew: Bool {
        if case .tool(_, target: .homebrew, _) = operationState { return true }
        return false
    }
    var isInstallingRuntime: Bool {
        guard case let .tool(_, target, _) = operationState else { return false }
        return [.fnm, .node, .pnpm].contains(target)
    }
    var isConfiguringShell: Bool {
        if case .shell(_, kind: .configuring) = operationState { return true }
        return false
    }
    var isVerifyingShell: Bool {
        if case .shell(_, kind: .verifying) = operationState { return true }
        return false
    }
    var isRestoringShell: Bool {
        if case .shell(_, kind: .restoring) = operationState { return true }
        return false
    }
    private var fnmExecutableURL: URL?
    /// Retained independently of runtimeContext so a missing Node can still be
    /// installed into the exact root selected by read-only fnm inspection.
    private(set) var chosenFNMDirectoryURL: URL?

    init(dependencies: ProvisioningModelDependencies = ProvisioningModelDependencies()) {
        self.dependencies = dependencies
    }

    var supportedEnvironmentIssue: String? { Self.environmentIssue }

    private func showProgress(_ text: String) { messagePresentation = .progress(text) }
    private func showError(_ text: String) { messagePresentation = .error(text) }
    private func clearMessage() { messagePresentation = nil }

    var isSupportedEnvironment: Bool { supportedEnvironmentIssue == nil }
    var isBusy: Bool {
        let hasActiveOperation = operationState != nil ||
            isShowingToolConsent || isShowingShellConfigurationConsent || isShowingShellRestoreConsent
#if DEBUG
        return hasActiveOperation || isShowingFixtureConsent
#else
        return hasActiveOperation
#endif
    }

    enum ToolRowAction: Equatable {
        case none
        case install(label: String, reason: String, enabled: Bool)
        case check(label: String, reason: String, enabled: Bool)
        case progress(String)

        var label: String? {
            switch self {
            case .none, .progress: return nil
            case let .install(label, _, _), let .check(label, _, _): return label
            }
        }

        var reason: String? {
            switch self {
            case .none: return nil
            case let .install(_, reason, _), let .check(_, reason, _), let .progress(reason): return reason
            }
        }

        var isEnabled: Bool {
            switch self {
            case let .install(_, _, enabled): return enabled
            case let .check(_, _, enabled): return enabled
            case .none, .progress: return false
            }
        }
    }

    var allRuntimeToolsReady: Bool {
        checks.first(where: { $0.id == .fnm })?.state.isReady == true &&
            nodeState?.isReady == true && pnpmState?.isReady == true &&
            runtimeContext?.isManagedByFNM == true && runtimeContext?.hasUsablePnpm == true
    }

    var developerToolsReady: Bool {
        checks.first(where: { $0.id == .developerTools })?.state.isReady == true
    }

    func rowAction(for id: ProvisioningCheck.ID) -> ToolRowAction {
        if let activeToolID {
            if activeToolID == id { return .progress(progressLabel(for: id)) }
            return disabledAction(for: id)
        }
        if let target = activeInspectionTargetID {
            if target == id { return .progress("Checking \(id.title)…") }
            return disabledAction(for: id)
        }
        if isChecking || activeInspectionID != nil {
            return disabledAction(for: id)
        }
        if isBusy {
            return disabledAction(for: id)
        }
        if id == .developerTools, commandLineToolsRequestNeedsCheck {
            return .check(label: "Check installation", reason: "Apple's installer was opened. Finish or cancel it, then verify the actual installation.", enabled: true)
        }
        if id == .homebrew, homebrewHandoffNeedsCheck {
            return .check(label: "Check installation", reason: "Homebrew Installer was opened. Finish or cancel it, then verify the actual installation.", enabled: true)
        }

        guard let state = state(for: id) else {
            return .install(label: "Install", reason: "Check the machine before installing this tool.", enabled: false)
        }
        switch state {
        case .ready:
            return .none
        case let .attention(detail):
            return .check(label: "Check again", reason: detail, enabled: true)
        case let .waiting(detail):
            return .check(label: "Check installation", reason: detail, enabled: true)
        case .checking:
            return .progress("Checking the current machine state…")
        case let .missing(detail), let .unverified(detail):
            let prerequisite = prerequisiteReason(for: id)
            let eligible = isSupportedEnvironment && hasCompletedCheck && prerequisite == nil && isInstallableMissing(id)
            return .install(label: "Install", reason: eligible ? detail : (prerequisite ?? detail), enabled: eligible)
        }
    }

    private func disabledAction(for id: ProvisioningCheck.ID) -> ToolRowAction {
        guard let state = state(for: id) else {
            return .install(label: "Install", reason: "Another setup operation is in progress.", enabled: false)
        }
        switch state {
        case .ready:
            return .none
        case let .attention(detail):
            return .check(label: "Check again", reason: "Another setup operation is in progress. \(detail)", enabled: false)
        case let .waiting(detail):
            return .check(label: "Check installation", reason: "Another setup operation is in progress. \(detail)", enabled: false)
        default:
            return .install(label: "Install", reason: "Another setup operation is in progress.", enabled: false)
        }
    }

    private func progressLabel(for id: ProvisioningCheck.ID) -> String {
        switch id {
        case .developerTools: return "Requesting Apple's installer…"
        case .homebrew: return "Opening Homebrew Installer…"
        case .fnm: return "Installing fnm…"
        case .node: return "Installing Node…"
        case .pnpm: return "Installing pnpm…"
        }
    }

    private func isInstallableMissing(_ id: ProvisioningCheck.ID) -> Bool {
        switch id {
        case .developerTools: return state(for: id)?.isMissing == true && !commandLineToolsRequestNeedsCheck
        case .homebrew: return state(for: id)?.isMissing == true && !homebrewHandoffNeedsCheck && developerToolsReady
        case .fnm, .node, .pnpm: return state(for: id)?.isMissing == true
        }
    }

    private func prerequisiteReason(for id: ProvisioningCheck.ID) -> String? {
        guard isSupportedEnvironment else { return supportedEnvironmentIssue.map { "Setup is unavailable: \($0)." } }
        guard hasCompletedCheck else { return "Check installation before installing a tool." }
        switch id {
        case .node:
            guard developerToolsReady, state(for: .homebrew)?.isReady == true,
                  state(for: .fnm)?.isReady == true else {
                return "Install and verify Apple developer tools, Homebrew, and fnm first."
            }
        case .pnpm:
            guard developerToolsReady, state(for: .homebrew)?.isReady == true,
                  state(for: .fnm)?.isReady == true,
                  state(for: .node)?.isReady == true,
                  runtimeContext?.isManagedByFNM == true else {
                return "Install and verify Apple developer tools, Homebrew, fnm, and a managed Node first."
            }
        case .developerTools, .homebrew, .fnm:
            let dependencyOrder: [ProvisioningCheck.ID] = [.developerTools, .homebrew, .fnm]
            for prerequisite in dependencyOrder.prefix(while: { $0 != id }) {
                if state(for: prerequisite)?.isReady != true {
                    return "Install and verify \(prerequisite.title) first."
                }
            }
        }
        return nil
    }

    var canRequestCommandLineTools: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && !commandLineToolsRequestNeedsCheck &&
            checks.first(where: { $0.id == .developerTools })?.state.isMissing == true
    }

    var canRequestHomebrew: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && developerToolsReady &&
            !homebrewHandoffNeedsCheck && homebrewMissing
    }

    func canInstallRuntimeTool(_ id: ProvisioningCheck.ID) -> Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy &&
            prerequisiteReason(for: id) == nil && isInstallableMissing(id)
    }

#if DEBUG
    var canPrepareFixture: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && allRuntimeToolsReady
    }
#endif

    var canConfigureShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && allRuntimeToolsReady &&
            runtimeContext?.isManagedByFNM == true && ifConfiguredInspectionAllowsConfigure
    }

    private var ifConfiguredInspectionAllowsConfigure: Bool {
        if case .notConfigured = shellInspection { return true }
        return false
    }

    var canVerifyShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && allRuntimeToolsReady &&
            runtimeContext?.isManagedByFNM == true && shellInspection.isConfigured
    }

    var canRestoreShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && ProvisioningShellConfiguration.canRestore()
    }

    private var homebrewMissing: Bool { homebrewState?.isMissing == true }
    private var homebrewState: ProvisioningCheck.State? { state(for: .homebrew) }
    private var nodeState: ProvisioningCheck.State? { state(for: .node) }
    private var pnpmState: ProvisioningCheck.State? { state(for: .pnpm) }

    private func state(for id: ProvisioningCheck.ID) -> ProvisioningCheck.State? {
        checks.first(where: { $0.id == id })?.state
    }

    func checkAgain() async {
        // A tool's own preflight/post-install refresh is represented inside its
        // tool state. Public inspections never replace an operation they do not own.
        guard operationState == nil else { return }

        let operationID = UUID()
        let isInitialInspection = !hasLoadedInitialInspection
        operationState = .inspection(token: operationID, target: nil)
        defer { finishInspection(operationID) }
        if isInitialInspection {
            hasCompletedCheck = false
            checks = ProvisioningCheck.all
        }
        showProgress("Inspecting installed tools…")

        let inspection = await withTaskCancellationHandler {
            await dependencies.inspect()
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishInspection(operationID)
            }
        }
        guard !Task.isCancelled, ownsInspection(operationID, target: nil) else { return }

        // Apply checks and their concrete context together so a failed refresh
        // cannot leave an old runtime eligible for a machine-changing action.
        fnmExecutableURL = inspection.fnmExecutableURL
        chosenFNMDirectoryURL = inspection.chosenFNMDirectoryURL
        runtimeContext = inspection.runtimeContext
        checks = [inspection.developerTools, inspection.homebrew, inspection.fnm, inspection.node, inspection.pnpm]
        hasCompletedCheck = true
        if isInitialInspection { hasLoadedInitialInspection = true }
        commandLineToolsRequestNeedsCheck = false
        homebrewHandoffNeedsCheck = false
        refreshShellInspection()
        if let supportedEnvironmentIssue {
            showError("Machine-changing setup is disabled: \(supportedEnvironmentIssue)")
        } else {
            clearMessage()
        }
    }

    func checkTool(_ id: ProvisioningCheck.ID) async {
        guard hasLoadedInitialInspection, operationState == nil, !isBusy else { return }

        let operationID = UUID()
        operationState = .inspection(token: operationID, target: id)
        defer { finishInspection(operationID) }
        showProgress("Checking \(id.title)…")

        let inspection = await withTaskCancellationHandler {
            await dependencies.inspectTarget(id)
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishInspection(operationID)
            }
        }
        guard !Task.isCancelled, ownsInspection(operationID, target: id) else { return }
        apply(inspection, for: id)
        if id == .developerTools { commandLineToolsRequestNeedsCheck = false }
        if id == .homebrew { homebrewHandoffNeedsCheck = false }
        refreshShellInspection()
        clearMessage()
    }

    private func refreshShellInspection() {
        shellInspection = ProvisioningShellConfiguration.inspect()
        shellConfigurationStatus = shellInspection.message
    }

    private func apply(_ inspection: ProvisioningTargetedInspection, for target: ProvisioningCheck.ID) {
        let returned = Dictionary(uniqueKeysWithValues: inspection.checks.map { ($0.id, $0) })
        checks = checks.map { returned[$0.id] ?? $0 }
        if [.fnm, .node, .pnpm].contains(target) {
            // A failed runtime context must not leave an old URL/context eligible
            // for writes. The fnm executable itself remains available for a
            // missing Node install, while shell actions require context.
            fnmExecutableURL = inspection.fnmExecutableURL
            chosenFNMDirectoryURL = inspection.chosenFNMDirectoryURL
            runtimeContext = inspection.runtimeContext
        }
        refreshShellInspection()
    }

    func requestCommandLineTools() async {
        guard canRequestCommandLineTools else { return }
        let operationID = UUID()
        operationState = .tool(token: operationID, target: .developerTools, phase: .preflight(UUID()))
        guard await inspectTarget(.developerTools, operationID: operationID, phase: .preflight) else {
            finishToolOperation(.developerTools, operationID: operationID)
            return
        }
        guard ownsTool(.developerTools, operationID: operationID), state(for: .developerTools)?.isMissing == true else {
            finishToolOperation(.developerTools, operationID: operationID)
            showError("Apple developer tools changed while setup was waiting; no installer was opened. Check installation again.")
            return
        }
        operationState = .tool(token: operationID, target: .developerTools, phase: .handoff)
        commandLineToolsRequestNeedsCheck = true
        setDeveloperToolsState(.waiting("Apple's installer dialog was requested. Finish or cancel it, then press Check installation; opening the dialog is not completion."))
        showProgress("Requesting Apple's Command Line Tools installer dialog…")

        do {
            try dependencies.requestCommandLineTools { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self, self.ownsTool(.developerTools, operationID: operationID) else { return }
                    self.finishToolOperation(.developerTools, operationID: operationID)
                    if status == 0 {
                        self.clearMessage()
                    } else {
                        self.showError("Could not request Apple's Command Line Tools installer (status \(status)). Press Check installation before retrying.")
                    }
                }
            }
        } catch {
            guard ownsTool(.developerTools, operationID: operationID) else { return }
            finishToolOperation(.developerTools, operationID: operationID)
            showError("Could not request Apple's Command Line Tools installer: \(error.localizedDescription)")
        }
    }

    func downloadAndOpenHomebrewPackage() async {
        guard canRequestHomebrew else { return }
        let operationID = UUID()
        operationState = .tool(token: operationID, target: .homebrew, phase: .preflight(UUID()))
        defer { finishToolOperation(.homebrew, operationID: operationID) }
        guard await inspectTarget(.homebrew, operationID: operationID, phase: .preflight) else {
            finishToolOperation(.homebrew, operationID: operationID)
            return
        }
        guard ownsTool(.homebrew, operationID: operationID), state(for: .homebrew)?.isMissing == true else {
            finishToolOperation(.homebrew, operationID: operationID)
            showError("Homebrew changed while setup was waiting; no package was opened. Check installation again.")
            return
        }
        operationState = .tool(token: operationID, target: .homebrew, phase: .handoff)
        homebrewHandoffNeedsCheck = true
        setHomebrewState(.waiting("Preparing the official Homebrew.pkg; installation is not complete."))
        showProgress("Looking up the latest official Homebrew.pkg…")

        do {
            let packageURL = try await withTaskCancellationHandler {
                try await dependencies.downloadHomebrew { [weak self] in
                    guard let self, self.ownsTool(.homebrew, operationID: operationID) else { return }
                    self.showProgress("Downloading Homebrew.pkg from Homebrew's official release…")
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.finishToolOperation(.homebrew, operationID: operationID)
                }
            }
            guard !Task.isCancelled, ownsTool(.homebrew, operationID: operationID), dependencies.openHomebrewPackage(packageURL) else {
                if ownsTool(.homebrew, operationID: operationID) { throw HomebrewProvisioningError.couldNotOpenInstaller }
                return
            }
            guard ownsTool(.homebrew, operationID: operationID) else { return }
            setHomebrewState(.waiting("Homebrew.pkg was opened in macOS Installer. Finish or cancel it, then press Check installation; opening it is not success."))
            clearMessage()
        } catch {
            guard !Task.isCancelled, ownsTool(.homebrew, operationID: operationID) else { return }
            setHomebrewState(.attention("Homebrew handoff failed: \(error.localizedDescription)"))
            showError("Homebrew handoff failed: \(error.localizedDescription) Press Check installation before retrying.")
        }
        finishToolOperation(.homebrew, operationID: operationID)
    }

    func installTool(_ id: ProvisioningCheck.ID) async {
        // The consent dialog owns this transition; release its UI lock before
        // the existing eligibility guards run.
        isShowingToolConsent = false
        switch id {
        case .developerTools:
            await requestCommandLineTools()
        case .homebrew:
            await downloadAndOpenHomebrewPackage()
        case .fnm, .node, .pnpm:
            await installRuntimeTool(id)
        }
    }

    func installRuntimeTool(_ id: ProvisioningCheck.ID) async {
        guard [.fnm, .node, .pnpm].contains(id), canInstallRuntimeTool(id) else { return }
        let operationID = UUID()
        operationState = .tool(token: operationID, target: id, phase: .preflight(UUID()))
        installationFailureLogURL = nil
        defer { finishToolOperation(id, operationID: operationID) }

        // Reinspect while the target owns the operation. This prevents replacing a
        // tool that was installed outside the app after the row was displayed.
        guard await inspectTarget(id, operationID: operationID, phase: .preflight) else { return }
        guard ownsTool(id, operationID: operationID), let targetState = state(for: id) else { return }
        if targetState.isReady {
            showProgress("\(id.title) is already installed; no change was made.")
            return
        }
        guard targetState.isMissing, runtimePrerequisitesReady(for: id) else {
            showError("\(id.title) needs attention or its prerequisites are not ready. No change was made; review the row and Check again.")
            return
        }
        let fnm = fnmExecutableURL
        if id == .node, fnm == nil {
            showError("fnm is not usable, so the missing Node runtime was not changed.")
            return
        }
        if id == .pnpm, runtimeContext == nil {
            showError("No selected Node context is available, so pnpm was not changed.")
            return
        }

        operationState = .tool(token: operationID, target: id, phase: .installing)
        // ProvisioningCommandRunner intentionally does not terminate its process when the
        // Swift task is cancelled. Keep ownership until the installer await returns so another
        // machine-changing installation cannot overlap the real installer.
        let result: ProvisioningProcessResult
        switch id {
        case .fnm:
            showProgress("Installing fnm through /opt/homebrew/bin/brew…")
            result = await dependencies.installFNM()
        case .node:
            guard let fnm else { return }
            showProgress("Installing Node \(Self.nodeVersion) in fnm…")
            result = await dependencies.installNode(fnm, chosenFNMDirectoryURL)
        case .pnpm:
            guard let context = runtimeContext else { return }
            showProgress("Installing pnpm \(Self.pnpmVersion) inside Node \(context.node.version)…")
            result = await dependencies.installPnpm(context)
        case .developerTools, .homebrew:
            return
        }
        guard !Task.isCancelled, ownsTool(id, operationID: operationID) else { return }
        recordInstallationResult(result, label: installationLabel(for: id))
        guard await inspectTarget(id, operationID: operationID, phase: .reinspecting) else { return }
        guard ownsTool(id, operationID: operationID) else { return }
        if result.succeeded {
            if state(for: id)?.isReady == true {
                clearMessage()
            } else {
                showError("\(id.title) did not become usable after installation. No dependent tool was installed.")
            }
        } else {
            let label = installationLabel(for: id)
            var message = "\(id.title) installation failed: \(result.failureDescription(for: label, timeout: ProvisioningConfiguration.installTimeout)). Dependent tools were not started; review the installation log and Check again."
            if let installationLogWarning { message += " \(installationLogWarning)" }
            showError(message)
        }
    }

#if DEBUG
    func prepareFixture() throws {
        isShowingFixtureConsent = false
        guard canPrepareFixture, let context = runtimeContext else { return }
        showProgress("Preparing the fixture project…")
        do {
            let fixture = try ProvisioningFixture.materialize(using: context)
            fixtureURL = fixture.folder
            fixtureCommand = fixture.command
            clearMessage()
        } catch {
            showError("Fixture preparation failed without changing conflicting files: \(error.localizedDescription)")
            throw error
        }
    }
#endif

    private func runtimePrerequisitesReady(for id: ProvisioningCheck.ID) -> Bool {
        switch id {
        case .fnm, .node, .pnpm: return prerequisiteReason(for: id) == nil
        case .developerTools, .homebrew: return false
        }
    }

    private func installationLabel(for id: ProvisioningCheck.ID) -> String {
        switch id {
        case .fnm: return "brew install fnm"
        case .node: return "fnm install \(Self.nodeVersion)"
        case .pnpm: return "npm install --global pnpm@\(Self.pnpmVersion)"
        case .developerTools, .homebrew: return id.title
        }
    }

    private func recordInstallationResult(_ result: ProvisioningProcessResult, label: String) {
        switch dependencies.recordInstallation(label, result) {
        case let .wrote(url):
            installationLogURL = url
            installationLogWarning = nil
            installationFailureLogURL = result.succeeded ? nil : url
        case let .failed(detail):
            installationLogWarning = "Installation diagnostics could not be written: \(detail)"
            installationFailureLogURL = nil
        }
    }

    func configureShell() throws {
        isShowingShellConfigurationConsent = false
        installationFailureLogURL = nil
        guard canConfigureShell, let context = runtimeContext else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsupported("a supported fnm-managed Node/pnpm context is not ready")
        }
        let fnmURL = context.fnmExecutableURL
        let selector = context.fnmSelector
        let operationID = UUID()
        operationState = .shell(token: operationID, kind: .configuring)
        showProgress("Configuring the optional shell…")
        defer { finishShellOperation(operationID) }
        do {
            shellConfigurationStatus = try ProvisioningShellConfiguration.configure(
                using: fnmURL,
                nodeVersion: selector,
                fnmDirectoryURL: context.chosenFNMDirectoryURL
            )
            shellInspection = ProvisioningShellConfiguration.inspect()
            clearMessage()
        } catch {
            shellConfigurationStatus = error.localizedDescription
            shellInspection = ProvisioningShellConfiguration.inspect()
            showError(error.localizedDescription)
            throw error
        }
    }

    func verifyFreshShell() async {
        guard canVerifyShell else { return }
        installationFailureLogURL = nil
        let operationID = UUID()
        operationState = .shell(token: operationID, kind: .verifying)
        showProgress("Checking a fresh interactive Zsh…")
        defer { finishShellOperation(operationID) }
        do {
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let shell = try ShellEnvironment.currentZsh(homeDirectory: home, zdotdir: home)
            var environment = shell.environment
            if let context = runtimeContext, context.isManagedByFNM {
                environment["FNM_DIR"] = context.chosenFNMDirectoryURL.path
            }
            if let context = runtimeContext {
                environment["PATH"] = ProvisioningExecutablePaths.runtimePATH(
                    selectedNodeURL: context.node.executableURL,
                    inheritedPATH: environment["PATH"] ?? "",
                    safeSystemPATH: ProvisioningConfiguration.safeSystemPATH
                )
            }
            environment["FNM_COREPACK_ENABLED"] = "false"
            environment["COREPACK_ENABLE_NETWORK"] = "0"
            environment["COREPACK_DEFAULT_TO_LATEST"] = "0"
            environment["COREPACK_ENABLE_PROJECT_SPEC"] = "0"
            let script = """
            set -e
            printf 'fnm=%s\\n' "$(command -v fnm)"
            printf 'fnm_version=%s\\n' "$(fnm --version)"
            printf 'node=%s\\n' "$(command -v node)"
            printf 'node_version=%s\\n' "$(node --version)"
            printf 'pnpm=%s\\n' "$(command -v pnpm)"
            printf 'pnpm_version=%s\\n' "$(pnpm --version)"
            """
            let result = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-i", "-c", script], environment: environment)
            guard !Task.isCancelled, ownsShell(operationID) else { return }
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\nstderr:\n")
            shellVerificationOutput = String(output.suffix(8_000))
            guard result.succeeded else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("fresh interactive Zsh verification failed: \(result.failureDescription(for: "/bin/zsh -i -c", timeout: ProvisioningConfiguration.commandTimeout))")
            }
            let values = result.stdout.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { values, line in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                values[parts[0]] = parts[1]
            }
            guard let nodeVersion = values["node_version"],
                  let pnpmVersion = values["pnpm_version"],
                  ProvisioningRuntimePolicy.isSupportedNodeVersion(nodeVersion),
                  ProvisioningRuntimePolicy.isSupportedPnpmVersion(pnpmVersion),
                  values["fnm"]?.hasPrefix("/") == true, values["node"]?.hasPrefix("/") == true,
                  values["pnpm"]?.hasPrefix("/") == true else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("fresh interactive Zsh did not resolve a supported stable Node/pnpm pair with absolute paths; no shell file was changed")
            }
            shellConfigurationStatus = "Fresh interactive Zsh verified \(nodeVersion) and pnpm \(pnpmVersion) at the reported absolute paths. This check used /bin/zsh -i -c and did not use a login shell."
            clearMessage()
        } catch {
            guard !Task.isCancelled, ownsShell(operationID) else { return }
            shellConfigurationStatus = error.localizedDescription
            showError(error.localizedDescription)
        }
    }

    func restoreShell() throws {
        isShowingShellRestoreConsent = false
        installationFailureLogURL = nil
        guard canRestoreShell else {
            refreshShellInspection()
            let refusal = "Restore was refused after rechecking the optional shell configuration: \(shellInspection.message)"
            showError(refusal)
            throw ProvisioningShellConfiguration.ConfigurationError.conflict(refusal)
        }
        let operationID = UUID()
        operationState = .shell(token: operationID, kind: .restoring)
        showProgress("Restoring the optional shell configuration…")
        defer { finishShellOperation(operationID) }
        do {
            shellConfigurationStatus = try ProvisioningShellConfiguration.restore()
            shellInspection = ProvisioningShellConfiguration.inspect()
            clearMessage()
        } catch {
            shellConfigurationStatus = error.localizedDescription
            shellInspection = ProvisioningShellConfiguration.inspect()
            showError(error.localizedDescription)
            throw error
        }
    }

    private func inspectTarget(_ id: ProvisioningCheck.ID, operationID: UUID, phase: InspectionPhase) async -> Bool {
        guard ownsTool(id, operationID: operationID) else { return false }
        let inspectionToken = UUID()
        switch phase {
        case .preflight:
            operationState = .tool(token: operationID, target: id, phase: .preflight(inspectionToken))
        case .reinspecting:
            operationState = .tool(token: operationID, target: id, phase: .reinspecting(inspectionToken))
        }
        showProgress("Checking \(id.title)…")
        let inspection = await withTaskCancellationHandler {
            await dependencies.inspectTarget(id)
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishToolOperation(id, operationID: operationID)
            }
        }
        guard !Task.isCancelled, ownsToolInspection(id, operationID: operationID, inspectionToken: inspectionToken) else { return false }
        apply(inspection, for: id)
        operationState = .tool(token: operationID, target: id, phase: .installing)
        return true
    }

    private func ownsTool(_ id: ProvisioningCheck.ID, operationID: UUID) -> Bool {
        guard case let .tool(token, target, _) = operationState else { return false }
        return token == operationID && target == id
    }

    private func ownsToolInspection(_ id: ProvisioningCheck.ID, operationID: UUID, inspectionToken: UUID) -> Bool {
        guard case let .tool(token, target, phase) = operationState else { return false }
        switch phase {
        case let .preflight(token: current), let .reinspecting(token: current):
            return token == operationID && target == id && current == inspectionToken
        case .installing, .handoff:
            return false
        }
    }

    private func ownsInspection(_ operationID: UUID, target: ProvisioningCheck.ID?) -> Bool {
        guard case let .inspection(token, currentTarget) = operationState else { return false }
        return token == operationID && currentTarget == target
    }

    private func finishInspection(_ operationID: UUID) {
        guard case let .inspection(token, _) = operationState, token == operationID else { return }
        operationState = nil
    }

    private func finishToolOperation(_ id: ProvisioningCheck.ID, operationID: UUID) {
        guard ownsTool(id, operationID: operationID) else { return }
        operationState = nil
    }

    private func ownsShell(_ operationID: UUID) -> Bool {
        guard case let .shell(token, _) = operationState else { return false }
        return token == operationID
    }

    private func finishShellOperation(_ operationID: UUID) {
        guard ownsShell(operationID) else { return }
        operationState = nil
    }

    private func setHomebrewState(_ state: ProvisioningCheck.State) {
        guard checks.contains(where: { $0.id == .homebrew }) else { return }
        checks = checks.map { $0.id == .homebrew ? ProvisioningCheck(id: .homebrew, state: state) : $0 }
    }

    private func setDeveloperToolsState(_ state: ProvisioningCheck.State) {
        guard checks.contains(where: { $0.id == .developerTools }) else { return }
        checks = checks.map { $0.id == .developerTools ? ProvisioningCheck(id: .developerTools, state: state) : $0 }
    }

    private static var environmentIssue: String? {
        var issues: [String] = []
        if !isAppleSilicon { issues.append("this is not an Apple Silicon process") }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15 { issues.append("macOS 15 or later is required") }
        if !isLoggedInAdministrator { issues.append("the logged-in user is not an administrator") }
        return issues.isEmpty ? nil : issues.joined(separator: "; ")
    }

    private static var isAppleSilicon: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0")) == "arm64"
        }
    }

    private static var isLoggedInAdministrator: Bool {
        guard let adminGroup = getgrnam("admin") else { return false }
        let adminGID = adminGroup.pointee.gr_gid
        let count = getgroups(0, nil)
        guard count >= 0 else { return false }
        var groups = [gid_t](repeating: 0, count: Int(count))
        if count > 0 && getgroups(count, &groups) < 0 { return false }
        return getgid() == adminGID || groups.contains(adminGID)
    }
}
