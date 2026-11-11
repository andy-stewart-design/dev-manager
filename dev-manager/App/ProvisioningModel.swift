#if DEBUG
import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class ProvisioningModel: ObservableObject {
    static let nodeVersion = "24.22.2"
    static let pnpmVersion = "12.18.0"

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

    var supportedEnvironmentIssue: String? {
        Self.environmentIssue
    }

    var message: String? {
        messagePresentation?.text
    }

    private func showProgress(_ text: String) {
        messagePresentation = .progress(text)
    }

    private func showError(_ text: String) {
        messagePresentation = .error(text)
    }

    private func clearMessage() {
        messagePresentation = nil
    }

    var isSupportedEnvironment: Bool {
        supportedEnvironmentIssue == nil
    }

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

    private var homebrewMissing: Bool {
        homebrewState?.isMissing == true
    }

    private var homebrewState: ProvisioningCheck.State? {
        checks.first(where: { $0.id == .homebrew })?.state
    }

    private var fnmState: ProvisioningCheck.State? {
        checks.first(where: { $0.id == .fnm })?.state
    }

    private var nodeState: ProvisioningCheck.State? {
        checks.first(where: { $0.id == .node })?.state
    }

    private var pnpmState: ProvisioningCheck.State? {
        checks.first(where: { $0.id == .pnpm })?.state
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
        checks = ProvisioningCheck.all.map { ProvisioningCheck(id: $0.id, state: .checking) }

        let developerTools = await checkDeveloperTools()
        let homebrew = await checkHomebrew()
        let fnm = await checkFNM()
        let runtime = await checkRuntime(using: fnm.executableURL)

        guard generation == checkGeneration else { return }
        fnmExecutableURL = fnm.executableURL
        checks = [developerTools.check, homebrew.check, fnm.check, runtime.node, runtime.pnpm]
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
            printf 'fnm=%s\\n' \"$(command -v fnm)\"
            printf 'fnm_version=%s\\n' \"$(fnm --version)\"
            printf 'node=%s\\n' \"$(command -v node)\"
            printf 'node_version=%s\\n' \"$(node --version)\"
            printf 'pnpm=%s\\n' \"$(command -v pnpm)\"
            printf 'pnpm_version=%s\\n' \"$(pnpm --version)\"
            """
            let result = await run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-i", "-c", script], environment: environment)
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\nstderr:\n")
            shellVerificationOutput = String(output.suffix(8_000))
            guard result.succeeded else {
                throw ProvisioningShellConfiguration.ConfigurationError.conflict("fresh interactive Zsh verification failed: \(commandFailure("/bin/zsh -i -c", result: result))")
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

    private func checkDeveloperTools() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let selector = await run(URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"])
        guard selector.succeeded, let selectedPath = selector.stdout.firstNonEmptyLine else {
            if selector.timedOut {
                return (ProvisioningCheck(id: .developerTools, state: .attention(commandFailure("xcode-select", result: selector))), nil)
            }
            return (ProvisioningCheck(id: .developerTools, state: .missing("No usable developer tools are selected. Request Apple's graphical installer, then Check again.")), nil)
        }

        let clang = await run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "clang"])
        guard clang.succeeded, let clangPath = clang.stdout.firstNonEmptyLine else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("Selected tools at \(selectedPath) are not usable: \(commandFailure("xcrun --find clang", result: clang))")), nil)
        }

        let sdk = await run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--sdk", "macosx", "--show-sdk-path"])
        guard sdk.succeeded else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("clang is at \(clangPath), but the macOS SDK check failed: \(commandFailure("xcrun --show-sdk-path", result: sdk))")), nil)
        }

        return (ProvisioningCheck(id: .developerTools, state: .ready("Selected: \(selectedPath); clang: \(clangPath)")), URL(fileURLWithPath: clangPath))
    }

    private func checkHomebrew() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        guard FileManager.default.isExecutableFile(atPath: brew.path) else {
            return (ProvisioningCheck(id: .homebrew, state: .missing("Homebrew was not found at /opt/homebrew/bin/brew.")), nil)
        }

        let result = await run(brew, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .homebrew, state: .attention("Found \(brew.path), but it did not run as the current user: \(commandFailure("brew --version", result: result))")), brew)
        }
        return (ProvisioningCheck(id: .homebrew, state: .ready("\(result.stdout.firstNonEmptyLine ?? brew.path); \(brew.path) ran as the current user")), brew)
    }

    func downloadAndOpenHomebrewPackage() async {
        guard canRequestHomebrew else { return }
        isDownloadingHomebrew = true
        homebrewHandoffNeedsCheck = true
        setHomebrewState(.waiting("Preparing the official Homebrew.pkg; installation is not complete."))
        showProgress("Looking up the latest official Homebrew.pkg…")

        do {
            let packageURL = try await downloadHomebrewPackage()
            guard NSWorkspace.shared.open(packageURL) else {
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

    private func downloadHomebrewPackage() async throws -> URL {
        guard let apiURL = URL(string: Self.homebrewReleaseAPIURL) else {
            throw HomebrewProvisioningError.invalidReleaseAPI
        }

        var apiRequest = URLRequest(url: apiURL)
        apiRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        apiRequest.setValue("DevManager/0.1 provisioning-spike", forHTTPHeaderField: "User-Agent")
        apiRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let session = Self.homebrewURLSession()
        let (data, response) = try await session.data(for: apiRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw HomebrewProvisioningError.releaseAPI(status: status)
        }

        let release = try JSONDecoder().decode(HomebrewRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == Self.homebrewPackageName }) else {
            throw HomebrewProvisioningError.assetNotFound
        }
        guard let downloadURL = URL(string: asset.browserDownloadURL),
              Self.isOfficialHomebrewDownloadURL(downloadURL) else {
            throw HomebrewProvisioningError.invalidDownloadURL
        }

        showProgress("Downloading Homebrew.pkg from Homebrew's official release…")
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("DevManager/0.1 provisioning-spike", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, downloadResponse) = try await session.download(for: downloadRequest)
        guard let downloadHTTPResponse = downloadResponse as? HTTPURLResponse,
              (200..<300).contains(downloadHTTPResponse.statusCode) else {
            let status = (downloadResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw HomebrewProvisioningError.packageDownload(status: status)
        }
        guard downloadHTTPResponse.url?.scheme?.lowercased() == "https" else {
            throw HomebrewProvisioningError.insecurePackageDownload
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevManager-Homebrew-\(UUID().uuidString).pkg")
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        guard let byteCount = attributes[.size] as? NSNumber, byteCount.int64Value > 0 else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw HomebrewProvisioningError.emptyPackage
        }
        return destinationURL
    }

    private func setHomebrewState(_ state: ProvisioningCheck.State) {
        guard checks.contains(where: { $0.id == .homebrew }) else { return }
        checks = checks.map {
            $0.id == .homebrew ? ProvisioningCheck(id: .homebrew, state: state) : $0
        }
    }

    private func setDeveloperToolsState(_ state: ProvisioningCheck.State) {
        guard checks.contains(where: { $0.id == .developerTools }) else { return }
        checks = checks.map {
            $0.id == .developerTools ? ProvisioningCheck(id: .developerTools, state: state) : $0
        }
    }

    private func checkFNM() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidates = [
            home.appendingPathComponent(".local/share/fnm/fnm"),
            home.appendingPathComponent(".fnm/fnm"),
            home.appendingPathComponent(".local/bin/fnm"),
            URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            URL(fileURLWithPath: "/usr/local/bin/fnm")
        ]
        guard let fnm = firstExecutable(candidates: candidates) else {
            return (ProvisioningCheck(id: .fnm, state: .missing("fnm was not found in its standard locations; no shell files were sourced.")), nil)
        }

        let result = await run(fnm, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .fnm, state: .attention("Found \(fnm.path), but it did not run as the current user: \(commandFailure("fnm --version", result: result))")), fnm)
        }
        return (ProvisioningCheck(id: .fnm, state: .ready("\(result.stdout.firstNonEmptyLine ?? "fnm") at \(fnm.path)")), fnm)
    }

    private func checkRuntime(using fnmURL: URL?) async -> (node: ProvisioningCheck, pnpm: ProvisioningCheck) {
        guard let fnmURL else {
            return (
                ProvisioningCheck(id: .node, state: .unverified("Waiting to verify Node \(Self.nodeVersion); fnm is unavailable.")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(Self.nodeVersion) context; fnm is unavailable."))
            )
        }

        // Inspect fnm's local inventory first. `fnm exec --using` is a
        // standalone execution check and fails when the requested version is
        // absent; it does not install the version.
        let inspection = await run(fnmURL, arguments: ["list"], environment: Self.readOnlyRuntimeEnvironment)
        guard inspection.succeeded else {
            let failure = commandFailure("fnm list", result: inspection)
            return (
                ProvisioningCheck(id: .node, state: .attention("Could not inspect the installed Node \(Self.nodeVersion): \(failure)")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(Self.nodeVersion) context; fnm inventory failed: \(failure)"))
            )
        }
        guard inspection.stdout.containsToken("v\(Self.nodeVersion)") else {
            return (
                ProvisioningCheck(id: .node, state: .missing("Node \(Self.nodeVersion) is not installed in fnm. No runtime was invoked or installed.")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(Self.nodeVersion) context; the pinned Node runtime is unavailable."))
            )
        }

        let node = await run(fnmURL, arguments: ["exec", "--using", Self.nodeVersion, "node", "--version"], environment: Self.readOnlyRuntimeEnvironment)
        guard node.succeeded else {
            let failure = commandFailure("fnm exec node", result: node)
            return (
                ProvisioningCheck(id: .node, state: .attention("The installed Node \(Self.nodeVersion) could not run through fnm: \(failure)")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(Self.nodeVersion) context; the pinned Node runtime could not run."))
            )
        }
        guard node.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "v\(Self.nodeVersion)" else {
            let output = node.stdout.firstNonEmptyLine ?? "no version output"
            return (
                ProvisioningCheck(id: .node, state: .attention("fnm returned an unusable Node version for \(Self.nodeVersion): \(output).")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(Self.nodeVersion) context; Node did not report the pinned version."))
            )
        }

        // Resolve pnpm's executable without running it. This makes a missing
        // pnpm distinguishable from a present Corepack shim that cannot run.
        let pnpmPath = await run(fnmURL, arguments: ["exec", "--using", Self.nodeVersion, "/usr/bin/which", "pnpm"], environment: Self.readOnlyRuntimeEnvironment)
        guard pnpmPath.succeeded else {
            if pnpmPath.timedOut {
                return (
                    ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
                    ProvisioningCheck(id: .pnpm, state: .attention("Could not inspect pnpm in the required Node \(Self.nodeVersion) context: \(commandFailure("which pnpm", result: pnpmPath))"))
                )
            }
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .missing("pnpm \(Self.pnpmVersion) is not installed in the Node \(Self.nodeVersion) context. No Corepack download was attempted."))
            )
        }
        guard let resolvedPnpm = pnpmPath.stdout.firstNonEmptyLine else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("fnm resolved pnpm in the Node \(Self.nodeVersion) context without a usable executable path."))
            )
        }

        let pnpm = await run(fnmURL, arguments: ["exec", "--using", Self.nodeVersion, "pnpm", "--version"], environment: Self.readOnlyRuntimeEnvironment)
        guard pnpm.succeeded else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm at \(resolvedPnpm) in the Node \(Self.nodeVersion) context, but it could not report its version: \(commandFailure("fnm exec pnpm", result: pnpm))"))
            )
        }
        guard pnpm.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == Self.pnpmVersion else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm at \(resolvedPnpm) in the Node \(Self.nodeVersion) context, but it reported \(pnpm.stdout.firstNonEmptyLine ?? "no version output") instead of \(Self.pnpmVersion)."))
            )
        }

        return (
            ProvisioningCheck(id: .node, state: .ready("Node \(Self.nodeVersion) through fnm")),
            ProvisioningCheck(id: .pnpm, state: .ready("pnpm \(Self.pnpmVersion) through fnm's Node \(Self.nodeVersion) context"))
        )
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
            let result = await runInstallProcess(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                arguments: ["install", "fnm"],
                environment: Self.installEnvironment,
                label: "brew install fnm"
            )
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
            let result = await runInstallProcess(
                executableURL: fnm,
                arguments: ["install", Self.nodeVersion],
                environment: Self.runtimeInstallEnvironment,
                label: "fnm install \(Self.nodeVersion)"
            )
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
            let result = await runInstallProcess(
                executableURL: fnm,
                arguments: ["exec", "--using", Self.nodeVersion, "npm", "install", "--global", "pnpm@\(Self.pnpmVersion)"],
                environment: Self.runtimeInstallEnvironment,
                label: "npm install --global pnpm@\(Self.pnpmVersion)"
            )
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
            let fixture = try materializeFixture(using: fnm)
            fixtureURL = fixture.folder
            fixtureCommand = fixture.command
            clearMessage()
        } catch {
            showError("Fixture preparation failed without changing conflicting files: \(error.localizedDescription)")
        }
    }

    private func recordInstallationResult(_ result: InstallProcessResult, label: String) {
        var text = "\(label) exited with status \(result.terminationStatus)."
        if result.timedOut { text = "\(label) timed out after \(Int(Self.installTimeout / 60)) minutes." }
        if !result.stdout.isEmpty { text += "\nstdout:\n\(result.stdout)" }
        if !result.stderr.isEmpty { text += "\nstderr:\n\(result.stderr)" }
        installationOutput = String((installationOutput + "\n" + text).suffix(16_000))
    }

    private func materializeFixture(using fnm: URL) throws -> (folder: URL, command: String) {
        let fileManager = FileManager.default
        let folder = Self.fixtureFolderURL
        let container = folder.deletingLastPathComponent()
        let applicationSupport = container.deletingLastPathComponent()

        // Inspect every owned path before creating a directory or file. In
        // particular, lstat prevents an existing symlink from being followed.
        guard try fixturePathKind(at: applicationSupport) == .directory else {
            throw FixtureProvisioningError.conflictingPath(applicationSupport.path)
        }
        let containerKind = try fixturePathKind(at: container)
        guard containerKind == .missing || containerKind == .directory else {
            throw FixtureProvisioningError.conflictingPath(container.path)
        }
        let folderKind = try fixturePathKind(at: folder)
        switch folderKind {
        case .directory:
            try validateExistingFixture(at: folder)
            return (folder, "FNM_COREPACK_ENABLED=false \(shellQuote(fnm.path)) exec --using \(Self.nodeVersion) pnpm dev")
        case .missing:
            break
        case .symlink, .regular, .other:
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }

        if containerKind == .missing {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: false)
        }
        guard try fixturePathKind(at: container) == .directory,
              try fixturePathKind(at: folder) == .missing else {
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }

        let stage = container.appendingPathComponent(".Provisioning Fixture.\(UUID().uuidString).tmp", isDirectory: true)
        guard try fixturePathKind(at: stage) == .missing else {
            throw FixtureProvisioningError.conflictingPath(stage.path)
        }
        var stageExists = false
        defer {
            if stageExists { try? fileManager.removeItem(at: stage) }
        }

        try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
        stageExists = true
        for (name, contents) in Self.fixtureFiles {
            let file = stage.appendingPathComponent(name)
            guard try fixturePathKind(at: file) == .missing else {
                throw FixtureProvisioningError.conflictingPath(file.path)
            }
            try writeNewFixtureFile(contents, at: file)
        }

        // Recheck the target immediately before the atomic directory move. The
        // staged directory is app-owned and is the only path written so far.
        guard try fixturePathKind(at: folder) == .missing else {
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }
        try fileManager.moveItem(at: stage, to: folder)
        stageExists = false
        return (folder, "FNM_COREPACK_ENABLED=false \(shellQuote(fnm.path)) exec --using \(Self.nodeVersion) pnpm dev")
    }

    private func validateExistingFixture(at folder: URL) throws {
        let fileManager = FileManager.default
        let expected = Set(Self.fixtureFiles.map { $0.name })
        let actual = Set(try fileManager.contentsOfDirectory(atPath: folder.path))
        guard actual == expected else {
            throw FixtureProvisioningError.unexpectedContents(folder.path)
        }
        for (name, contents) in Self.fixtureFiles {
            let file = folder.appendingPathComponent(name)
            guard try fixturePathKind(at: file) == .regular else {
                throw FixtureProvisioningError.conflictingPath(file.path)
            }
            let existing = try String(contentsOf: file, encoding: .utf8)
            guard existing == contents else {
                throw FixtureProvisioningError.unexpectedContents(file.path)
            }
        }
    }

    private func fixturePathKind(at url: URL) throws -> FixturePathKind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw FixtureProvisioningError.pathInspectionFailed(url.path, String(cString: strerror(errno)))
            }
            return .missing
        }
        let type = info.st_mode & S_IFMT
        if type == S_IFLNK { return .symlink }
        if type == S_IFDIR { return .directory }
        if type == S_IFREG { return .regular }
        return .other
    }

    private func writeNewFixtureFile(_ contents: String, at url: URL) throws {
        guard let data = contents.data(using: .utf8) else {
            throw FixtureProvisioningError.writeFailed(url.path, "fixture contents are not UTF-8")
        }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw FixtureProvisioningError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            return write(descriptor, baseAddress, bytes.count)
        }
        guard written == data.count else {
            throw FixtureProvisioningError.writeFailed(url.path, String(cString: strerror(errno)))
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runInstallProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        label: String
    ) async -> InstallProcessResult {
        let timeout = Self.installTimeout
        return await Task.detached(priority: .userInitiated) {
            let collector = InstallOutputCollector()
            let spawned: InstallSpawn
            do {
                spawned = try Self.spawnInstallProcess(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                )
            } catch {
                return InstallProcessResult(
                    succeeded: false,
                    stdout: "",
                    stderr: "\(label): \(error.localizedDescription)",
                    terminationStatus: -1,
                    timedOut: false
                )
            }

            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                Self.drain(spawned.stdout, into: collector, stream: "stdout")
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                Self.drain(spawned.stderr, into: collector, stream: "stderr")
                group.leave()
            }

            var timedOut = !Self.waitForInstallExit(spawned.processID, timeout: timeout)
            if timedOut {
                collector.append("\nTimed out; terminating the installer process group.\n", stream: "stderr")
            }
            let groupWasClean = Self.stopInstallGroup(
                spawned.processID,
                timeout: timedOut ? 5.0 : 2.0
            )
            let status = Self.reapInstallProcess(spawned.processID, timeout: 2.0)
            if status == nil { timedOut = true }

            // A descendant can retain a pipe after the leader exits. Never wait
            // indefinitely for such a descriptor; close our owned read ends and
            // give the drainers one final bounded opportunity to finish.
            if group.wait(timeout: .now() + 2.0) == .timedOut {
                spawned.stdout.closeFile()
                spawned.stderr.closeFile()
                _ = group.wait(timeout: .now() + 1.0)
            } else {
                spawned.stdout.closeFile()
                spawned.stderr.closeFile()
            }

            let terminationStatus = status.map(Self.installExitCode) ?? -1
            return InstallProcessResult(
                succeeded: !timedOut && groupWasClean && terminationStatus == 0,
                stdout: collector.stdout,
                stderr: collector.stderr,
                terminationStatus: terminationStatus,
                timedOut: timedOut
            )
        }.value
    }

    nonisolated private static func spawnInstallProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> InstallSpawn {
        let stdoutPipe = try makeInstallPipe()
        let stderrPipe: (read: Int32, write: Int32)
        do {
            stderrPipe = try makeInstallPipe()
        } catch {
            close(stdoutPipe.read)
            close(stdoutPipe.write)
            throw error
        }

        let stdinFD = open("/dev/null", O_RDONLY)
        guard stdinFD >= 0 else {
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw InstallProcessError.spawnFailed("/dev/null: \(String(cString: strerror(errno)))")
        }
        let normalizedStdin: Int32
        do {
            normalizedStdin = try normalizeInstallDescriptor(stdinFD)
        } catch {
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw error
        }

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw InstallProcessError.spawnFailed("could not initialize file actions")
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
            throw InstallProcessError.spawnFailed("could not initialize process-group attributes")
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        func closeParentDescriptors() {
            close(normalizedStdin)
            close(stdoutPipe.read); close(stdoutPipe.write)
            close(stderrPipe.read); close(stderrPipe.write)
        }

        let flags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP)
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, normalizedStdin, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stdoutPipe.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderrPipe.write, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, normalizedStdin) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stdoutPipe.write) == 0,
              posix_spawn_file_actions_addclose(&actions, stderrPipe.read) == 0,
              posix_spawn_file_actions_addclose(&actions, stderrPipe.write) == 0 else {
            closeParentDescriptors()
            throw InstallProcessError.spawnFailed("could not configure the installer process group or output streams")
        }

        let commandArguments = [executableURL.path] + arguments
        var argv = commandArguments.map { strdup($0) }
        argv.append(nil)
        defer { argv.compactMap { $0 }.forEach { free($0) } }
        var envp = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.compactMap { $0 }.forEach { free($0) } }

        var processID: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvBuffer in
            envp.withUnsafeMutableBufferPointer { envBuffer in
                posix_spawn(
                    &processID,
                    executableURL.path,
                    &actions,
                    &attributes,
                    argvBuffer.baseAddress,
                    envBuffer.baseAddress
                )
            }
        }
        close(normalizedStdin)
        close(stdoutPipe.write)
        close(stderrPipe.write)
        guard result == 0 else {
            close(stdoutPipe.read)
            close(stderrPipe.read)
            throw InstallProcessError.spawnFailed(String(cString: strerror(result)))
        }

        return InstallSpawn(
            processID: processID,
            stdout: FileHandle(fileDescriptor: stdoutPipe.read, closeOnDealloc: true),
            stderr: FileHandle(fileDescriptor: stderrPipe.read, closeOnDealloc: true)
        )
    }

    nonisolated private static func makeInstallPipe() throws -> (read: Int32, write: Int32) {
        var fds = [Int32](repeating: -1, count: 2)
        guard pipe(&fds) == 0 else {
            throw InstallProcessError.pipeFailed(String(cString: strerror(errno)))
        }
        do {
            fds[0] = try normalizeInstallDescriptor(fds[0])
            fds[1] = try normalizeInstallDescriptor(fds[1])
            return (fds[0], fds[1])
        } catch {
            if fds[0] >= 0 { close(fds[0]) }
            if fds[1] >= 0 { close(fds[1]) }
            throw error
        }
    }

    nonisolated private static func normalizeInstallDescriptor(_ descriptor: Int32) throws -> Int32 {
        guard descriptor < 3 else { return descriptor }
        let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        guard replacement >= 0 else {
            throw InstallProcessError.pipeFailed("could not protect file descriptor: \(String(cString: strerror(errno)))")
        }
        close(descriptor)
        return replacement
    }

    nonisolated private static func waitForInstallExit(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var info = siginfo_t()
            let result = waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0, info.si_pid != 0 { return true }
            if result < 0, errno != EINTR { return false }
            usleep(100_000)
        }
        return false
    }

    nonisolated private static func stopInstallGroup(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let hasMembers = { dm_group_has_non_zombie_members(processID, processID) != 0 }
        guard hasMembers() else { return true }
        _ = kill(-processID, SIGTERM)
        let termDeadline = Date().addingTimeInterval(timeout)
        while hasMembers() && Date() < termDeadline { usleep(50_000) }
        if hasMembers() {
            _ = kill(-processID, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1.0)
            while hasMembers() && Date() < killDeadline { usleep(50_000) }
        }
        return !hasMembers()
    }

    nonisolated private static func reapInstallProcess(_ processID: Int32, timeout: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while Date() < deadline {
            let result = waitpid(processID, &status, WNOHANG)
            if result == processID { return status }
            if result < 0, errno != EINTR { return nil }
            usleep(50_000)
        }
        return nil
    }

    nonisolated private static func installExitCode(_ status: Int32) -> Int32 {
        (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
    }

    nonisolated private static func drain(_ handle: FileHandle, into collector: InstallOutputCollector, stream: String) {
        while true {
            guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { break }
            collector.append(String(decoding: data, as: UTF8.self), stream: stream)
        }
    }

    private func firstExecutable(candidates: [String]) -> URL? {
        firstExecutable(candidates: candidates.map(URL.init(fileURLWithPath:)))
    }

    private func firstExecutable(candidates: [URL]) -> URL? {
        candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func commandFailure(_ command: String, result: CommandResult) -> String {
        if result.timedOut {
            return "\(command) timed out after \(Int(Self.commandTimeout)) seconds"
        }
        let detail = (result.stderr.firstNonEmptyLine ?? result.stdout.firstNonEmptyLine ?? "exit status \(result.terminationStatus)")
        return "\(command) failed: \(detail)"
    }

    private static let commandTimeout: TimeInterval = 8
    private static let installTimeout: TimeInterval = 15 * 60
    private static let homebrewReleaseAPIURL = "https://api.github.com/repos/Homebrew/brew/releases/latest"
    private static let homebrewPackageName = "Homebrew.pkg"
    private static let officialHomebrewReleasePrefix = "https://github.com/Homebrew/brew/releases/download/"

    private static func homebrewURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration)
    }

    private static func isOfficialHomebrewDownloadURL(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix(officialHomebrewReleasePrefix) &&
            url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == "github.com" &&
            url.pathComponents.last == homebrewPackageName
    }

    private static var guiSafePATH: String {
        let inherited = ProcessInfo.processInfo.environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return inherited?.isEmpty == false ? inherited! : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static var readOnlyRuntimeEnvironment: [String: String] {
        [
            "PATH": guiSafePATH,
            "FNM_COREPACK_ENABLED": "false",
            "FNM_RESOLVE_ENGINES": "false",
            "COREPACK_ENABLE_NETWORK": "0",
            "COREPACK_DEFAULT_TO_LATEST": "0",
            "COREPACK_ENABLE_PROJECT_SPEC": "0"
        ]
    }

    private static var installEnvironment: [String: String] {
        [
            "PATH": guiSafePATH,
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "NONINTERACTIVE": "1"
        ]
    }

    private static var runtimeInstallEnvironment: [String: String] {
        installEnvironment.merging([
            "FNM_COREPACK_ENABLED": "false",
            "COREPACK_ENABLE_NETWORK": "0",
            "COREPACK_DEFAULT_TO_LATEST": "0",
            "COREPACK_ENABLE_PROJECT_SPEC": "0",
            "npm_config_yes": "true",
            "npm_config_audit": "false",
            "npm_config_fund": "false"
        ]) { _, new in new }
    }

    private static var fixtureFolderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dev Manager", isDirectory: true)
            .appendingPathComponent("Provisioning Fixture", isDirectory: true)
    }

    private static let fixturePackageJSON = """
    {
      \"name\": \"dev-manager-provisioning-fixture\",
      \"private\": true,
      \"version\": \"1.0.0\",
      \"packageManager\": \"pnpm@12.18.0\",
      \"engines\": { \"node\": \"24.22.2\" },
      \"scripts\": { \"dev\": \"node server.js\" }
    }
    """

    private static let fixtureServerJS = """
    const http = require("node:http");

    const server = http.createServer((_request, response) => {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end("<h1>Dev Manager provisioning fixture</h1>");
    });

    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : "unknown";
      console.log(`Dev Manager fixture: http://127.0.0.1:${port}/`);
    });
    """

    private static let fixtureMarker = "dev-manager-provisioning-fixture-v1\n"

    private static var fixtureFiles: [(name: String, contents: String)] {
        [
            (".dev-manager-fixture", fixtureMarker),
            ("package.json", fixturePackageJSON),
            ("server.js", fixtureServerJS),
            (".node-version", "\(nodeVersion)\n")
        ]
    }

    private static var environmentIssue: String? {
        var issues: [String] = []
        if !isAppleSilicon {
            issues.append("this is not an Apple Silicon process")
        }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15 {
            issues.append("macOS 15 or later is required")
        }
        if !isLoggedInAdministrator {
            issues.append("the logged-in user is not an administrator")
        }
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

    private func run(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            let completion = CommandCompletion()

            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = error
            process.terminationHandler = { process in
                guard completion.claim() else { return }
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(
                    succeeded: process.terminationReason == .exit && process.terminationStatus == 0,
                    stdout: stdout,
                    stderr: stderr,
                    terminationStatus: process.terminationStatus,
                    timedOut: false
                ))
            }

            let timeoutWork = DispatchWorkItem {
                guard completion.claim() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(returning: CommandResult(
                    succeeded: false,
                    stdout: "",
                    stderr: "",
                    terminationStatus: -1,
                    timedOut: true
                ))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.commandTimeout, execute: timeoutWork)

            do {
                try process.run()
            } catch {
                guard completion.claim() else { return }
                continuation.resume(returning: CommandResult(
                    succeeded: false,
                    stdout: "",
                    stderr: error.localizedDescription,
                    terminationStatus: -1,
                    timedOut: false
                ))
            }
        }
    }
}

struct ProvisioningCheck: Identifiable, Equatable {
    enum ID: String, CaseIterable, Identifiable {
        case developerTools
        case homebrew
        case fnm
        case node
        case pnpm

        var id: String { rawValue }

        var title: String {
            switch self {
            case .developerTools: return "Apple developer tools"
            case .homebrew: return "Homebrew"
            case .fnm: return "Fast Node Manager (fnm)"
            case .node: return "Node 24.22.2"
            case .pnpm: return "pnpm 12.18.0"
            }
        }
    }

    enum State: Equatable {
        case checking
        case waiting(String)
        case unverified(String)
        case ready(String)
        case missing(String)
        case attention(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }

        var isUnverified: Bool {
            if case .unverified = self { return true }
            return false
        }
    }

    let id: ID
    let state: State

    static var all: [ProvisioningCheck] {
        ID.allCases.map { ProvisioningCheck(id: $0, state: .checking) }
    }
}

private struct InstallProcessResult: Sendable {
    let succeeded: Bool
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let timedOut: Bool
}

private struct InstallSpawn: Sendable {
    let processID: Int32
    let stdout: FileHandle
    let stderr: FileHandle
}

private enum InstallProcessError: LocalizedError {
    case pipeFailed(String)
    case spawnFailed(String)

    var errorDescription: String? {
        switch self {
        case let .pipeFailed(detail): return "Could not create installer output pipes: \(detail)"
        case let .spawnFailed(detail): return "Could not launch the installer: \(detail)"
        }
    }
}

private final class InstallOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutStorage = ""
    private var stderrStorage = ""

    var stdout: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutStorage
    }

    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrStorage
    }

    func append(_ text: String, stream: String) {
        lock.lock()
        defer { lock.unlock() }
        if stream == "stdout" {
            stdoutStorage.append(text)
        } else {
            stderrStorage.append(text)
        }
        if stdoutStorage.count > 12_000 { stdoutStorage = String(stdoutStorage.suffix(12_000)) }
        if stderrStorage.count > 12_000 { stderrStorage = String(stderrStorage.suffix(12_000)) }
    }
}

private enum FixturePathKind: Equatable {
    case missing
    case directory
    case regular
    case symlink
    case other
}

private enum FixtureProvisioningError: LocalizedError {
    case conflictingPath(String)
    case unexpectedContents(String)
    case pathInspectionFailed(String, String)
    case writeFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .conflictingPath(path):
            return "The fixture path conflicts with an existing non-owned path and was left unchanged: \(path)"
        case let .unexpectedContents(path):
            return "An existing fixture path has unexpected contents and was left unchanged: \(path)"
        case let .pathInspectionFailed(path, detail):
            return "The fixture path could not be safely inspected and was left unchanged: \(path): \(detail)"
        case let .writeFailed(path, detail):
            return "The fixture file could not be created: \(path): \(detail)"
        }
    }
}

nonisolated private final class CommandCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}

private struct HomebrewRelease: Decodable {
    let assets: [HomebrewReleaseAsset]
}

private struct HomebrewReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum HomebrewProvisioningError: LocalizedError {
    case invalidReleaseAPI
    case releaseAPI(status: Int)
    case assetNotFound
    case invalidDownloadURL
    case packageDownload(status: Int)
    case insecurePackageDownload
    case emptyPackage
    case couldNotOpenInstaller

    var errorDescription: String? {
        switch self {
        case .invalidReleaseAPI:
            return "The official Homebrew release API URL was invalid."
        case let .releaseAPI(status):
            return "The official Homebrew release API returned HTTP status \(status)."
        case .assetNotFound:
            return "The latest official Homebrew release did not contain the exact Homebrew.pkg asset."
        case .invalidDownloadURL:
            return "The release asset did not provide a valid official HTTPS Homebrew download URL."
        case let .packageDownload(status):
            return "The official Homebrew package download returned HTTP status \(status)."
        case .insecurePackageDownload:
            return "The final Homebrew package response was not HTTPS."
        case .emptyPackage:
            return "The downloaded Homebrew.pkg was empty."
        case .couldNotOpenInstaller:
            return "macOS could not open Homebrew.pkg through Launch Services."
        }
    }
}

private struct CommandResult {
    let succeeded: Bool
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let timedOut: Bool
}

private extension String {
    var firstNonEmptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func containsToken(_ expected: String) -> Bool {
        components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            .contains(expected)
    }
}
#endif
