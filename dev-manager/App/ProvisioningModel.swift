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
    @Published private(set) var message: String?
    @Published var isShowingCommandLineToolsConsent = false
    @Published var isShowingHomebrewConsent = false

    private(set) var hasCompletedCheck = false
    private var commandLineToolsRequestNeedsCheck = false
    private var homebrewHandoffNeedsCheck = false
    private var checkGeneration = 0

    var supportedEnvironmentIssue: String? {
        Self.environmentIssue
    }

    var isSupportedEnvironment: Bool {
        supportedEnvironmentIssue == nil
    }

    var developerToolsReady: Bool {
        checks.first(where: { $0.id == .developerTools })?.state.isReady == true
    }

    var canRequestCommandLineTools: Bool {
        hasCompletedCheck && isSupportedEnvironment && !commandLineToolsRequestNeedsCheck &&
            !isChecking && !isRequestingCommandLineTools && !isDownloadingHomebrew && !developerToolsReady
    }

    var canRequestHomebrew: Bool {
        hasCompletedCheck && isSupportedEnvironment && developerToolsReady &&
            !homebrewHandoffNeedsCheck && !isChecking && !isRequestingCommandLineTools &&
            !isDownloadingHomebrew && homebrewMissing
    }

    private var homebrewMissing: Bool {
        checks.first(where: { $0.id == .homebrew })?.state.isMissing == true
    }

    func checkAgain() async {
        guard !isChecking && !isRequestingCommandLineTools && !isDownloadingHomebrew else { return }
        checkGeneration += 1
        let generation = checkGeneration
        hasCompletedCheck = false
        isChecking = true
        message = "Inspecting installed tools…"
        checks = ProvisioningCheck.all.map { ProvisioningCheck(id: $0.id, state: .checking) }

        let developerTools = await checkDeveloperTools()
        let homebrew = await checkHomebrew()
        let fnm = await checkFNM()
        let runtime = await checkRuntime(using: fnm.executableURL)

        guard generation == checkGeneration else { return }
        checks = [developerTools.check, homebrew.check, fnm.check, runtime.node, runtime.pnpm]
        isChecking = false
        hasCompletedCheck = true
        commandLineToolsRequestNeedsCheck = false
        homebrewHandoffNeedsCheck = !homebrew.check.state.isMissing
        if let supportedEnvironmentIssue {
            message = "Inspection complete. Machine-changing actions are disabled: \(supportedEnvironmentIssue)"
        } else {
            message = "Inspection complete. Installation requests are never treated as completion; press Check again after Apple's UI finishes."
        }
    }

    func requestCommandLineTools() {
        guard canRequestCommandLineTools else { return }
        isRequestingCommandLineTools = true
        commandLineToolsRequestNeedsCheck = true
        message = "Requesting Apple's Command Line Tools installer dialog…"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRequestingCommandLineTools = false
                let status = process.terminationStatus
                self.message = "Apple's installer request returned (status \(status)). No installation was inferred; complete or cancel Apple's dialog, then press Check again before retrying."
            }
        }

        do {
            try process.run()
        } catch {
            isRequestingCommandLineTools = false
            message = "Could not request Apple's Command Line Tools installer: \(error.localizedDescription)"
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
        message = "Looking up the latest official Homebrew.pkg…"

        do {
            let packageURL = try await downloadHomebrewPackage()
            guard NSWorkspace.shared.open(packageURL) else {
                throw HomebrewProvisioningError.couldNotOpenInstaller
            }
            setHomebrewState(.waiting("Homebrew.pkg was opened in macOS Installer. Finish or cancel it, then press Check again; opening it is not success."))
            message = "Homebrew.pkg was handed to macOS Installer. Complete or cancel Apple's UI, then press Check again before retrying."
        } catch {
            setHomebrewState(.attention("Homebrew handoff failed: \(error.localizedDescription)"))
            message = "Homebrew handoff failed: \(error.localizedDescription) Press Check again before retrying."
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

        message = "Downloading Homebrew.pkg from Homebrew's official release…"
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

        // Inspect fnm's local inventory first. Calling `fnm exec --using` for an
        // absent version can install it, so no exec check is attempted until the
        // exact version is reported as installed.
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

    private static let readOnlyRuntimeEnvironment: [String: String] = [
        "FNM_COREPACK_ENABLED": "false",
        "FNM_RESOLVE_ENGINES": "false",
        "COREPACK_ENABLE_NETWORK": "0",
        "COREPACK_DEFAULT_TO_LATEST": "0",
        "COREPACK_ENABLE_PROJECT_SPEC": "0"
    ]

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
            case .fnm: return "fnm"
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
    }

    let id: ID
    let state: State

    static var all: [ProvisioningCheck] {
        ID.allCases.map { ProvisioningCheck(id: $0, state: .checking) }
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
