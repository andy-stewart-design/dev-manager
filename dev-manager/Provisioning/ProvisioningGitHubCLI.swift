import Foundation

nonisolated struct ProvisioningGitHubCLIContext: Equatable, Sendable {
    let executableURL: URL
    let version: String

    init(executableURL: URL, version: String) {
        self.executableURL = executableURL
        self.version = version
    }
}

nonisolated enum ProvisioningGitHubCLIInspector {
    typealias Runner = @Sendable (URL, [String], [String: String], TimeInterval) async -> ProvisioningProcessResult
    typealias FileExists = @Sendable (String) -> Bool
    typealias IsExecutable = @Sendable (String) -> Bool

    static func candidateURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [URL] {
        let standard = [
            URL(fileURLWithPath: "/opt/homebrew/bin/gh"),
            URL(fileURLWithPath: "/usr/local/bin/gh"),
            homeDirectory.appendingPathComponent(".local/bin/gh")
        ]
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .prefix(ProvisioningRuntimePolicy.maximumInheritedPATHEntries)
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("gh") }
        var result = [URL]()
        for candidate in standard + pathCandidates where !result.contains(candidate) {
            result.append(candidate)
            if result.count == ProvisioningRuntimePolicy.maximumExecutableCandidates { break }
        }
        return result
    }

    static func inspect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileExists: @escaping FileExists = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: @escaping IsExecutable = { FileManager.default.isExecutableFile(atPath: $0) },
        run: @escaping Runner = { executable, arguments, environment, timeout in
            await ProvisioningCommandRunner.run(executable, arguments: arguments, environment: environment, timeout: timeout)
        }
    ) async -> (check: ProvisioningCheck, context: ProvisioningGitHubCLIContext?) {
        let candidates = candidateURLs(environment: environment, homeDirectory: homeDirectory)
        var foundNonExecutable: URL?
        var executableFailure: (URL, String)?

        for candidate in candidates {
            guard fileExists(candidate.path) else { continue }
            guard isExecutable(candidate.path) else {
                foundNonExecutable = foundNonExecutable ?? candidate
                continue
            }
            let result = await run(candidate, ["--version"], [:], ProvisioningConfiguration.commandTimeout)
            guard result.succeeded,
                  let version = parseVersion(from: result.stdout) ?? parseVersion(from: result.stderr) else {
                executableFailure = executableFailure ?? (candidate, result.failureDescription(for: "gh --version", timeout: ProvisioningConfiguration.commandTimeout))
                continue
            }
            let context = ProvisioningGitHubCLIContext(executableURL: candidate, version: version)
            return (
                ProvisioningCheck(id: .githubCLI, state: .ready("gh version \(version) at \(candidate.path)")),
                context
            )
        }

        if let executableFailure {
            return (
                ProvisioningCheck(id: .githubCLI, state: .attention("Found \(executableFailure.0.path), but its bounded gh --version check was not usable: \(executableFailure.1)")),
                nil
            )
        }
        if let foundNonExecutable {
            return (
                ProvisioningCheck(id: .githubCLI, state: .attention("A GitHub CLI file exists at \(foundNonExecutable.path), but it is not executable. No file was overwritten.")),
                nil
            )
        }
        return (
            ProvisioningCheck(id: .githubCLI, state: .missing("GitHub CLI was not found in the bounded GUI PATH or standard locations.")),
            nil
        )
    }

    static func parseVersion(from output: String) -> String? {
        guard let line = output.firstNonEmptyLine else { return nil }
        let pieces = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard pieces.count >= 3, pieces[0].lowercased() == "gh", pieces[1].lowercased() == "version" else { return nil }
        let token = pieces[2].trimmingCharacters(in: CharacterSet(charactersIn: "(),"))
        guard token == pieces[2], ProvisioningRuntimePolicy.normalizedRuntimeVersion(token) != nil else { return nil }
        return token
    }
}

