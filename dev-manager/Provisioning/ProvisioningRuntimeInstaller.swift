#if DEBUG
import Foundation

nonisolated enum ProvisioningRuntimeInstaller {
    nonisolated static func installFNM() async -> ProvisioningInstallProcessResult {
        await ProvisioningCommandRunner.runInstallProcess(
            executableURL: ProvisioningConfiguration.homebrewURL,
            arguments: ["install", "fnm"],
            environment: ProvisioningConfiguration.installEnvironment,
            label: "brew install fnm"
        )
    }

    nonisolated static func installNode(using fnmURL: URL) async -> ProvisioningInstallProcessResult {
        await ProvisioningCommandRunner.runInstallProcess(
            executableURL: fnmURL,
            arguments: ["install", ProvisioningConfiguration.nodeVersion],
            environment: ProvisioningConfiguration.runtimeInstallEnvironment,
            label: "fnm install \(ProvisioningConfiguration.nodeVersion)"
        )
    }

    nonisolated static func installPnpm(using fnmURL: URL) async -> ProvisioningInstallProcessResult {
        await ProvisioningCommandRunner.runInstallProcess(
            executableURL: fnmURL,
            arguments: [
                "exec", "--using", ProvisioningConfiguration.nodeVersion,
                "npm", "install", "--global", "pnpm@\(ProvisioningConfiguration.pnpmVersion)"
            ],
            environment: ProvisioningConfiguration.runtimeInstallEnvironment,
            label: "npm install --global pnpm@\(ProvisioningConfiguration.pnpmVersion)"
        )
    }
}
#endif
