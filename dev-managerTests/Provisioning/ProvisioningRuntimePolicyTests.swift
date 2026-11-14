#if DEBUG
import Foundation
import Testing
@testable import dev_manager

private final class ProvisioningCommandSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [[String]]()
    private var rootStorage = [String]()

    func record(_ arguments: [String], root: String? = nil) {
        lock.lock()
        storage.append(arguments)
        if let root { rootStorage.append(root) }
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var roots: [String] {
        lock.lock()
        defer { lock.unlock() }
        return rootStorage
    }
}

private func isJSONProbe(_ arguments: [String]) -> Bool {
    arguments.contains { $0.hasPrefix("JSON.stringify(") }
}

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

    @Test("maps unsupported, prerelease, and unusable versions to attention-worthy statuses")
    func versionStatuses() {
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

    @Test("an external macOS alias does not outrank a managed legacy default")
    func externalMacOSAliasDoesNotOutrankManagedLegacyDefault() {
        let home = URL(fileURLWithPath: "/Users/root-policy-external-macos", isDirectory: true)
        let mac = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let roots = ProvisioningFNMContext.orderedDataRoots(
            explicitFNMDirectory: nil,
            xdgFNMDirectory: nil,
            homeDirectory: home,
            evidence: [
                mac: ProvisioningFNMRootEvidence(
                    hasConfiguredDefault: false,
                    inventory: .knownEmpty,
                    defaultAlias: .external
                ),
                legacy: ProvisioningFNMRootEvidence(
                    hasConfiguredDefault: true,
                    hasInstalledInventory: true,
                    defaultAlias: .managed,
                    managedDefaultVersion: "24.21.0"
                )
            ]
        )
        #expect(roots == [legacy, mac])
    }

    @Test("a broken alias outranks an inventory-only implicit root")
    func brokenAliasOutranksInventoryOnlyRoot() {
        let home = URL(fileURLWithPath: "/Users/root-policy-broken-alias", isDirectory: true)
        let mac = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let roots = ProvisioningFNMContext.orderedDataRoots(
            explicitFNMDirectory: nil,
            xdgFNMDirectory: nil,
            homeDirectory: home,
            evidence: [
                mac: ProvisioningFNMRootEvidence(
                    hasConfiguredDefault: true,
                    defaultAlias: .broken
                ),
                legacy: ProvisioningFNMRootEvidence(
                    hasConfiguredDefault: false,
                    hasInstalledInventory: true,
                    inventory: .knownVersions(["24.21.0"]),
                    defaultAlias: .absent
                )
            ]
        )
        #expect(roots == [mac, legacy])
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

    @Test("inspector keeps explicit FNM_DIR and XDG roots ahead of populated implicit roots", arguments: ["FNM_DIR", "XDG_DATA_HOME"])
    func inspectorEnvironmentRootPrecedence(variable: String) async {
        let home = URL(fileURLWithPath: "/Users/root-policy-environment-\(variable)", isDirectory: true)
        let explicit = URL(fileURLWithPath: "/tmp/root-policy-\(variable)", isDirectory: true)
        let xdgParent = URL(fileURLWithPath: "/tmp/root-policy-xdg", isDirectory: true)
        let selected = variable == "FNM_DIR" ? explicit : xdgParent.appendingPathComponent("fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let spy = ProvisioningCommandSpy()
        let environment = variable == "FNM_DIR"
            ? ["FNM_DIR": explicit.path]
            : ["XDG_DATA_HOME": xdgParent.path]
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-policy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
                spy.record(arguments, root: environment["FNM_DIR"])
                return nil
            },
            filesystemFacts: { root in
                if root == legacy {
                    return ProvisioningFNMRootEvidence(hasConfiguredDefault: true, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .managed, managedDefaultVersion: "24.21.0", rootReadable: true)
                }
                return ProvisioningFNMRootEvidence(hasConfiguredDefault: false, hasInstalledInventory: false, inventory: .knownEmpty, defaultAlias: .absent, rootReadable: true)
            },
            executableAvailable: { _ in false },
            rootEnvironment: environment,
            homeDirectory: home
        )
        #expect(chosenRoot(observation) == selected)
        #expect(spy.calls.isEmpty)
        #expect(spy.roots.isEmpty)
    }

    @Test("a usable fallback Node retains selected root inventory attention")
    func selectedFallbackPreservesInventoryAttention() async {
        let home = URL(fileURLWithPath: "/Users/root-policy-unknown-inventory", isDirectory: true)
        let selected = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let alternate = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-policy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
                let root = URL(fileURLWithPath: environment["FNM_DIR"] ?? "", isDirectory: true)
                spy.record(arguments, root: root.path)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if isJSONProbe(arguments) {
                    return ProvisioningProcessResult(succeeded: true, stdout: "{\"version\":\"v24.21.0\",\"execPath\":\"" + root.path + "/node-versions/v24.21.0/installation/bin/node\"}\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return nil
            },
            filesystemFacts: { root in
                root == selected
                    ? ProvisioningFNMRootEvidence(hasConfiguredDefault: false, hasInstalledInventory: true, inventory: .unknown, defaultAlias: .absent, rootReadable: true)
                    : ProvisioningFNMRootEvidence(hasConfiguredDefault: false, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .absent, rootReadable: true)
            },
            executableAvailable: { url in
                url.path.hasSuffix("/installation/bin/node")
            },
            rootEnvironment: [:],
            homeDirectory: home
        )
        #expect(chosenRoot(observation) == selected)
        #expect(selectedContext(observation)?.node.version == "24.21.0")
        #expect(!spy.calls.isEmpty)
        #expect(Set(spy.roots) == Set([selected.path]))
        #expect(nodeAttention(observation)?.contains("could not be read") == true)
        #expect(!spy.roots.contains(alternate.path))
    }

    @Test("the populated legacy root is selected over an empty implicit macOS root")
    func populatedLegacyRootIsAuthoritative() async {
        let home = URL(fileURLWithPath: "/Users/root-policy-empty", isDirectory: true)
        let mac = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacy = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-policy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
                let root = URL(fileURLWithPath: environment["FNM_DIR"] ?? "", isDirectory: true)
                spy.record(arguments, root: root.path)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if isJSONProbe(arguments) {
                    return ProvisioningProcessResult(succeeded: true, stdout: "{\"version\":\"v24.21.0\",\"execPath\":\"" + root.path + "/node-versions/v24.21.0/installation/bin/node\"}\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return nil
            },
            filesystemFacts: { root in
                root == mac
                    ? ProvisioningFNMRootEvidence(hasConfiguredDefault: false, hasInstalledInventory: false, inventory: .knownEmpty, defaultAlias: .absent, rootReadable: true)
                    : ProvisioningFNMRootEvidence(hasConfiguredDefault: false, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .absent, rootReadable: true)
            },
            executableAvailable: { url in
                url.path.hasPrefix(legacy.path) && url.path.hasSuffix("/installation/bin/node")
            },
            rootEnvironment: [:],
            homeDirectory: home
        )
        #expect(chosenRoot(observation) == legacy)
        #expect(selectedContext(observation)?.node.version == "24.21.0")
        #expect(selectedContext(observation)?.node.executableURL.path == legacy.path + "/node-versions/v24.21.0/installation/bin/node")
        #expect(!spy.calls.isEmpty)
        #expect(Set(spy.roots) == Set([legacy.path]))
    }

    @Test("managed default failures and unsupported defaults retain the selected root", arguments: ["failed", "timed out", "unknown", "unsupported"])
    func managedDefaultFailuresRetainSelectedRoot(kind: String) async {
        let home = URL(fileURLWithPath: "/Users/root-policy-default-\(kind.replacingOccurrences(of: " ", with: "-"))", isDirectory: true)
        let selected = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let alternate = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-policy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
                let root = URL(fileURLWithPath: environment["FNM_DIR"] ?? "", isDirectory: true)
                spy.record(arguments, root: root.path)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if arguments == ["default"] {
                    if root == alternate {
                        return ProvisioningProcessResult(succeeded: true, stdout: "24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    switch kind {
                    case "failed":
                        return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "default unavailable", terminationStatus: 1, timedOut: false)
                    case "timed out":
                        return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "", terminationStatus: -1, timedOut: true)
                    case "unsupported":
                        return ProvisioningProcessResult(succeeded: true, stdout: "20.0.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                    default:
                        return ProvisioningProcessResult(succeeded: true, stdout: "not-a-version\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                }
                if isJSONProbe(arguments) {
                    let version = kind == "unsupported" && root == selected ? "v20.0.0" : "v24.21.0"
                    return ProvisioningProcessResult(succeeded: true, stdout: "{\"version\":\"" + version + "\",\"execPath\":\"" + root.path + "/node-versions/" + version + "/installation/bin/node\"}\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return nil
            },
            filesystemFacts: { root in
                root == selected
                    ? ProvisioningFNMRootEvidence(hasConfiguredDefault: true, hasInstalledInventory: true, inventory: .knownVersions([kind == "unsupported" ? "20.0.0" : "24.21.0"]), defaultAlias: kind == "unknown" ? .unknown : .managed, managedDefaultVersion: kind == "unsupported" ? "20.0.0" : "24.21.0", rootReadable: true)
                    : ProvisioningFNMRootEvidence(hasConfiguredDefault: true, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .managed, managedDefaultVersion: "24.21.0", rootReadable: true)
            },
            executableAvailable: { url in
                guard url.path.hasSuffix("/installation/bin/node") else { return false }
                if kind == "unsupported" {
                    return url.path.hasPrefix(selected.path) || url.path.hasPrefix(alternate.path)
                }
                return url.path.hasPrefix(alternate.path)
            },
            rootEnvironment: [:],
            homeDirectory: home
        )
        #expect(chosenRoot(observation) == selected)
        #expect(!spy.calls.isEmpty)
        #expect(Set(spy.roots) == Set([selected.path]))
        if kind == "unsupported" {
            #expect(selectedContext(observation)?.node.version == "20.0.0")
            #expect(nodeAttention(observation)?.contains("outside supported stable majors") == true)
        } else {
            #expect(selectedContext(observation) == nil)
            #expect(nodeAttention(observation) != nil)
        }
        #expect(!spy.roots.contains(alternate.path))
    }

    @Test("a broken selected default executable does not use a healthy alternate")
    func brokenSelectedDefaultExecutableDoesNotCrossRoots() async {
        let home = URL(fileURLWithPath: "/Users/root-policy-broken-executable", isDirectory: true)
        let selected = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let alternate = home.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-policy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
                let root = URL(fileURLWithPath: environment["FNM_DIR"] ?? "", isDirectory: true)
                spy.record(arguments, root: root.path)
                if arguments == ["default"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if isJSONProbe(arguments) {
                    return ProvisioningProcessResult(succeeded: true, stdout: "{\"version\":\"v24.21.0\",\"execPath\":\"" + root.path + "/node-versions/v24.21.0/installation/bin/node\"}\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return nil
            },
            filesystemFacts: { root in
                root == selected
                    ? ProvisioningFNMRootEvidence(hasConfiguredDefault: true, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .managed, managedDefaultVersion: "24.21.0", rootReadable: true)
                    : ProvisioningFNMRootEvidence(hasConfiguredDefault: true, hasInstalledInventory: true, inventory: .knownVersions(["24.21.0"]), defaultAlias: .managed, managedDefaultVersion: "24.21.0", rootReadable: true)
            },
            executableAvailable: { url in
                url.path.hasPrefix(alternate.path) && url.path.hasSuffix("/installation/bin/node")
            },
            rootEnvironment: [:],
            homeDirectory: home
        )
        #expect(chosenRoot(observation) == selected)
        #expect(spy.calls == [["default"]])
        #expect(Set(spy.roots) == Set([selected.path]))
        #expect(selectedContext(observation) == nil)
        #expect(nodeAttention(observation)?.contains("no executable") == true)
    }

    @Test("runtime outcome mapping preserves node missing and attention roots")
    func runtimeOutcomeMappingPreservesNodeStates() {
        let root = URL(fileURLWithPath: "/tmp/fnm-outcomes", isDirectory: true)
        let missing = ProvisioningInspector.runtimeChecks(for: .missing(root: root, reason: "no managed Node"))
        #expect(missing.chosenFNMDirectoryURL == root)
        if case .missing = missing.node.state {} else { #expect(Bool(false)) }
        if case .unverified = missing.pnpm.state {} else { #expect(Bool(false)) }

        let attention = ProvisioningInspector.runtimeChecks(for: .attention(root: root, reason: "Node probe failed"))
        #expect(attention.chosenFNMDirectoryURL == root)
        if case .attention = attention.node.state {} else { #expect(Bool(false)) }
        if case .unverified = attention.pnpm.state {} else { #expect(Bool(false)) }
    }

    @Test("selected runtime maps every explicit pnpm outcome")
    func selectedRuntimeMapsPnpmOutcomes() throws {
        let validNode = try makeValidatedNode()
        defer { try? FileManager.default.removeItem(at: validNode.root) }
        let node = validNode.node
        let fnm = URL(fileURLWithPath: "/opt/homebrew/bin/fnm")
        let root = validNode.root
        let pnpmURL = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let outcomes: [ProvisioningInspector.PnpmOutcome] = [
            .missing,
            .unusable(executableURL: pnpmURL, reason: "exit 1"),
            .unsupported(ProvisioningPnpmTool(version: "9.0.0", executableURL: pnpmURL)),
            .ready(ProvisioningPnpmTool(version: "12.6.0", executableURL: pnpmURL)),
            .budgetExhausted("Runtime inspection budget exhausted.")
        ]
        for outcome in outcomes {
            let checks = ProvisioningInspector.runtimeChecks(for: .selected(.init(node: node, fnmExecutableURL: fnm, fnmSelector: "24.21.0", root: root, pnpm: outcome)))
            switch outcome {
            case .missing:
                if case .missing = checks.pnpm.state {} else { #expect(Bool(false)) }
            case .ready:
                if case .ready = checks.pnpm.state {} else { #expect(Bool(false)) }
            case .unusable, .unsupported, .budgetExhausted:
                if case .attention = checks.pnpm.state {} else { #expect(Bool(false)) }
            }
        }

        let unsupportedFixture = try makeValidatedNode(version: "20.0.0")
        defer { try? FileManager.default.removeItem(at: unsupportedFixture.root) }
        let unsupportedNode = ProvisioningInspector.runtimeChecks(for: .selected(.init(
            node: unsupportedFixture.node,
            fnmExecutableURL: fnm,
            fnmSelector: "20.0.0",
            root: unsupportedFixture.root,
            pnpm: .ready(ProvisioningPnpmTool(version: "12.6.0", executableURL: pnpmURL)),
            attention: "configured default is unsupported"
        )))
        if case .attention = unsupportedNode.node.state {} else { #expect(Bool(false)) }
        if case .ready = unsupportedNode.pnpm.state {} else { #expect(Bool(false)) }
        #expect(unsupportedNode.context?.pnpm == nil)
        #expect(unsupportedNode.context?.hasUsablePnpm == false)
    }

    @Test("a managed fnm Node remains selected when pnpm is missing")
    func managedNodeRemainsSelectedWhenPnpmIsMissing() throws {
        let fixture = try makeValidatedNode()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let context = ProvisioningRuntimeContext(
            node: fixture.node,
            pnpm: nil,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            chosenFNMDirectoryURL: fixture.root
        )
        #expect(context.isManagedByFNM)
        #expect(!context.hasUsablePnpm)
        #expect(context.chosenFNMDirectoryURL == fixture.root)
    }

    @Test("fnm absence leaves external Node unprobed and setup-neutral")
    func absentFNMDoesNotAdoptExternalNode() {
        let checks = ProvisioningInspector.runtimeChecksWithoutFNM()
        if case .missing = checks.node.state {} else { #expect(Bool(false), "A known missing fnm backend leaves Node missing") }
        if case .unverified = checks.pnpm.state {} else { #expect(Bool(false), "pnpm cannot be verified without a managed Node") }
        #expect(!checks.node.state.isReady)
        #expect(!checks.pnpm.state.isReady)
    }

    @Test("failed fnm inspection leaves runtime unverified")
    func failedFNMInspectionDoesNotClaimMissingRuntime() {
        let checks = ProvisioningInspector.runtimeChecksWithoutFNM(fnmInspectionFailed: true)
        if case .unverified = checks.node.state {} else { #expect(Bool(false)) }
        if case .unverified = checks.pnpm.state {} else { #expect(Bool(false)) }
    }

    @Test("only concrete node-versions targets are managed")
    func managedNodePathValidation() {
        let root = URL(fileURLWithPath: "/tmp/fnm-root", isDirectory: true)
        #expect(ProvisioningRuntimePolicy.isManagedNodeExecutable(
            URL(fileURLWithPath: "/tmp/fnm-root/node-versions/v24.21.0/installation/bin/node"), within: root))
        // A non-existent lexical alias has no filesystem evidence to canonicalize;
        // a real alias is accepted when its target resolves inside node-versions.
        #expect(!ProvisioningRuntimePolicy.isManagedNodeExecutable(
            URL(fileURLWithPath: "/tmp/fnm-root/aliases/default/bin/node"), within: root))
        #expect(!ProvisioningRuntimePolicy.isManagedNodeExecutable(
            URL(fileURLWithPath: "/tmp/fnm-root-evil/node-versions/v24.21.0/installation/bin/node"), within: root))
        #expect(!ProvisioningRuntimePolicy.isManagedNodeExecutable(
            URL(fileURLWithPath: "/usr/local/bin/node"), within: root))
        let expected = root.appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        let external = ProvisioningManagedNode.validated(
            reportedVersion: "24.21.0",
            actualExecutablePath: "/usr/local/bin/node",
            selector: "24.21.0",
            expectedExecutableURL: expected,
            root: root,
            executableAvailable: { _ in true }
        )
        #expect(external.node == nil)
        #expect(external.failure != nil)
    }

    @Test("validated managed Node results retain canonical aliases and reject inconsistent probes")
    func validatedManagedNodeResults() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dev-manager-managed-node-\(UUID().uuidString)", isDirectory: true)
        let expected = root.appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        let other = root.appendingPathComponent("node-versions/v22.20.0/installation/bin/node")
        let alias = root.appendingPathComponent("aliases/default/bin/node")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: expected.path, contents: Data()))
        #expect(fileManager.createFile(atPath: other.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: expected.path)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: other.path)
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: expected)

        let valid = ProvisioningManagedNode.validated(
            reportedVersion: "v24.21.0",
            actualExecutablePath: alias.path,
            selector: "24.21.0",
            expectedExecutableURL: expected,
            root: root,
            executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
        )
        #expect(valid.node?.version == "24.21.0")
        #expect(valid.node?.executableURL == expected.resolvingSymlinksInPath().standardizedFileURL)

        let cases: [(String, String, URL, @Sendable (URL) -> Bool)] = [
            ("external path", "24.21.0", URL(fileURLWithPath: "/usr/local/bin/node"), { _ in true }),
            ("missing actual path", "24.21.0", URL(fileURLWithPath: "/tmp/missing-managed-node"), { $0 == expected }),
            ("different managed version", "24.21.0", other, { _ in true }),
            ("reported version mismatch", "22.20.0", expected, { _ in true })
        ]
        for (_, version, actual, available) in cases {
            let result = ProvisioningManagedNode.validated(
                reportedVersion: version,
                actualExecutablePath: actual.path,
                selector: "24.21.0",
                expectedExecutableURL: expected,
                root: root,
                executableAvailable: available
            )
            #expect(result.node == nil)
            #expect(result.failure != nil)
        }
    }

    @Test("probe results preserve prerelease information instead of making a stable Node")
    func probeVersionPreservesPrerelease() {
        #expect(ProvisioningRuntimePolicy.normalizedRuntimeVersion("v24.22.0-rc.1") == "24.22.0-rc.1")
        #expect(ProvisioningRuntimePolicy.nodeStatus("24.22.0-rc.1") == .prerelease)
        #expect(!ProvisioningRuntimePolicy.isSupportedNodeVersion("24.22.0-rc.1"))
    }

    @Test("normalized runtime versions enforce ASCII semantic-version components", arguments: [
        "0.0.0",
        "v24.21.0-rc.1+build.01",
        "24.21.0+001",
        "24.21.0-alpha-1"
    ])
    func strictRuntimeVersionAcceptsValidCases(version: String) {
        let expected = version.hasPrefix("v") ? String(version.dropFirst()) : version
        #expect(ProvisioningRuntimePolicy.normalizedRuntimeVersion(version) == expected)
    }

    @Test("normalized runtime versions reject malformed numeric and Unicode identifiers", arguments: [
        "",
        "24.21",
        "24.21.0.1",
        "024.21.0",
        "24.021.0",
        "24.21.00",
        "24.21.0-01",
        "24.21.0-rc..1",
        "24.21.0-rc_1",
        "24.21.0-β",
        "24.21.0+build_1",
        "24.21.0+"
    ])
    func strictRuntimeVersionRejectsInvalidCases(version: String) {
        #expect(ProvisioningRuntimePolicy.normalizedRuntimeVersion(version) == nil)
    }

    @Test("raw executable paths reject empty and relative paths before URL construction")
    func rawExecutablePathValidation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dev-manager-relative-node-\(UUID().uuidString)", isDirectory: true)
        let expected = root.appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: expected.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: expected.path)

        for path in ["", "node-versions/v24.21.0/installation/bin/node"] {
            let result = ProvisioningManagedNode.validated(
                reportedVersion: "24.21.0",
                actualExecutablePath: path,
                selector: "24.21.0",
                expectedExecutableURL: expected,
                root: root,
                executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
            )
            #expect(result.node == nil)
            #expect(result.failure?.contains("non-absolute") == true)
        }
    }

    @Test("a selected store symlink into another version is rejected before fnm exec")
    func selectedStoreSymlinkVersionMismatchIsRejectedBeforeExecution() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dev-manager-store-link-\(UUID().uuidString)", isDirectory: true)
        let expected = root.appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        let other = root.appendingPathComponent("node-versions/v22.20.0/installation/bin/node")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: other.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: other.path)
        try fileManager.createSymbolicLink(at: expected, withDestinationURL: other)

        let direct = ProvisioningManagedNode.validated(
            reportedVersion: "24.21.0",
            actualExecutablePath: other.path,
            selector: "24.21.0",
            expectedExecutableURL: expected,
            root: root,
            executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
        )
        #expect(direct.node == nil)
        #expect(direct.failure != nil)

        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-store-link/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, _, _ in
                spy.record(arguments)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "unexpected exec", terminationStatus: 1, timedOut: false)
            },
            filesystemFacts: { _ in
                ProvisioningFNMRootEvidence(
                    hasInstalledInventory: true,
                    inventory: .knownVersions(["24.21.0"]),
                    defaultAlias: .absent,
                    rootReadable: true
                )
            },
            executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) },
            rootEnvironment: ["FNM_DIR": root.path],
            homeDirectory: root.deletingLastPathComponent()
        )
        #expect(spy.calls == [["list"]])
        #expect(selectedContext(observation) == nil)
        #expect(nodeAttention(observation) != nil)
    }

    @Test("one JSON fnm exec serves each candidate and malformed probe results need attention", arguments: [
        "",
        "{}",
        "{\"version\":24,\"execPath\":\"/tmp/node\"}",
        "not JSON"
    ])
    func malformedNodeJSONNeedsAttention(output: String) async {
        let result = await inspectNodeProbe(
            processResult: ProvisioningProcessResult(succeeded: true, stdout: output, stderr: "", terminationStatus: 0, timedOut: false)
        )
        #expect(selectedContext(result.observation) == nil)
        #expect(nodeAttention(result.observation) != nil)
        #expect(result.calls.filter { $0.first == "exec" }.count == 1)
        #expect(result.calls.filter { $0.contains("--version") }.isEmpty)
    }

    @Test("valid JSON probe is one exec and produces a managed context")
    func validJSONProbeIsSingleExec() async {
        let root = URL(fileURLWithPath: "/tmp/dev-manager-json-probe")
        let output = "{\"version\":\"v24.21.0\",\"execPath\":\"\(root.path)/node-versions/v24.21.0/installation/bin/node\"}"
        let result = await inspectNodeProbe(
            processResult: ProvisioningProcessResult(succeeded: true, stdout: output, stderr: "", terminationStatus: 0, timedOut: false)
        )
        #expect(selectedContext(result.observation)?.node.version == "24.21.0")
        #expect(result.calls.filter { $0.first == "exec" }.count == 1)
        #expect(result.calls.filter { isJSONProbe($0) } == [[
            "exec", "--using", "24.21.0", "node", "-p",
            "JSON.stringify({version: process.version, execPath: process.execPath})"
        ]])
    }

    @Test("fnm JSON probe failure and timeout remain attention")
    func nodeJSONProbeFailureAndTimeoutNeedAttention() async {
        for processResult in [
            ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "fnm failed", terminationStatus: 1, timedOut: false),
            ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "", terminationStatus: -1, timedOut: true)
        ] {
            let result = await inspectNodeProbe(processResult: processResult)
            #expect(selectedContext(result.observation) == nil)
            #expect(nodeAttention(result.observation) != nil)
            #expect(result.calls.filter { $0.first == "exec" }.count == 1)
        }
    }

    @Test("real aliases are managed when they resolve inside the fnm store")
    func managedAliasTargetValidation() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dev-manager-fnm-alias-\(UUID().uuidString)", isDirectory: true)
        let storedNode = root
            .appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        let aliasNode = root.appendingPathComponent("aliases/default/bin/node")
        let outsideRoot = root.deletingLastPathComponent()
            .appendingPathComponent("dev-manager-outside-\(UUID().uuidString)", isDirectory: true)
        let outsideNode = outsideRoot.appendingPathComponent("node")
        let outsideAlias = root.appendingPathComponent("aliases/outside/bin/node")
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outsideRoot)
        }

        try fileManager.createDirectory(at: storedNode.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: aliasNode.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideAlias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: storedNode.path, contents: Data()))
        #expect(fileManager.createFile(atPath: outsideNode.path, contents: Data()))
        try fileManager.createSymbolicLink(at: aliasNode, withDestinationURL: storedNode)
        try fileManager.createSymbolicLink(at: outsideAlias, withDestinationURL: outsideNode)

        #expect(ProvisioningRuntimePolicy.isManagedNodeExecutable(aliasNode, within: root))
        #expect(!ProvisioningRuntimePolicy.isManagedNodeExecutable(outsideAlias, within: root))
    }

    @Test("filesystem facts distinguish broken in-root aliases from valid external aliases")
    func defaultAliasFilesystemClassification() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dev-manager-fnm-default-alias-\(UUID().uuidString)", isDirectory: true)
        let brokenRoot = base.appendingPathComponent("broken", isDirectory: true)
        let externalRoot = base.appendingPathComponent("external", isDirectory: true)
        let externalNode = base.appendingPathComponent("system-node", isDirectory: false)
        defer { try? fileManager.removeItem(at: base) }

        let brokenAlias = brokenRoot.appendingPathComponent("aliases/default/bin/node", isDirectory: false)
        let brokenTarget = brokenRoot.appendingPathComponent("node-versions/v24.21.0/installation/bin/node", isDirectory: false)
        let externalAlias = externalRoot.appendingPathComponent("aliases/default/bin/node", isDirectory: false)
        try fileManager.createDirectory(at: brokenAlias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalAlias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: externalNode.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: externalNode.path)
        try fileManager.createSymbolicLink(at: brokenAlias, withDestinationURL: brokenTarget)
        try fileManager.createSymbolicLink(at: externalAlias, withDestinationURL: externalNode)

        let broken = ProvisioningFNMContext.filesystemFacts(at: brokenRoot)
        let external = ProvisioningFNMContext.filesystemFacts(at: externalRoot)
        #expect(broken.defaultAlias == .broken)
        #expect(broken.hasConfiguredDefault)
        #expect(external.defaultAlias == .external)
        #expect(!external.hasConfiguredDefault)
    }

    @Test("fnm's system default is not a managed selector")
    func systemDefaultIsNotSelected() {
        #expect(ProvisioningRuntimePolicy.orderedStableNodeCandidates(defaultVersion: "system", inventory: []).isEmpty)
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
        let homebrewCount = path.split(separator: ":").map(String.init).filter { $0 == "/opt/homebrew/bin" }.count
        #expect(homebrewCount == 1)
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

    @Test("pnpm absence from an empty candidate set remains missing")
    func emptyPnpmCandidateSetIsMissing() {
        let outcome = ProvisioningInspector.PnpmOutcome.missing
        let check = ProvisioningInspector.pnpmCheck(for: outcome, selectedNodeVersion: "24.21.0")
        if case .missing = check.state {
            // Expected: an actually empty candidate set remains installable.
        } else {
            #expect(Bool(false), "An empty pnpm candidate set must be missing")
        }
    }

    @Test("a real pnpm candidate failure stays attention with its concrete path")
    func pnpmCandidateFailureRetainsPath() {
        let path = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let outcome = ProvisioningInspector.PnpmOutcome.unusable(executableURL: path, reason: "exit 1")
        let check = ProvisioningInspector.pnpmCheck(for: outcome, selectedNodeVersion: "24.21.0")

        if case let .attention(detail) = check.state {
            #expect(detail.contains(path.path))
            #expect(detail.contains("exit 1"))
        } else {
            #expect(Bool(false), "A failed real pnpm candidate must need attention")
        }
    }

    @Test("an unknown pnpm probe caused by budget exhaustion is not missing")
    func exhaustedPnpmProbeNeedsAttention() {
        let outcome = ProvisioningInspector.PnpmOutcome.budgetExhausted("Runtime inspection budget exhausted.")
        let check = ProvisioningInspector.pnpmCheck(for: outcome, selectedNodeVersion: "24.21.0")

        if case .attention = check.state {
            // Expected: an unknown result is not an installable absence.
        } else {
            #expect(Bool(false), "Budget exhaustion must need attention")
        }
    }

    @Test("accepted Homebrew pnpm remains ready for selected Node 24.21")
    func acceptedHomebrewPnpmRemainsReady() throws {
        let fixture = try makeValidatedNode()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let context = ProvisioningRuntimeContext(
            node: fixture.node,
            pnpm: nil,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            chosenFNMDirectoryURL: fixture.root
        )
        let path = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let outcome = ProvisioningInspector.PnpmOutcome.ready(ProvisioningPnpmTool(version: "12.6.0", executableURL: path))
        let check = ProvisioningInspector.pnpmCheck(for: outcome, selectedNodeVersion: context.node.version)

        #expect(check.state == .ready("pnpm 12.6.0; path: /opt/homebrew/bin/pnpm; selected Node: 24.21.0"))
    }

    @Test("context normalizes accepted pnpm build metadata while the row keeps the report")
    func contextNormalizesAcceptedPnpmBuildMetadata() throws {
        let fixture = try makeValidatedNode()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let pnpmURL = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let selected = ProvisioningInspector.SelectedRuntime(
            node: fixture.node,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            root: fixture.root,
            pnpm: .ready(ProvisioningPnpmTool(version: "12.6.0+build.7", executableURL: pnpmURL))
        )
        let mapped = ProvisioningInspector.runtimeChecks(for: .selected(selected))
        #expect(mapped.context?.pnpm?.version == "12.6.0")
        #expect(mapped.context?.pnpm?.executableURL == pnpmURL)
        #expect(mapped.context?.hasUsablePnpm == true)
        #expect(mapped.pnpm.state == .ready("pnpm 12.6.0+build.7; path: /opt/homebrew/bin/pnpm; selected Node: 24.21.0"))
    }

    @Test("a readable empty root is an authoritative zero-command absence")
    func emptyRootSkipsAllFNMCommands() async {
        let spy = ProvisioningCommandSpy()
        let home = URL(fileURLWithPath: "/Users/root-policy-empty-only", isDirectory: true)
        let selectedRoot = home.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-spy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, _, _ in
                spy.record(arguments)
                return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "unexpected", terminationStatus: 13, timedOut: false)
            },
            filesystemFacts: { _ in
                ProvisioningFNMRootEvidence(inventory: .knownEmpty, defaultAlias: .absent, rootReadable: true)
            },
            executableAvailable: { _ in false },
            rootEnvironment: [:],
            homeDirectory: home
        )
        #expect(spy.calls.isEmpty)
        #expect(chosenRoot(observation) == selectedRoot)
        #expect(nodeAttention(observation) == nil)
        #expect(selectedContext(observation) == nil)
    }

    @Test("a bad managed candidate is rejected before node or pnpm execution")
    func badCandidateHasNoNodeOrPnpmInvocation() async {
        let spy = ProvisioningCommandSpy()
        let selectedRoot = ProvisioningFNMContext.candidateDataRoots().first
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-spy/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, _, _ in
                spy.record(arguments)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return ProvisioningProcessResult(succeeded: true, stdout: "", stderr: "", terminationStatus: 0, timedOut: false)
            },
            filesystemFacts: { root in
                (selectedRoot.map { $0 == root } ?? false)
                    ? ProvisioningFNMRootEvidence(inventory: .knownVersions(["24.21.0"]), defaultAlias: .absent, rootReadable: true)
                    : ProvisioningFNMRootEvidence(inventory: .knownEmpty, defaultAlias: .absent, rootReadable: true)
            },
            executableAvailable: { _ in false }
        )
        #expect(spy.calls == [["list"]])
        if case .attention = observation {} else { #expect(Bool(false), "A rejected candidate needs an explicit attention outcome") }
        #expect(nodeAttention(observation) != nil)
    }

    @Test("the actual inspector route transitions from no fnm to no Node to managed Node and pnpm")
    func inspectorDecisionRouteCoversSetupStages() async {
        // This is deliberately not a fabricated model: each later state runs
        // the same injected fnm/list/default/exec/pnpm orchestration used by
        // ProvisioningInspector, with no subprocess or host executable probe.
        let noFNM = ProvisioningInspector.runtimeChecksWithoutFNM()
        if case .missing = noFNM.node.state {} else { #expect(Bool(false)) }
        if case .unverified = noFNM.pnpm.state {} else { #expect(Bool(false)) }

        let noNode = await inspectTranscript(.emptyStore)
        let noNodeChecks = ProvisioningInspector.runtimeChecks(for: noNode)
        if case .missing = noNodeChecks.node.state {} else { #expect(Bool(false), "empty fnm inventory is normal missing Node") }
        if case .unverified = noNodeChecks.pnpm.state {} else { #expect(Bool(false)) }

        let managedOnly = ProvisioningInspector.runtimeChecks(for: await inspectTranscript(.managedNode))
        if case .ready = managedOnly.node.state {} else { #expect(Bool(false)) }
        if case .missing = managedOnly.pnpm.state {} else { #expect(Bool(false), "pnpm is not probed before managed Node selection") }

        let working = ProvisioningInspector.runtimeChecks(for: await inspectTranscript(.managedNodeAndHomebrewPnpm))
        if case .ready = working.node.state {} else { #expect(Bool(false)) }
        if case .ready = working.pnpm.state {} else { #expect(Bool(false), "Homebrew pnpm is usable with the selected managed Node") }
        #expect(working.context?.isManagedByFNM == true)
    }

    @Test("absence classification uses inventory and alias facts, not fnm English")
    func changedAbsenceTextIsStillMissingButRealFailureIsAttention() async {
        let empty = await inspectTranscript(.emptyStoreChangedError)
        let emptyChecks = ProvisioningInspector.runtimeChecks(for: empty)
        if case .missing = emptyChecks.node.state {} else { #expect(Bool(false)) }

        let failed = await inspectTranscript(.unexpectedInventoryFailure)
        let failedChecks = ProvisioningInspector.runtimeChecks(for: failed)
        if case .attention = failedChecks.node.state {} else { #expect(Bool(false), "a nonempty/unknown failed inventory is not absence") }

        let malformed = await inspectTranscript(.malformedDefaultAlias)
        let malformedChecks = ProvisioningInspector.runtimeChecks(for: malformed)
        if case .attention = malformedChecks.node.state {} else { #expect(Bool(false), "a broken default alias needs attention") }
    }

    @Test("an unmanaged system default can reuse managed inventory without changing the default")
    func systemDefaultUsesExistingManagedCandidate() async {
        let observation = await inspectTranscript(.systemDefaultWithManagedInventory)
        let checks = ProvisioningInspector.runtimeChecks(for: observation)
        if case let .ready(detail) = checks.node.state {
            #expect(detail.contains("unmanaged default was not changed"))
        } else {
            #expect(Bool(false))
        }
    }

    @Test("configured unsupported default is authoritative and does not fall back")
    func unsupportedConfiguredDefaultDoesNotFallback() async {
        let observation = await inspectTranscript(.unsupportedConfiguredDefault)
        let checks = ProvisioningInspector.runtimeChecks(for: observation)
        if case let .attention(detail) = checks.node.state {
            #expect(detail.contains("outside supported stable majors"))
        } else {
            #expect(Bool(false))
        }
        if case .ready = checks.pnpm.state {} else {
            #expect(Bool(false), "working pnpm is still reported independently")
        }
        #expect(checks.context?.pnpm == nil)
        #expect(checks.context?.hasUsablePnpm == false)
    }

    @Test("inspector skips unsupported pnpm and selects a later supported global candidate")
    func unsupportedPnpmFallsThroughToGlobalCandidate() async {
        let observation = await inspectTranscript(.unsupportedPnpmThenGlobal)
        let checks = ProvisioningInspector.runtimeChecks(for: observation)
        if case .ready = checks.pnpm.state {} else { #expect(Bool(false)) }
        #expect(checks.context?.pnpm?.executableURL.path == "/opt/homebrew/bin/pnpm")
        #expect(checks.context?.hasUsablePnpm == true)
    }

    @Test("a failed pnpm candidate is superseded by budget exhaustion")
    func failedPnpmThenBudgetExhaustionPreservesRanking() async {
        let observation = await inspectTranscript(.pnpmFailureThenBudget)
        if case let .selected(runtime) = observation {
            if case .budgetExhausted = runtime.pnpm {} else { #expect(Bool(false), "budget exhaustion outranks an earlier failed candidate") }
            #expect(runtime.context.pnpm == nil)
        } else {
            #expect(Bool(false), "the managed Node remains selected while pnpm inspection is unknown")
        }
        let checks = ProvisioningInspector.runtimeChecks(for: observation)
        if case .attention = checks.pnpm.state {} else { #expect(Bool(false)) }
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

    private func inspectNodeProbe(processResult: ProvisioningProcessResult) async -> (observation: ProvisioningInspector.RuntimeObservation, calls: [[String]]) {
        let root = URL(fileURLWithPath: "/tmp/dev-manager-json-probe")
        let spy = ProvisioningCommandSpy()
        let observation = await ProvisioningInspector.inspectFNMRuntime(
            using: URL(fileURLWithPath: "/tmp/fnm-json-probe/fnm"),
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, _, _ in
                spy.record(arguments)
                if arguments == ["list"] {
                    return ProvisioningProcessResult(succeeded: true, stdout: "24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                return processResult
            },
            filesystemFacts: { _ in
                ProvisioningFNMRootEvidence(
                    hasInstalledInventory: true,
                    inventory: .knownVersions(["24.21.0"]),
                    defaultAlias: .absent,
                    rootReadable: true
                )
            },
            executableAvailable: { url in
                url.path.contains("/node-versions/") && url.path.hasSuffix("/installation/bin/node")
            },
            rootEnvironment: ["FNM_DIR": root.path],
            homeDirectory: URL(fileURLWithPath: "/tmp/dev-manager-json-home", isDirectory: true)
        )
        return (observation, spy.calls)
    }

    private enum TranscriptStage: Sendable {
        case emptyStore
        case emptyStoreChangedError
        case managedNode
        case managedNodeAndHomebrewPnpm
        case systemDefaultWithManagedInventory
        case unexpectedInventoryFailure
        case malformedDefaultAlias
        case unsupportedConfiguredDefault
        case unsupportedPnpmThenGlobal
        case pnpmFailureThenBudget
    }

    private func inspectTranscript(_ stage: TranscriptStage) async -> ProvisioningInspector.RuntimeObservation {
        let fnm = URL(fileURLWithPath: "/tmp/fnm-transcript/fnm")
        let facts: ProvisioningFNMRootEvidence
        switch stage {
        case .emptyStore, .emptyStoreChangedError, .managedNodeAndHomebrewPnpm, .managedNode, .systemDefaultWithManagedInventory, .unsupportedConfiguredDefault, .unsupportedPnpmThenGlobal, .pnpmFailureThenBudget:
            facts = ProvisioningFNMRootEvidence(
                hasConfiguredDefault: !(stage == .emptyStore || stage == .emptyStoreChangedError || stage == .systemDefaultWithManagedInventory),
                hasInstalledInventory: !(stage == .emptyStore || stage == .emptyStoreChangedError),
                inventory: stage == .emptyStore || stage == .emptyStoreChangedError
                    ? .knownEmpty
                    : .knownVersions(stage == .unsupportedConfiguredDefault ? ["v20.0.0", "v24.21.0"] : ["v24.21.0"]),
                defaultAlias: stage == .emptyStore || stage == .emptyStoreChangedError
                    ? .absent
                    : stage == .systemDefaultWithManagedInventory ? .external : .managed
            )
        case .unexpectedInventoryFailure:
            facts = ProvisioningFNMRootEvidence(inventory: .unknown, defaultAlias: .unknown, rootReadable: false)
        case .malformedDefaultAlias:
            facts = ProvisioningFNMRootEvidence(hasConfiguredDefault: true, inventory: .knownEmpty, defaultAlias: .broken)
        }

        return await ProvisioningInspector.inspectFNMRuntime(
            using: fnm,
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { executable, arguments, environment, _ in
                let root = environment["FNM_DIR"] ?? "/tmp/fnm-transcript"
                let nodePath = root + "/node-versions/v24.21.0/installation/bin/node"
                let unsupportedNodePath = root + "/node-versions/v20.0.0/installation/bin/node"
                switch stage {
                case .emptyStore, .emptyStoreChangedError:
                    if arguments == ["list"] {
                        return ProvisioningProcessResult(succeeded: true, stdout: "* system\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: stage == .emptyStoreChangedError ? "default selection is unavailable" : "nothing configured here", terminationStatus: 1, timedOut: false)
                case .unexpectedInventoryFailure:
                    return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "permission denied while reading local inventory", terminationStatus: 13, timedOut: false)
                case .malformedDefaultAlias:
                    if arguments == ["list"] {
                        return ProvisioningProcessResult(succeeded: true, stdout: "* system\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    return ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "configuration unavailable", terminationStatus: 1, timedOut: false)
                case .managedNode, .managedNodeAndHomebrewPnpm, .systemDefaultWithManagedInventory, .unsupportedConfiguredDefault, .unsupportedPnpmThenGlobal, .pnpmFailureThenBudget:
                    if arguments == ["list"] {
                        let list = stage == .unsupportedConfiguredDefault ? "v20.0.0\nv24.21.0\n" : "* v24.21.0\n"
                        return ProvisioningProcessResult(succeeded: true, stdout: list, stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    if arguments == ["default"] {
                        let selected: String
                        if stage == .systemDefaultWithManagedInventory {
                            selected = "system\n"
                        } else {
                            selected = stage == .unsupportedConfiguredDefault ? "20.0.0\n" : "24.21.0\n"
                        }
                        return ProvisioningProcessResult(succeeded: true, stdout: selected, stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    if isJSONProbe(arguments) {
                        let version = stage == .unsupportedConfiguredDefault ? "v20.0.0" : "v24.21.0"
                        let path = stage == .unsupportedConfiguredDefault ? unsupportedNodePath : nodePath
                        return ProvisioningProcessResult(succeeded: true, stdout: "{\"version\":\"" + version + "\",\"execPath\":\"" + path + "\"}\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    if arguments == ["--version"] {
                        if stage == .unsupportedPnpmThenGlobal {
                            let version = executable.path.hasSuffix("/installation/bin/pnpm") ? "9.0.0\n" : "12.6.0\n"
                            return ProvisioningProcessResult(succeeded: true, stdout: version, stderr: "", terminationStatus: 0, timedOut: false)
                        }
                        if stage == .pnpmFailureThenBudget {
                            return executable.path.hasSuffix("/installation/bin/pnpm")
                                ? ProvisioningProcessResult(succeeded: false, stdout: "", stderr: "pnpm failed", terminationStatus: 1, timedOut: false)
                                : nil
                        }
                        return ProvisioningProcessResult(succeeded: true, stdout: "12.6.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    return nil
                }
            },
            filesystemFacts: { _ in facts },
            executableAvailable: { url in
                if url.path == "/opt/homebrew/bin/pnpm" {
                    return stage == .managedNodeAndHomebrewPnpm || stage == .unsupportedConfiguredDefault || stage == .unsupportedPnpmThenGlobal || stage == .pnpmFailureThenBudget
                }
                if (stage == .unsupportedPnpmThenGlobal || stage == .pnpmFailureThenBudget),
                   url.path.hasSuffix("/installation/bin/pnpm") {
                    return true
                }
                // The injected spy represents concrete managed Node files as
                // executable; production uses FileManager for the same check.
                return url.path.contains("/node-versions/") && url.path.hasSuffix("/installation/bin/node")
            }
        )
    }
}

private func makeValidatedNode(version: String = "24.21.0") throws -> (node: ProvisioningManagedNode, root: URL) {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("dev-manager-managed-node-\(version)-\(UUID().uuidString)", isDirectory: true)
    let expected = root.appendingPathComponent("node-versions/v\(version)/installation/bin/node")
    try fileManager.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard fileManager.createFile(atPath: expected.path, contents: Data()) else {
        throw NSError(domain: "ProvisioningRuntimePolicyTests", code: 1)
    }
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: expected.path)
    let result = ProvisioningManagedNode.validated(
        reportedVersion: "v\(version)",
        actualExecutablePath: expected.path,
        selector: "v\(version)",
        expectedExecutableURL: expected,
        root: root,
        executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
    )
    guard let node = result.node else {
        throw NSError(domain: "ProvisioningRuntimePolicyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: result.failure ?? "validation failed"])
    }
    return (node, root)
}

private func chosenRoot(_ observation: ProvisioningInspector.RuntimeObservation) -> URL? {
    switch observation {
    case let .missing(root, _), let .attention(root, _): return root
    case let .selected(runtime): return runtime.root
    }
}

private func selectedContext(_ observation: ProvisioningInspector.RuntimeObservation) -> ProvisioningRuntimeContext? {
    if case let .selected(runtime) = observation { return runtime.context }
    return nil
}

private func nodeAttention(_ observation: ProvisioningInspector.RuntimeObservation) -> String? {
    switch observation {
    case let .attention(_, reason): return reason
    case let .selected(runtime): return runtime.attention
    case .missing: return nil
    }
}
#endif
