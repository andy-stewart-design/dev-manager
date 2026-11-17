import Foundation

nonisolated enum ProvisioningGitHubCLIInstaller {
    static let installArguments = ["install", "gh"]
    static let installLabel = "brew install gh"

    static func install() async -> ProvisioningProcessResult {
        await install(using: ProvisioningConfiguration.homebrewURL)
    }

    static func install(using brewURL: URL) async -> ProvisioningProcessResult {
        await ProvisioningCommandRunner.runInstallProcess(
            executableURL: brewURL,
            arguments: installArguments,
            environment: ProvisioningConfiguration.installEnvironment,
            label: installLabel
        )
    }
}
