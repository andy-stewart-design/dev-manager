import Foundation

nonisolated enum ProvisioningRuntimeInstaller {
    nonisolated static func installFNM() async -> ProvisioningProcessResult {
        await ProvisioningCommandRunner.runInstallProcess(
            executableURL: ProvisioningConfiguration.homebrewURL,
            arguments: ["install", "fnm"],
            environment: ProvisioningConfiguration.installEnvironment,
            label: "brew install fnm"
        )
    }

    nonisolated static func installNode(using fnmURL: URL, fnmDirectoryURL: URL? = nil) async -> ProvisioningProcessResult {
        var environment = ProvisioningConfiguration.runtimeInstallEnvironment
        if let fnmDirectoryURL {
            environment = ProvisioningFNMContext.environment(basedOn: environment, root: fnmDirectoryURL)
        }
        return await ProvisioningCommandRunner.runInstallProcess(
            executableURL: fnmURL,
            arguments: ["install", ProvisioningRuntimePolicy.recommendedNodeVersion],
            environment: environment,
            label: "fnm install \(ProvisioningRuntimePolicy.recommendedNodeVersion)"
        )
    }

    nonisolated static func installPnpm(using context: ProvisioningRuntimeContext) async -> ProvisioningProcessResult {
        let version = ProvisioningRuntimePolicy.recommendedPnpmVersion
        if context.isManagedByFNM,
           let fnmURL = context.fnmExecutableURL,
           let selector = context.fnmSelector,
           let root = context.chosenFNMDirectoryURL {
            let environment = ProvisioningFNMContext.environment(
                basedOn: ProvisioningConfiguration.runtimeInstallEnvironment,
                root: root
            )
            return await ProvisioningCommandRunner.runInstallProcess(
                executableURL: fnmURL,
                arguments: [
                    "exec", "--using", selector,
                    "npm", "install", "--global", "pnpm@\(version)"
                ],
                environment: environment,
                label: "npm install --global pnpm@\(version) in Node \(selector)"
            )
        }

        // For an accepted unmanaged GUI Node, keep the selected Node directory
        // first on PATH so npm's own shebang resolves to that concrete Node.
        var environment = ProvisioningConfiguration.runtimeInstallEnvironment
        let nodeDirectory = context.nodeExecutableURL.deletingLastPathComponent().path
        environment["PATH"] = nodeDirectory + ":" + (environment["PATH"] ?? "")
        return await ProvisioningCommandRunner.runInstallProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["npm", "install", "--global", "pnpm@\(version)"],
            environment: environment,
            label: "npm install --global pnpm@\(version) in Node \(context.nodeVersion)"
        )
    }
}
