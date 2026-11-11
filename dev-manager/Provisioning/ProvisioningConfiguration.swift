#if DEBUG
import Foundation

nonisolated enum ProvisioningConfiguration {
    nonisolated static let nodeVersion = "24.22.2"
    nonisolated static let pnpmVersion = "12.18.0"

    nonisolated static let commandTimeout: TimeInterval = 8
    nonisolated static let installTimeout: TimeInterval = 15 * 60
    // Cleanup is deliberately finite and shared by read-only checks and installers.
    // The value applies separately to the TERM and KILL phases; output-drain
    // cancellation has its own final grace after those two phases.
    nonisolated static let processCleanupGrace: TimeInterval = 2
    nonisolated static let processDrainCancellationGrace: TimeInterval = 0.25
    nonisolated static let homebrewReleaseAPIURL = "https://api.github.com/repos/Homebrew/brew/releases/latest"
    nonisolated static let homebrewPackageName = "Homebrew.pkg"
    nonisolated static let officialHomebrewReleasePrefix = "https://github.com/Homebrew/brew/releases/download/"

    nonisolated static let homebrewURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")

    nonisolated static var guiSafePATH: String {
        let inherited = ProcessInfo.processInfo.environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return inherited?.isEmpty == false ? inherited! : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    nonisolated static var readOnlyRuntimeEnvironment: [String: String] {
        [
            "PATH": guiSafePATH,
            "FNM_COREPACK_ENABLED": "false",
            "FNM_RESOLVE_ENGINES": "false",
            "COREPACK_ENABLE_NETWORK": "0",
            "COREPACK_DEFAULT_TO_LATEST": "0",
            "COREPACK_ENABLE_PROJECT_SPEC": "0"
        ]
    }

    nonisolated static var installEnvironment: [String: String] {
        [
            "PATH": guiSafePATH,
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "NONINTERACTIVE": "1"
        ]
    }

    nonisolated static var runtimeInstallEnvironment: [String: String] {
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

    nonisolated static var fixtureFolderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dev Manager", isDirectory: true)
            .appendingPathComponent("Provisioning Fixture", isDirectory: true)
    }

    nonisolated static let fixturePackageJSON = """
    {
      \"name\": \"dev-manager-provisioning-fixture\",
      \"private\": true,
      \"version\": \"1.0.0\",
      \"packageManager\": \"pnpm@\(pnpmVersion)\",
      \"engines\": { \"node\": \"\(nodeVersion)\" },
      \"scripts\": { \"dev\": \"node server.js\" }
    }
    """

    nonisolated static let fixtureServerJS = """
    const http = require(\"node:http\");

    const server = http.createServer((_request, response) => {
      response.writeHead(200, { \"Content-Type\": \"text/html; charset=utf-8\" });
      response.end(\"<h1>Dev Manager provisioning fixture</h1>\");
    });

    server.listen(0, \"127.0.0.1\", () => {
      const address = server.address();
      const port = typeof address === \"object\" && address ? address.port : \"unknown\";
      console.log(`Dev Manager fixture: http://127.0.0.1:${port}/`);
    });
    """

    nonisolated static let fixtureMarker = "dev-manager-provisioning-fixture-v1\n"

    nonisolated static var fixtureFiles: [(name: String, contents: String)] {
        [
            (".dev-manager-fixture", fixtureMarker),
            ("package.json", fixturePackageJSON),
            ("server.js", fixtureServerJS),
            (".node-version", "\(nodeVersion)\n")
        ]
    }
}
#endif
