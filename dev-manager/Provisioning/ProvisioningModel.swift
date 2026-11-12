#if DEBUG
import Combine
import Darwin
import Foundation

@MainActor
final class ProvisioningModel: ObservableObject {
    static var nodeVersion: String { ProvisioningConfiguration.nodeVersion }
    static var pnpmVersion: String { ProvisioningConfiguration.pnpmVersion }

    @Published private(set) var checks: [ProvisioningCheck] = []
    @Published private(set) var isChecking = false
    @Published private(set) var isRequestingCommandLineTools = false
    @Published private(set) var isDownloadingHomebrew = false
    @Published private(set) var isInstallingRuntime = false
    @Published private(set) var installationOutput = ""
    @Published private(set) var fixtureURL: URL?
    @Published private(set) var fixtureCommand: String?

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
    @Published private(set) var isConfiguringShell = false
    @Published private(set) var isVerifyingShell = false
    @Published private(set) var isRestoringShell = false
    @Published var isShowingToolConsent = false
    @Published var isShowingFixtureConsent = false
    @Published var isShowingShellConfigurationConsent = false
    @Published var isShowingShellRestoreConsent = false

    @Published private(set) var hasCompletedCheck = false
    @Published private(set) var commandLineToolsRequestNeedsCheck = false
    @Published private(set) var homebrewHandoffNeedsCheck = false
    @Published private(set) var activeToolID: ProvisioningCheck.ID?
    @Published private(set) var shellInspection = ProvisioningShellConfiguration.Inspection.notConfigured("The optional fnm shell configuration has not been checked.")
    private var checkGeneration = 0
    private var fnmExecutableURL: URL?

    var supportedEnvironmentIssue: String? { Self.environmentIssue }

    private func showProgress(_ text: String) { messagePresentation = .progress(text) }
    private func showError(_ text: String) { messagePresentation = .error(text) }
    private func clearMessage() { messagePresentation = nil }

    var isSupportedEnvironment: Bool { supportedEnvironmentIssue == nil }
    var isBusy: Bool {
        isChecking || isRequestingCommandLineTools || isDownloadingHomebrew || isInstallingRuntime ||
            isConfiguringShell || isVerifyingShell || isRestoringShell
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
        fnmState?.isReady == true && nodeState?.isReady == true && pnpmState?.isReady == true
    }

    var developerToolsReady: Bool {
        checks.first(where: { $0.id == .developerTools })?.state.isReady == true
    }

    func rowAction(for id: ProvisioningCheck.ID) -> ToolRowAction {
        if let activeToolID {
            if activeToolID == id { return .progress(progressLabel(for: id)) }
            return disabledAction(for: id)
        }
        if isChecking { return .progress("Checking the current machine state…") }
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
        let dependencyOrder: [ProvisioningCheck.ID] = [.developerTools, .homebrew, .fnm, .node, .pnpm]
        for prerequisite in dependencyOrder.prefix(while: { $0 != id }) {
            if state(for: prerequisite)?.isReady != true {
                return "Install and verify \(prerequisite.title) first."
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

    var canPrepareFixture: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && allRuntimeToolsReady
    }

    var canConfigureShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && allRuntimeToolsReady
    }

    var canVerifyShell: Bool {
        canConfigureShell && shellInspection.isConfigured
    }

    var canRestoreShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isBusy && ProvisioningShellConfiguration.hasRecordedConfiguration()
    }

    private var homebrewMissing: Bool { homebrewState?.isMissing == true }
    private var homebrewState: ProvisioningCheck.State? { state(for: .homebrew) }
    private var fnmState: ProvisioningCheck.State? { state(for: .fnm) }
    private var nodeState: ProvisioningCheck.State? { state(for: .node) }
    private var pnpmState: ProvisioningCheck.State? { state(for: .pnpm) }

    private func state(for id: ProvisioningCheck.ID) -> ProvisioningCheck.State? {
        checks.first(where: { $0.id == id })?.state
    }

