#if DEBUG
import Darwin
import Foundation

nonisolated enum ProvisioningInspector {
    nonisolated static func inspect() async -> ProvisioningInspection {
        let developerTools = await checkDeveloperTools()
        let homebrew = await checkHomebrew()
        let fnm = await checkFNM()
        let runtime = await checkRuntime(using: fnm.executableURL)
        return ProvisioningInspection(
            developerTools: developerTools.check,
            developerToolsExecutableURL: developerTools.executableURL,
            homebrew: homebrew.check,
            fnm: fnm.check,
            fnmExecutableURL: fnm.executableURL,
            node: runtime.node,
            pnpm: runtime.pnpm
        )
    }

    private nonisolated static func checkDeveloperTools() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let selector = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"])
        guard selector.succeeded, let selectedPath = selector.stdout.firstNonEmptyLine else {
            if selector.timedOut {
                return (ProvisioningCheck(id: .developerTools, state: .attention(selector.failureDescription(for: "xcode-select"))), nil)
            }
            return (ProvisioningCheck(id: .developerTools, state: .missing("No usable developer tools are selected. Request Apple's graphical installer, then Check again.")), nil)
        }

        let clang = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "clang"])
        guard clang.succeeded, let clangPath = clang.stdout.firstNonEmptyLine else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("Selected tools at \(selectedPath) are not usable: \(clang.failureDescription(for: "xcrun --find clang"))")), nil)
        }

        let sdk = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--sdk", "macosx", "--show-sdk-path"])
        guard sdk.succeeded else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("clang is at \(clangPath), but the macOS SDK check failed: \(sdk.failureDescription(for: "xcrun --show-sdk-path"))")), nil)
        }

        return (ProvisioningCheck(id: .developerTools, state: .ready("Selected: \(selectedPath); clang: \(clangPath)")), URL(fileURLWithPath: clangPath))
    }

    private nonisolated static func checkHomebrew() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let brew = ProvisioningConfiguration.homebrewURL
        guard FileManager.default.isExecutableFile(atPath: brew.path) else {
            return (ProvisioningCheck(id: .homebrew, state: .missing("Homebrew was not found at /opt/homebrew/bin/brew.")), nil)
        }

        let result = await ProvisioningCommandRunner.run(brew, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .homebrew, state: .attention("Found \(brew.path), but it did not run as the current user: \(result.failureDescription(for: "brew --version"))")), brew)
        }
        return (ProvisioningCheck(id: .homebrew, state: .ready("\(result.stdout.firstNonEmptyLine ?? brew.path); \(brew.path) ran as the current user")), brew)
    }

    private nonisolated static func checkFNM() async -> (check: ProvisioningCheck, executableURL: URL?) {
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

        let result = await ProvisioningCommandRunner.run(fnm, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .fnm, state: .attention("Found \(fnm.path), but it did not run as the current user: \(result.failureDescription(for: "fnm --version"))")), fnm)
        }
        return (ProvisioningCheck(id: .fnm, state: .ready("\(result.stdout.firstNonEmptyLine ?? "fnm") at \(fnm.path)")), fnm)
    }

    private nonisolated static func checkRuntime(using fnmURL: URL?) async -> (node: ProvisioningCheck, pnpm: ProvisioningCheck) {
        guard let fnmURL else {
            return (
                ProvisioningCheck(id: .node, state: .unverified("Waiting to verify Node \(ProvisioningConfiguration.nodeVersion); fnm is unavailable.")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(ProvisioningConfiguration.nodeVersion) context; fnm is unavailable."))
            )
        }

        let inspection = await ProvisioningCommandRunner.run(fnmURL, arguments: ["list"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment)
        guard inspection.succeeded else {
            let failure = inspection.failureDescription(for: "fnm list")
            return (
                ProvisioningCheck(id: .node, state: .attention("Could not inspect the installed Node \(ProvisioningConfiguration.nodeVersion): \(failure)")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(ProvisioningConfiguration.nodeVersion) context; fnm inventory failed: \(failure)"))
            )
        }
        guard inspection.stdout.containsToken("v\(ProvisioningConfiguration.nodeVersion)") else {
            return (
                ProvisioningCheck(id: .node, state: .missing("Node \(ProvisioningConfiguration.nodeVersion) is not installed in fnm. No runtime was invoked or installed.")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(ProvisioningConfiguration.nodeVersion) context; the pinned Node runtime is unavailable."))
            )
        }

        let node = await ProvisioningCommandRunner.run(fnmURL, arguments: ["exec", "--using", ProvisioningConfiguration.nodeVersion, "node", "--version"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment)
        guard node.succeeded else {
            let failure = node.failureDescription(for: "fnm exec node")
            return (
                ProvisioningCheck(id: .node, state: .attention("The installed Node \(ProvisioningConfiguration.nodeVersion) could not run through fnm: \(failure)")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(ProvisioningConfiguration.nodeVersion) context; the pinned Node runtime could not run."))
            )
        }
        guard node.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "v\(ProvisioningConfiguration.nodeVersion)" else {
            let output = node.stdout.firstNonEmptyLine ?? "no version output"
            return (
                ProvisioningCheck(id: .node, state: .attention("fnm returned an unusable Node version for \(ProvisioningConfiguration.nodeVersion): \(output).")),
                ProvisioningCheck(id: .pnpm, state: .unverified("Not yet verified in the required Node \(ProvisioningConfiguration.nodeVersion) context; Node did not report the pinned version."))
            )
        }

        let pnpmPath = await ProvisioningCommandRunner.run(fnmURL, arguments: ["exec", "--using", ProvisioningConfiguration.nodeVersion, "/usr/bin/which", "pnpm"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment)
        guard pnpmPath.succeeded else {
            if pnpmPath.timedOut {
                return (
                    ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
                    ProvisioningCheck(id: .pnpm, state: .attention("Could not inspect pnpm in the required Node \(ProvisioningConfiguration.nodeVersion) context: \(pnpmPath.failureDescription(for: "which pnpm"))"))
                )
            }
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .missing("pnpm \(ProvisioningConfiguration.pnpmVersion) is not installed in the Node \(ProvisioningConfiguration.nodeVersion) context. No Corepack download was attempted."))
            )
        }
        guard let resolvedPnpm = pnpmPath.stdout.firstNonEmptyLine else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("fnm resolved pnpm in the Node \(ProvisioningConfiguration.nodeVersion) context without a usable executable path."))
            )
        }

        let pnpm = await ProvisioningCommandRunner.run(fnmURL, arguments: ["exec", "--using", ProvisioningConfiguration.nodeVersion, "pnpm", "--version"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment)
        guard pnpm.succeeded else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm at \(resolvedPnpm) in the Node \(ProvisioningConfiguration.nodeVersion) context, but it could not report its version: \(pnpm.failureDescription(for: "fnm exec pnpm"))"))
            )
        }
        guard pnpm.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == ProvisioningConfiguration.pnpmVersion else {
            return (
                ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
                ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm at \(resolvedPnpm) in the Node \(ProvisioningConfiguration.nodeVersion) context, but it reported \(pnpm.stdout.firstNonEmptyLine ?? "no version output") instead of \(ProvisioningConfiguration.pnpmVersion)."))
            )
        }

        return (
            ProvisioningCheck(id: .node, state: .ready("Node \(ProvisioningConfiguration.nodeVersion) through fnm")),
            ProvisioningCheck(id: .pnpm, state: .ready("pnpm \(ProvisioningConfiguration.pnpmVersion) through fnm's Node \(ProvisioningConfiguration.nodeVersion) context"))
        )
    }

    private nonisolated static func firstExecutable(candidates: [URL]) -> URL? {
        candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }
}

#endif
