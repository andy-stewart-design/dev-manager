#if DEBUG
import Testing
@testable import dev_manager

@Suite("Provisioning runtime policy")
struct ProvisioningRuntimePolicyTests {
    @Test("supports the documented stable Node and pnpm major families")
    func supportedMajorFamilies() {
        for version in ["22.0.0", "24.21.0", "26.1.3"] {
            #expect(ProvisioningRuntimePolicy.isSupportedNodeVersion(version))
        }
        for nodeMajor in [22, 24, 26] {
            #expect(ProvisioningRuntimePolicy.isSupportedNodeVersion("\(nodeMajor).0.0"))
            for pnpmMajor in [10, 11, 12] {
                #expect(ProvisioningRuntimePolicy.supportsPair(nodeVersion: "\(nodeMajor).0.0", pnpmVersion: "\(pnpmMajor).0.0"))
            }
        }
        #expect(ProvisioningRuntimePolicy.supportedNodeMajors == Set([22, 24, 26]))
        #expect(ProvisioningRuntimePolicy.supportedPnpmMajors == Set([10, 11, 12]))
    }

    @Test("accepts the approved user example without requiring recommended patches")
    func acceptsUserExample() {
        #expect(ProvisioningRuntimePolicy.isSupportedNodeVersion("24.21.0"))
        #expect(ProvisioningRuntimePolicy.isSupportedPnpmVersion("12.6.0"))
        #expect(ProvisioningRuntimePolicy.recommendedNodeVersion == "24.22.2")
        #expect(ProvisioningRuntimePolicy.recommendedPnpmVersion == "12.18.0")
    }

    @Test("maps unsupported, prerelease, and unusable versions to attention-worthy statuses") {
        #expect(ProvisioningRuntimePolicy.nodeStatus("20.19.0") == .unsupported)
        #expect(ProvisioningRuntimePolicy.nodeStatus("24.22.0-rc.1") == .prerelease)
        #expect(ProvisioningRuntimePolicy.pnpmStatus("13.0.0") == .unsupported)
        #expect(ProvisioningRuntimePolicy.pnpmStatus("not-a-version") == .unusable)
    }

    @Test("stable candidate inventory rejects prereleases before normalization")
    func prereleaseInventoryIsNotSelected() {
        let candidates = ProvisioningRuntimePolicy.orderedStableNodeCandidates(
            defaultVersion: nil,
            inventory: ["v24.22.0-rc.1", "24.21.0", "v26.0.0-nightly.1"]
        )
        #expect(candidates == ["24.21.0"])
    }

