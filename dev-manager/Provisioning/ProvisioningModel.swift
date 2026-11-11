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
    @Published var isShowingCommandLineToolsConsent = false
    @Published var isShowingHomebrewConsent = false
    @Published var isShowingRuntimeConsent = false
    @Published var isShowingShellConfigurationConsent = false
    @Published var isShowingShellRestoreConsent = false

    @Published private(set) var hasCompletedCheck = false
    @Published private(set) var commandLineToolsRequestNeedsCheck = false
    @Published private(set) var homebrewHandoffNeedsCheck = false
    private var checkGeneration = 0
    private var fnmExecutableURL: URL?

    var supportedEnvironmentIssue: String? { Self.environmentIssue }
    var message: String? { messagePresentation?.text }

    private func showProgress(_ text: String) { messagePresentation = .progress(text) }
    private func showError(_ text: String) { messagePresentation = .error(text) }
    private func clearMessage() { messagePresentation = nil }

    var isSupportedEnvironment: Bool { supportedEnvironmentIssue == nil }

    enum NextAction: Equatable {
        case checkInstallation
        case installAppleDeveloperTools
        case installHomebrew
        case setupNodeAndPnpm
        case configureShellOptional
        case reviewDetails
        case done
        case checking
        case openingAppleInstaller
        case downloadingHomebrew
        case installingRuntime
        case working
        case unsupported

        var title: String {
            switch self {
            case .checkInstallation: return "Check installation"
            case .installAppleDeveloperTools: return "Install Apple developer tools"
            case .installHomebrew: return "Install Homebrew"
            case .setupNodeAndPnpm: return "Set up Node and pnpm"
            case .configureShellOptional: return "Configure shell — optional"
            case .reviewDetails: return "Review setup details"
            case .done: return "Done"
            case .checking: return "Checking…"
            case .openingAppleInstaller: return "Opening Apple installer…"
            case .downloadingHomebrew: return "Downloading Homebrew.pkg…"
            case .installingRuntime: return "Setting up Node and pnpm…"
            case .working: return "Working…"
            case .unsupported: return "Setup unavailable"
            }
        }
    }

    var nextAction: NextAction {
        if isChecking { return .checking }
        if isRequestingCommandLineTools { return .openingAppleInstaller }
        if isDownloadingHomebrew { return .downloadingHomebrew }
        if isInstallingRuntime { return .installingRuntime }
        if isConfiguringShell || isVerifyingShell || isRestoringShell { return .working }
        if !hasCompletedCheck || commandLineToolsRequestNeedsCheck || homebrewHandoffNeedsCheck {
            return .checkInstallation
        }
        guard isSupportedEnvironment else { return .unsupported }

        if developerToolsReady {
            // Continue below.
        } else if checks.first(where: { $0.id == .developerTools })?.state.isMissing == true,
                  canRequestCommandLineTools {
            return .installAppleDeveloperTools
        } else {
            return .reviewDetails
        }

        if homebrewState?.isReady == true {
            // Continue below.
        } else if homebrewMissing, canRequestHomebrew {
            return .installHomebrew
        } else {
            return .reviewDetails
        }

        if allRuntimeToolsReady {
            switch ProvisioningShellConfiguration.inspect() {
            case .notConfigured where canConfigureShell:
                return .configureShellOptional
            case .configured, .notConfigured, .conflict:
                return .done
            }
        }
        if canInstallRuntime { return .setupNodeAndPnpm }
        return .reviewDetails
    }

    var allRuntimeToolsReady: Bool {
        fnmState?.isReady == true && nodeState?.isReady == true && pnpmState?.isReady == true
    }

    var developerToolsReady: Bool {
        checks.first(where: { $0.id == .developerTools })?.state.isReady == true
    }

    var canRequestCommandLineTools: Bool {
        hasCompletedCheck && isSupportedEnvironment && !commandLineToolsRequestNeedsCheck &&
            !isChecking && !isRequestingCommandLineTools && !isDownloadingHomebrew &&
            !isInstallingRuntime && !isConfiguringShell && !isVerifyingShell && !isRestoringShell && !developerToolsReady
    }

    var canRequestHomebrew: Bool {
        hasCompletedCheck && isSupportedEnvironment && developerToolsReady &&
            !homebrewHandoffNeedsCheck && !isChecking && !isRequestingCommandLineTools &&
            !isDownloadingHomebrew && !isInstallingRuntime && !isConfiguringShell && !isVerifyingShell &&
            !isRestoringShell && homebrewMissing
    }

    var canInstallRuntime: Bool {
        guard hasCompletedCheck, isSupportedEnvironment, developerToolsReady, !isChecking,
              !isRequestingCommandLineTools, !isDownloadingHomebrew, !isInstallingRuntime,
              !isConfiguringShell, !isVerifyingShell, !isRestoringShell,
              homebrewState?.isReady == true else { return false }
        guard fnmState?.isReady == true || fnmState?.isMissing == true else { return false }
        guard nodeState?.isReady == true || nodeState?.isMissing == true || nodeState?.isUnverified == true else { return false }
        guard pnpmState?.isReady == true || pnpmState?.isMissing == true || pnpmState?.isUnverified == true else { return false }
        return fixtureURL == nil && fixtureCommand == nil
    }

    var canConfigureShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isChecking && !isRequestingCommandLineTools &&
            !isDownloadingHomebrew && !isInstallingRuntime && !isConfiguringShell && !isVerifyingShell &&
            !isRestoringShell && fnmState?.isReady == true && nodeState?.isReady == true && pnpmState?.isReady == true
    }

    var canVerifyShell: Bool {
        canConfigureShell && ProvisioningShellConfiguration.inspect().isConfigured
    }

    var canRestoreShell: Bool {
        hasCompletedCheck && isSupportedEnvironment && !isChecking && !isRequestingCommandLineTools &&
            !isDownloadingHomebrew && !isInstallingRuntime && !isConfiguringShell && !isVerifyingShell &&
            !isRestoringShell && ProvisioningShellConfiguration.hasRecordedConfiguration()
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
        guard generation == checkGeneration else { return }
        fnmExecutableURL = inspection.fnmExecutableURL
        checks = [inspection.developerTools, inspection.homebrew, inspection.fnm, inspection.node, inspection.pnpm]
        isChecking = false
        hasCompletedCheck = true
        commandLineToolsRequestNeedsCheck = false
        homebrewHandoffNeedsCheck = false
        shellConfigurationStatus = ProvisioningShellConfiguration.inspect().message
        if let supportedEnvironmentIssue {
            showError("Machine-changing setup is disabled: \(supportedEnvironmentIssue)")
        } else {
            clearMessage()
        }
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
            clearMessage()
        } catch {
            shellConfigurationStatus = error.localizedDescription
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
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("fresh interactive Zsh verification failed: \(result.failureDescription(for: "/bin/zsh -i -c"))")
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
            clearMessage()
        } catch {
            shellConfigurationStatus = error.localizedDescription
            showError(error.localizedDescription)
            throw error
        }
    }

    func requestCommandLineTools() {
        guard canRequestCommandLineTools else { return }
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
                let status = process.terminationStatus
                if status == 0 {
                    self.clearMessage()
                } else {
                    self.showError("Could not request Apple's Command Line Tools installer (status \(status)). Press Check again before retrying.")
                }
            }
        }

        do {
            try process.run()
        } catch {
            isRequestingCommandLineTools = false
            showError("Could not request Apple's Command Line Tools installer: \(error.localizedDescription)")
        }
    }

    func downloadAndOpenHomebrewPackage() async {
        guard canRequestHomebrew else { return }
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
            setHomebrewState(.waiting("Homebrew.pkg was opened in macOS Installer. Finish or cancel it, then press Check again; opening it is not success."))
            clearMessage()
        } catch {
            setHomebrewState(.attention("Homebrew handoff failed: \(error.localizedDescription)"))
            showError("Homebrew handoff failed: \(error.localizedDescription) Press Check again before retrying.")
        }
        isDownloadingHomebrew = false
    }

    func installRuntimeAndPrepareFixture() async {
        guard canInstallRuntime else { return }
        isInstallingRuntime = true
        installationOutput = ""
        defer { isInstallingRuntime = false }

        guard homebrewState?.isReady == true else {
            showError("Homebrew is not ready; runtime installation was not started.")
            return
        }

        var fnm = fnmExecutableURL
        if fnm == nil {
            showProgress("Installing fnm through /opt/homebrew/bin/brew…")
            let result = await ProvisioningRuntimeInstaller.installFNM()
            recordInstallationResult(result, label: "brew install fnm")
            guard result.succeeded else {
                showError("fnm installation failed. The fixture was not prepared; press Check again and retry after reviewing the output.")
                return
            }
            await checkAgain(allowDuringInstallation: true)
            guard fnmState?.isReady == true, let detectedFNM = fnmExecutableURL else {
                showError("fnm was not usable after Homebrew finished. The fixture was not prepared; review the fnm check and retry.")
                return
            }
            fnm = detectedFNM
        }

        guard fnmState?.isReady == true, let fnm else {
            showError("The existing fnm installation needs attention. It was not replaced or upgraded.")
            return
        }

        if nodeState?.isMissing == true {
            showProgress("Installing Node \(Self.nodeVersion) in fnm…")
            let result = await ProvisioningRuntimeInstaller.installNode(using: fnm)
            recordInstallationResult(result, label: "fnm install \(Self.nodeVersion)")
            guard result.succeeded else {
                showError("Node \(Self.nodeVersion) installation failed. Dependent steps were not started.")
                return
            }
            await checkAgain(allowDuringInstallation: true)
        }

        guard nodeState?.isReady == true else {
            showError("Node \(Self.nodeVersion) is not usable through fnm. The existing installation was left unchanged.")
            return
        }

        if pnpmState?.isMissing == true {
            showProgress("Installing pnpm \(Self.pnpmVersion) inside Node \(Self.nodeVersion)…")
            let result = await ProvisioningRuntimeInstaller.installPnpm(using: fnm)
            recordInstallationResult(result, label: "npm install --global pnpm@\(Self.pnpmVersion)")
            guard result.succeeded else {
                showError("pnpm \(Self.pnpmVersion) installation failed. The fixture was not prepared.")
                return
            }
            await checkAgain(allowDuringInstallation: true)
        }

        guard nodeState?.isReady == true, pnpmState?.isReady == true else {
            showError("The pinned runtime is not fully usable. Existing conflicting or unusable tools were left unchanged; the fixture was not prepared.")
            return
        }

        do {
            let fixture = try ProvisioningFixture.materialize(using: fnm)
            fixtureURL = fixture.folder
            fixtureCommand = fixture.command
            clearMessage()
        } catch {
            showError("Fixture preparation failed without changing conflicting files: \(error.localizedDescription)")
        }
    }

    private func recordInstallationResult(_ result: ProvisioningInstallProcessResult, label: String) {
        var text = "\(label) exited with status \(result.terminationStatus)."
        if result.timedOut { text = "\(label) timed out after \(Int(ProvisioningConfiguration.installTimeout / 60)) minutes." }
        if !result.stdout.isEmpty { text += "\nstdout:\n\(result.stdout)" }
        if !result.stderr.isEmpty { text += "\nstderr:\n\(result.stderr)" }
        installationOutput = String((installationOutput + "\n" + text).suffix(16_000))
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
