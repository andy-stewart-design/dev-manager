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
        guard context.isManagedByFNM,
              let fnmURL = context.fnmExecutableURL,
              let selector = context.fnmSelector else {
            return ProvisioningProcessResult(
                succeeded: false,
                stdout: "",
                stderr: "The selected runtime context does not contain a usable managed fnm executable and selector.",
                terminationStatus: -1,
                timedOut: false
            )
        }
        let environment = ProvisioningFNMContext.environment(
            basedOn: ProvisioningConfiguration.runtimeInstallEnvironment,
            root: context.chosenFNMDirectoryURL
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
}