    @Test("implicit fnm roots prefer real inventory over empty roots")
    func implicitFNMRootPrecedence() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let mac = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let roots = ProvisioningFNMContext.orderedDataRoots(
            explicitFNMDirectory: nil,
            xdgFNMDirectory: nil,
            homeDirectory: home,
            evidence: [legacy: ProvisioningFNMRootEvidence(hasConfiguredDefault: true)]
        )
        #expect(roots == [legacy, mac])
    }

    @Test("explicit FNM_DIR wins despite legacy evidence")
    func explicitFNMRootWins() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let explicit = URL(fileURLWithPath: "/tmp/explicit-fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let roots = ProvisioningFNMContext.orderedDataRoots(
            explicitFNMDirectory: explicit,
            xdgFNMDirectory: nil,
            homeDirectory: home,
            evidence: [legacy: ProvisioningFNMRootEvidence(hasConfiguredDefault: true)]
        )
        #expect(roots == [explicit])
    }

    @Test("XDG fnm root wins over implicit legacy evidence")
    func xdgFNMRootWins() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let xdg = URL(fileURLWithPath: "/tmp/xdg/fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let roots = ProvisioningFNMContext.orderedDataRoots(
            explicitFNMDirectory: nil,
            xdgFNMDirectory: xdg,
            homeDirectory: home,
            evidence: [legacy: ProvisioningFNMRootEvidence(hasConfiguredDefault: true)]
        )
        #expect(roots == [xdg])
    }

    @Test("an authoritative fnm Node remains selected when pnpm is missing")
    func authoritativeNodeDoesNotBecomeGUIFallback() {
        let context = ProvisioningRuntimeContext(
            nodeVersion: "24.21.0",
            nodeExecutableURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/node"),
            pnpmVersion: nil,
            pnpmExecutableURL: nil,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            chosenFNMDirectoryURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm", isDirectory: true)
        )
        #expect(context.isManagedByFNM)
        #expect(!context.hasUsablePnpm)
        #expect(context.chosenFNMDirectoryURL?.path == "/Users/test/.local/share/fnm")
    }

    @Test("a managed context requires its selected fnm root")
    func managedContextRequiresRoot() {
        let context = ProvisioningRuntimeContext(
            nodeVersion: "24.21.0",
            nodeExecutableURL: URL(fileURLWithPath: "/tmp/node"),
            pnpmVersion: "12.6.0",
            pnpmExecutableURL: URL(fileURLWithPath: "/tmp/pnpm"),
            fnmExecutableURL: URL(fileURLWithPath: "/tmp/fnm"),
            fnmSelector: "24.21.0"
        )
        #expect(!context.isManagedByFNM)
    }

    @Test("pnpm candidates retain Homebrew after a nonempty GUI PATH")
    func pnpmCandidateOrderIncludesHomebrew() {
        let candidates = ProvisioningExecutablePaths.pnpmCandidates(
            inheritedPATH: "/custom/bin:/usr/bin"
        )
        #expect(candidates.first?.path == "/opt/homebrew/bin/pnpm")
        #expect(candidates.contains(URL(fileURLWithPath: "/usr/local/bin/pnpm")))
        #expect(candidates.contains(URL(fileURLWithPath: "/custom/bin/pnpm")))
    }

    @Test("a missing fnm candidate does not hide global pnpm candidates")
    func missingFNMCandidateDoesNotHideGlobalPnpm() {
        let candidates = ProvisioningExecutablePaths.pnpmCandidates(
            prior: [URL(fileURLWithPath: "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/pnpm")],
            inheritedPATH: "/usr/bin"
        )
        #expect(candidates.first?.path.contains(".local/share/fnm") == true)
        #expect(candidates.contains(URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")))
    }

    @Test("selected Node pnpm precedes Homebrew while retaining fallback candidates")
    func selectedNodePnpmPrecedesHomebrew() {
        let selectedNode = URL(fileURLWithPath: "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/node")
        let candidates = ProvisioningExecutablePaths.pnpmCandidates(
            selectedNodeURL: selectedNode,
            inheritedPATH: "/custom/bin"
        )
        #expect(candidates.first?.path == "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/pnpm")
        #expect(candidates.contains(URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")))
        #expect(candidates.contains(URL(fileURLWithPath: "/custom/bin/pnpm")))
    }

    @Test("selected Node directory precedes Homebrew in external pnpm probe PATH")
    func selectedNodePathPrecedesHomebrew() {
        let path = ProvisioningExecutablePaths.runtimePATH(
            selectedNodeURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/node"),
            inheritedPATH: "/opt/homebrew/bin:/usr/bin",
            safeSystemPATH: "/opt/homebrew/bin:/usr/bin:/bin"
        )
        #expect(path.split(separator: ":").first.map(String.init) == "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin")
        #expect(path.split(separator: ":").map(String.init).filter { $0 == "/opt/homebrew/bin" }.count == 1)
    }

    @Test("candidate ordering keeps later candidates available after an unsupported first probe")
    func unsupportedCandidateDoesNotEndDiscovery() {
        let candidates = ProvisioningExecutablePaths.pnpmCandidates(
            prior: [URL(fileURLWithPath: "/tmp/unsupported-pnpm")],
            inheritedPATH: "/custom/bin"
        )
        #expect(candidates.first?.path == "/tmp/unsupported-pnpm")
        #expect(candidates.contains(URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")))
        #expect(candidates.contains(URL(fileURLWithPath: "/custom/bin/pnpm")))
    }

    @Test("executable candidate ordering is deduplicated and bounded")
    func executableCandidatesAreDeduplicatedAndBounded() {
        let candidates = ProvisioningExecutablePaths.orderedCandidates(
            name: "pnpm",
            prior: [URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")],
            known: [URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")],
            inheritedPATH: Array(repeating: "/bin", count: 40).joined(separator: ":")
        )
        #expect(candidates.count <= ProvisioningRuntimePolicy.maximumExecutableCandidates)
        let paths = candidates.map { $0.standardizedFileURL.path }
        #expect(paths.count == Set(paths).count)
    }

    @Test("ready labels retain actual detected versions")
    func actualVersionLabels() {
        #expect(ProvisioningCheck(id: .node, state: .ready("Node 24.21.0; path: /tmp/node")).rowTitle == "Node 24.21.0")
        #expect(ProvisioningCheck(id: .pnpm, state: .ready("pnpm 12.6.0; path: /tmp/pnpm")).rowTitle == "pnpm 12.6.0")
        #expect(ProvisioningCheck(id: .node, state: .missing("recommended Node 24.22.2")).rowTitle == "Node")
    }

    @Test("prefers the read-only fnm default while retaining bounded inventory order")
    func candidatePreference() {
        let candidates = ProvisioningRuntimePolicy.orderedStableNodeCandidates(
            defaultVersion: "v24.21.0",
            inventory: ["v22.20.0", "v24.21.0", "v26.1.0", "v20.0.0"]
        )
        #expect(candidates == ["24.21.0", "22.20.0", "26.1.0"])
        #expect(candidates.count <= ProvisioningRuntimePolicy.maximumFNMRuntimeCandidates)
    }
}
#endif
