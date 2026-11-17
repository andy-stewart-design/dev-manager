#if DEBUG
import Foundation
import Testing
@testable import dev_manager

@Suite("Provisioning GitHub CLI")
struct ProvisioningGitHubCLITests {
    @Test("GitHub CLI installation is independent of Node and reinspects after brew")
    @MainActor
    func modelInstallsOnlyMissingCLI() async {
        let targetCalls = GitHubCLICallCounter()
        let installCalls = GitHubCLICallCounter()
        let homebrew = ProvisioningCheck(id: .homebrew, state: .ready("Homebrew"))
        let dependencies = ProvisioningModelDependencies(
            inspect: {
                ProvisioningInspection(
                    developerTools: ProvisioningCheck(id: .developerTools, state: .ready("Apple")),
                    developerToolsExecutableURL: nil,
                    homebrew: homebrew,
                    fnm: ProvisioningCheck(id: .fnm, state: .missing("Node is not installed")),
                    fnmExecutableURL: nil,
                    chosenFNMDirectoryURL: nil,
                    node: ProvisioningCheck(id: .node, state: .missing("Node is not installed")),
                    pnpm: ProvisioningCheck(id: .pnpm, state: .unverified("Node is not installed")),
                    runtimeContext: nil,
                    githubCLI: ProvisioningCheck(id: .githubCLI, state: .missing("gh is not installed"))
                )
            },
            inspectTarget: { id in
                let call = await targetCalls.next()
                let state: ProvisioningCheck.State = call == 0 ? .missing("gh is not installed") : .ready("gh version 2.83.1")
                let check = ProvisioningCheck(id: id, state: state)
                return ProvisioningTargetedInspection(
                    checks: [check], fnmExecutableURL: nil, runtimeContext: nil,
                    githubCLI: check,
                    githubCLIContext: state.isReady ? ProvisioningGitHubCLIContext(executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/gh"), version: "2.83.1") : nil
                )
            },
            installGitHubCLI: {
                _ = await installCalls.next()
                return ProvisioningProcessResult(succeeded: true, stdout: "", stderr: "", terminationStatus: 0, timedOut: false)
            },
            recordInstallation: { _, _ in .failed("test recorder intentionally disabled") }
        )
        let model = ProvisioningModel(dependencies: dependencies)
        await model.checkAgain()
        #expect(model.checks.first(where: { $0.id == .node })?.state.isMissing == true)
        #expect(model.canInstallGitHubCLI)
        await model.installGitHubCLI()
        #expect(await installCalls.value == 1)
        #expect(await targetCalls.value == 2)
        #expect(model.checks.first(where: { $0.id == .githubCLI })?.state.isReady == true)
    }

    @Test("candidate discovery is ordered, deduplicated, and bounded")
    func boundedCandidates() {
        let home = URL(fileURLWithPath: "/tmp/gh-home")
        let path = (0..<40).map { "/tmp/path-\($0)" }.joined(separator: ":")
        let candidates = ProvisioningGitHubCLIInspector.candidateURLs(
            environment: ["PATH": path],
            homeDirectory: home
        )
        #expect(candidates.first?.path == "/opt/homebrew/bin/gh")
        #expect(candidates.contains(where: { $0.path == "/usr/local/bin/gh" }))
        #expect(candidates.contains(where: { $0.path == "/tmp/gh-home/.local/bin/gh" }))
        #expect(candidates.count <= ProvisioningRuntimePolicy.maximumExecutableCandidates)
        #expect(Set(candidates).count == candidates.count)
    }

    @Test("parses the actual gh version line and rejects human output that is not a version")
    func parsesVersion() {
        #expect(ProvisioningGitHubCLIInspector.parseVersion(from: "gh version 2.83.1 (2026-01-15)\n") == "2.83.1")
        #expect(ProvisioningGitHubCLIInspector.parseVersion(from: "gh version not-installed\n") == nil)
        #expect(ProvisioningGitHubCLIInspector.parseVersion(from: "GitHub CLI\n") == nil)
    }

    @Test("working existing gh is reused without Node or auth probes")
    func reusesWorkingCLI() async {
        let home = URL(fileURLWithPath: "/tmp/gh-test-home")
        let executable = home.appendingPathComponent(".local/bin/gh")
        let result = await ProvisioningGitHubCLIInspector.inspect(
            environment: ["PATH": "/tmp/other/bin"],
            homeDirectory: home,
            fileExists: { $0 == executable.path },
            isExecutable: { $0 == executable.path },
            run: { url, arguments, _, _ in
                #expect(url == executable)
                #expect(arguments == ["--version"])
                return ProvisioningProcessResult(succeeded: true, stdout: "gh version 2.83.1 (2026-01-15)\n", stderr: "", terminationStatus: 0, timedOut: false)
            }
        )
        #expect(result.check.state == .ready("gh version 2.83.1 at \(executable.path)"))
        #expect(result.context?.executableURL == executable)
        #expect(result.context?.version == "2.83.1")
    }

    @Test("malformed, timed out, and non-executable candidates require attention")
    func malformedCandidatesRequireAttention() async {
        let home = URL(fileURLWithPath: "/tmp/gh-attention-home")
        let executable = home.appendingPathComponent(".local/bin/gh")
        let malformed = await ProvisioningGitHubCLIInspector.inspect(
            environment: [:], homeDirectory: home,
            fileExists: { $0 == executable.path }, isExecutable: { _ in true },
            run: { _, _, _, _ in ProvisioningProcessResult(succeeded: true, stdout: "gh version future-wording\n", stderr: "", terminationStatus: 0, timedOut: false) }
        )
        #expect(malformed.check.state.isAttention)

        let timedOut = await ProvisioningGitHubCLIInspector.inspect(
            environment: [:], homeDirectory: home,
            fileExists: { $0 == executable.path }, isExecutable: { _ in true },
            run: { _, _, _, _ in ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "", terminationStatus: -1, timedOut: true) }
        )
        #expect(timedOut.check.state.isAttention)

        let failed = await ProvisioningGitHubCLIInspector.inspect(
            environment: [:], homeDirectory: home,
            fileExists: { $0 == executable.path }, isExecutable: { _ in true },
            run: { _, _, _, _ in ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "permission denied", terminationStatus: 1, timedOut: false) }
        )
        #expect(failed.check.state.isAttention)

        let nonExecutable = await ProvisioningGitHubCLIInspector.inspect(
            environment: [:], homeDirectory: home,
            fileExists: { $0 == executable.path }, isExecutable: { _ in false },
            run: { _, _, _, _ in Issue.record("non-executable candidate must not run"); return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "", terminationStatus: -1, timedOut: false) }
        )
        #expect(nonExecutable.check.state == ProvisioningCheck.State.attention("A GitHub CLI file exists at \(executable.path), but it is not executable. No file was overwritten."))
    }

    @Test("installation description is exactly brew install gh")
    func installCommand() {
        #expect(ProvisioningGitHubCLIInstaller.installArguments == ["install", "gh"])
        #expect(ProvisioningGitHubCLIInstaller.installLabel == "brew install gh")
    }
}

private actor GitHubCLICallCounter {
    private var count = 0
    func next() -> Int { defer { count += 1 }; return count }
    var value: Int { count }
}
#endif