    func checkAgain(allowDuringInstallation: Bool = false) async {
        guard !isChecking && !isRequestingCommandLineTools && !isDownloadingHomebrew &&
                (allowDuringInstallation || !isInstallingRuntime) &&
                !isConfiguringShell && !isVerifyingShell && !isRestoringShell else { return }
        checkGeneration += 1
        let generation = checkGeneration
        hasCompletedCheck = false
        isChecking = true
        showProgress("Inspecting installed tools…")
        checks = ProvisioningCheck.all

        let inspection = await ProvisioningInspector.inspect()
        guard generation == checkGeneration else {
            isChecking = false
            return
        }
        fnmExecutableURL = inspection.fnmExecutableURL
        checks = [inspection.developerTools, inspection.homebrew, inspection.fnm, inspection.node, inspection.pnpm]
        isChecking = false
        hasCompletedCheck = true
        commandLineToolsRequestNeedsCheck = false
        homebrewHandoffNeedsCheck = false
        shellInspection = ProvisioningShellConfiguration.inspect()
        shellConfigurationStatus = shellInspection.message
        if let supportedEnvironmentIssue {
            showError("Machine-changing setup is disabled: \(supportedEnvironmentIssue)")
        } else {
            clearMessage()
        }
    }

    func requestCommandLineTools() async {
        guard canRequestCommandLineTools else { return }
        await checkAgain()
        guard canRequestCommandLineTools else {
            showError("Apple developer tools changed while setup was waiting; no installer was opened. Check installation again.")
            return
        }
        activeToolID = .developerTools
        isRequestingCommandLineTools = true
        commandLineToolsRequestNeedsCheck = true
        setDeveloperToolsState(.waiting("Apple's installer dialog was requested. Finish or cancel it, then press Check installation; opening the dialog is not completion."))
        showProgress("Requesting Apple's Command Line Tools installer dialog…")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRequestingCommandLineTools = false
                self.activeToolID = nil
                let status = process.terminationStatus
                if status == 0 {
                    self.clearMessage()
                } else {
                    self.showError("Could not request Apple's Command Line Tools installer (status \(status)). Press Check installation before retrying.")
                }
            }
        }

        do {
            try process.run()
        } catch {
            isRequestingCommandLineTools = false
            activeToolID = nil
            showError("Could not request Apple's Command Line Tools installer: \(error.localizedDescription)")
        }
    }

    func downloadAndOpenHomebrewPackage() async {
        guard canRequestHomebrew else { return }
        await checkAgain()
        guard canRequestHomebrew else {
            showError("Homebrew changed while setup was waiting; no package was opened. Check installation again.")
            return
        }
        activeToolID = .homebrew
        isDownloadingHomebrew = true
        homebrewHandoffNeedsCheck = true
        setHomebrewState(.waiting("Preparing the official Homebrew.pkg; installation is not complete."))
        showProgress("Looking up the latest official Homebrew.pkg…")

        do {
            let packageURL = try await HomebrewPackageInstaller.downloadPackage { [weak self] in
                self?.showProgress("Downloading Homebrew.pkg from Homebrew's official release…")
            }
            guard HomebrewPackageInstaller.openPackage(packageURL) else {
                throw HomebrewProvisioningError.couldNotOpenInstaller
            }
            setHomebrewState(.waiting("Homebrew.pkg was opened in macOS Installer. Finish or cancel it, then press Check installation; opening it is not success."))
            clearMessage()
        } catch {
            setHomebrewState(.attention("Homebrew handoff failed: \(error.localizedDescription)"))
            showError("Homebrew handoff failed: \(error.localizedDescription) Press Check installation before retrying.")
        }
        isDownloadingHomebrew = false
        activeToolID = nil
    }

    func installTool(_ id: ProvisioningCheck.ID) async {
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
        activeToolID = id
        isInstallingRuntime = true
        installationOutput = ""
        defer {
            isInstallingRuntime = false
            activeToolID = nil
        }

        // Reinspect while the target remains active. This prevents replacing a tool
        // that was installed outside the app after the row was displayed.
        await checkAgain(allowDuringInstallation: true)
        guard let targetState = state(for: id) else { return }
        if targetState.isReady {
            showProgress("\(id.title) is already installed; no change was made.")
            return
        }
        guard targetState.isMissing, runtimePrerequisitesReady(for: id) else {
            showError("\(id.title) needs attention or its prerequisites are not ready. No change was made; review the row and Check again.")
            return
        }
        let fnm = fnmExecutableURL
        if id != .fnm, fnm == nil {
            showError("fnm is not usable, so Node and pnpm were not changed.")
            return
        }

        let result: ProvisioningProcessResult
        switch id {
        case .fnm:
            showProgress("Installing fnm through /opt/homebrew/bin/brew…")
            result = await ProvisioningRuntimeInstaller.installFNM()
        case .node:
            guard let fnm else { return }
            showProgress("Installing Node \(Self.nodeVersion) in fnm…")
            result = await ProvisioningRuntimeInstaller.installNode(using: fnm)
        case .pnpm:
            guard let fnm else { return }
            showProgress("Installing pnpm \(Self.pnpmVersion) inside Node \(Self.nodeVersion)…")
            result = await ProvisioningRuntimeInstaller.installPnpm(using: fnm)
        case .developerTools, .homebrew:
            return
        }
        recordInstallationResult(result, label: installationLabel(for: id))
        await checkAgain(allowDuringInstallation: true)
        if result.succeeded {
            if state(for: id)?.isReady == true {
                clearMessage()
            } else {
                showError("\(id.title) did not become usable after installation. No dependent tool was installed.")
            }
        } else {
            showError("\(id.title) installation failed. Dependent tools were not started; review the visible output and Check again.")
        }
    }

    func prepareFixture() throws {
        guard canPrepareFixture, let fnm = fnmExecutableURL else { return }
        showProgress("Preparing the fixture project…")
        do {
            let fixture = try ProvisioningFixture.materialize(using: fnm)
            fixtureURL = fixture.folder
            fixtureCommand = fixture.command
            clearMessage()
        } catch {
            showError("Fixture preparation failed without changing conflicting files: \(error.localizedDescription)")
            throw error
        }
    }

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
        var text = "\(label) exited with status \(result.terminationStatus)."
        if result.timedOut { text = "\(label) timed out after \(Int(ProvisioningConfiguration.installTimeout / 60)) minutes." }
        if !result.stdout.isEmpty { text += "\nstdout:\n\(result.stdout)" }
        if !result.stderr.isEmpty { text += "\nstderr:\n\(result.stderr)" }
        installationOutput = String((installationOutput + "\n" + text).suffix(16_000))
    }

    func configureShell() throws {
        guard canConfigureShell, let fnmExecutableURL else {
            throw ProvisioningShellConfiguration.ConfigurationError.unsupported("the supported environment and pinned fnm/Node/pnpm runtime are not ready")
        }
        isConfiguringShell = true
        showProgress("Configuring the optional shell…")
        defer { isConfiguringShell = false }
        do {
            shellConfigurationStatus = try ProvisioningShellConfiguration.configure(using: fnmExecutableURL, nodeVersion: Self.nodeVersion)
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
        isVerifyingShell = true
        showProgress("Checking a fresh interactive Zsh…")
        defer { isVerifyingShell = false }
        do {
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let shell = try ShellEnvironment.currentZsh(homeDirectory: home, zdotdir: home)
            var environment = shell.environment
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
            guard values["node_version"] == "v\(Self.nodeVersion)", values["pnpm_version"] == Self.pnpmVersion,
                  values["fnm"]?.hasPrefix("/") == true, values["node"]?.hasPrefix("/") == true,
                  values["pnpm"]?.hasPrefix("/") == true else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("fresh interactive Zsh resolved unexpected fnm, Node, or pnpm paths/versions; no shell file was changed")
            }
            shellConfigurationStatus = "Fresh interactive Zsh verified fnm, Node \(Self.nodeVersion), and pnpm \(Self.pnpmVersion). This check used /bin/zsh -i -c and did not use a login shell."
            clearMessage()
        } catch {
            shellConfigurationStatus = error.localizedDescription
            showError(error.localizedDescription)
        }
    }

    func restoreShell() throws {
        guard canRestoreShell else { return }
        isRestoringShell = true
        showProgress("Restoring the optional shell configuration…")
        defer { isRestoringShell = false }
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

#endif
