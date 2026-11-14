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
                    defaultAlias: .external,
                    inventory: .knownEmpty
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
        #expect(observation.chosenFNMDirectoryURL == selected)
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
                if arguments.contains("--version") && arguments.contains("node") {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if arguments.contains("process.execPath") {
                    return ProvisioningProcessResult(succeeded: true, stdout: root.path + "/node-versions/v24.21.0/installation/bin/node\n", stderr: "", terminationStatus: 0, timedOut: false)
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
        #expect(observation.chosenFNMDirectoryURL == selected)
        #expect(observation.nodeContext?.nodeVersion == "24.21.0")
        #expect(!spy.calls.isEmpty)
        #expect(Set(spy.roots) == Set([selected.path]))
        #expect(observation.nodeAttention?.contains("could not be read") == true)
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
                if arguments.contains("--version") && arguments.contains("node") {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if arguments.contains("process.execPath") {
                    return ProvisioningProcessResult(succeeded: true, stdout: root.path + "/node-versions/v24.21.0/installation/bin/node\n", stderr: "", terminationStatus: 0, timedOut: false)
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
        #expect(observation.chosenFNMDirectoryURL == legacy)
        #expect(observation.nodeContext?.nodeVersion == "24.21.0")
        #expect(observation.nodeContext?.nodeExecutableURL.path == legacy.path + "/node-versions/v24.21.0/installation/bin/node")
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
                if arguments.contains("--version") && arguments.contains("node") {
                    let version = kind == "unsupported" && root == selected ? "v20.0.0" : "v24.21.0"
                    return ProvisioningProcessResult(succeeded: true, stdout: version + "\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if arguments.contains("process.execPath") {
                    let version = kind == "unsupported" && root == selected ? "v20.0.0" : "v24.21.0"
                    return ProvisioningProcessResult(succeeded: true, stdout: root.path + "/node-versions/" + version + "/installation/bin/node\n", stderr: "", terminationStatus: 0, timedOut: false)
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
        #expect(observation.chosenFNMDirectoryURL == selected)
        #expect(!spy.calls.isEmpty)
        #expect(Set(spy.roots) == Set([selected.path]))
        if kind == "unsupported" {
            #expect(observation.nodeContext?.nodeVersion == "20.0.0")
            #expect(observation.nodeAttention?.contains("outside supported stable majors") == true)
        } else {
            #expect(observation.nodeContext == nil)
            #expect(observation.nodeAttention != nil)
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
                if arguments.contains("--version") && arguments.contains("node") {
                    return ProvisioningProcessResult(succeeded: true, stdout: "v24.21.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                }
                if arguments.contains("process.execPath") {
                    return ProvisioningProcessResult(succeeded: true, stdout: root.path + "/node-versions/v24.21.0/installation/bin/node\n", stderr: "", terminationStatus: 0, timedOut: false)
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
        #expect(observation.chosenFNMDirectoryURL == selected)
        #expect(spy.calls == [["default"]])
        #expect(Set(spy.roots) == Set([selected.path]))
        #expect(observation.nodeContext == nil)
        #expect(observation.nodeAttention?.contains("no executable") == true)
    }

    @Test("a managed fnm Node remains selected when pnpm is missing")
    func managedNodeRemainsSelectedWhenPnpmIsMissing() {
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
        #expect(context.chosenFNMDirectoryURL.path == "/Users/test/.local/share/fnm")
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
        let externalContext = ProvisioningRuntimeContext(
            nodeVersion: "24.21.0",
            nodeExecutableURL: URL(fileURLWithPath: "/usr/local/bin/node"),
            pnpmVersion: nil,
            pnpmExecutableURL: nil,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            chosenFNMDirectoryURL: root
        )
        #expect(!externalContext.isManagedByFNM)
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
        let observation = ProvisioningInspector.PnpmObservation.noCandidate
        let check = ProvisioningInspector.pnpmCheck(for: nil, observed: observation)

        #expect(observation.executableURL == nil)
        #expect(observation.failure == nil)
        #expect(!observation.foundExecutable)
        if case .missing = check.state {
            // Expected: an actually empty candidate set remains installable.
        } else {
            #expect(Bool(false), "An empty pnpm candidate set must be missing")
        }
    }

    @Test("a real pnpm candidate failure stays attention with its concrete path")
    func pnpmCandidateFailureRetainsPath() {
        let path = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let observation = ProvisioningInspector.PnpmObservation(
            version: nil,
            executableURL: path,
            failure: "exit 1",
            foundExecutable: true
        )
        let check = ProvisioningInspector.pnpmCheck(for: nil, observed: observation)

        if case let .attention(detail) = check.state {
            #expect(detail.contains(path.path))
            #expect(detail.contains("exit 1"))
        } else {
            #expect(Bool(false), "A failed real pnpm candidate must need attention")
        }
    }

    @Test("an unknown pnpm probe caused by budget exhaustion is not missing")
    func exhaustedPnpmProbeNeedsAttention() {
        let observation = ProvisioningInspector.PnpmObservation(
            version: nil,
            executableURL: nil,
            failure: "Runtime inspection budget exhausted.",
            foundExecutable: false,
            budgetExhausted: true
        )
        let check = ProvisioningInspector.pnpmCheck(for: nil, observed: observation)

        if case .attention = check.state {
            // Expected: an unknown result is not an installable absence.
        } else {
            #expect(Bool(false), "Budget exhaustion must need attention")
        }
    }

    @Test("accepted Homebrew pnpm remains ready for selected Node 24.21")
    func acceptedHomebrewPnpmRemainsReady() {
        let context = ProvisioningRuntimeContext(
            nodeVersion: "24.21.0",
            nodeExecutableURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm/node-versions/v24.21.0/installation/bin/node"),
            pnpmVersion: nil,
            pnpmExecutableURL: nil,
            fnmExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            fnmSelector: "24.21.0",
            chosenFNMDirectoryURL: URL(fileURLWithPath: "/Users/test/.local/share/fnm", isDirectory: true)
        )
        let path = URL(fileURLWithPath: "/opt/homebrew/bin/pnpm")
        let observation = ProvisioningInspector.PnpmObservation(
            version: "12.6.0",
            executableURL: path,
            failure: nil,
            foundExecutable: true
        )
        let check = ProvisioningInspector.pnpmCheck(for: context, observed: observation)

        #expect(check.state == .ready("pnpm 12.6.0; path: /opt/homebrew/bin/pnpm; selected Node: 24.21.0"))
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
        #expect(observation.chosenFNMDirectoryURL == selectedRoot)
        #expect(observation.nodeAttention == nil)
        #expect(observation.nodeContext == nil)
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
        #expect(observation.nodeContext == nil)
        #expect(observation.pnpmObservation == nil)
        #expect(observation.nodeAttention != nil)
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

    private enum TranscriptStage: Sendable {
        case emptyStore
        case emptyStoreChangedError
        case managedNode
        case managedNodeAndHomebrewPnpm
        case systemDefaultWithManagedInventory
        case unexpectedInventoryFailure
        case malformedDefaultAlias
        case unsupportedConfiguredDefault
    }

    private func inspectTranscript(_ stage: TranscriptStage) async -> ProvisioningInspector.RuntimeObservation {
        let fnm = URL(fileURLWithPath: "/tmp/fnm-transcript/fnm")
        let facts: ProvisioningFNMRootEvidence
        switch stage {
        case .emptyStore, .emptyStoreChangedError, .managedNodeAndHomebrewPnpm, .managedNode, .systemDefaultWithManagedInventory, .unsupportedConfiguredDefault:
            facts = ProvisioningFNMRootEvidence(
                hasConfiguredDefault: !(stage == .emptyStore || stage == .emptyStoreChangedError || stage == .systemDefaultWithManagedInventory),
                hasInstalledInventory: !(stage == .emptyStore || stage == .emptyStoreChangedError),
                inventory: stage == .emptyStore || stage == .emptyStoreChangedError
                    ? .knownEmpty
                    : .knownVersions(stage == .unsupportedConfiguredDefault ? ["v20.0.0", "v24.21.0"] : ["v24.21.0"]),
                defaultAlias: stage == .emptyStore || stage == .emptyStoreChangedError || stage == .systemDefaultWithManagedInventory ? .absent : .managed
            )
        case .unexpectedInventoryFailure:
            facts = ProvisioningFNMRootEvidence(inventory: .unknown, defaultAlias: .unknown, rootReadable: false)
        case .malformedDefaultAlias:
            facts = ProvisioningFNMRootEvidence(hasConfiguredDefault: true, inventory: .knownEmpty, defaultAlias: .broken)
        }

        return await ProvisioningInspector.inspectFNMRuntime(
            using: fnm,
            budget: ProvisioningInspector.RuntimeInspectionBudget(),
            run: { _, arguments, environment, _ in
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
                case .managedNode, .managedNodeAndHomebrewPnpm, .systemDefaultWithManagedInventory, .unsupportedConfiguredDefault:
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
                    if arguments.contains("--version") && arguments.contains("node") {
                        let version = stage == .unsupportedConfiguredDefault ? "v20.0.0\n" : "v24.21.0\n"
                        return ProvisioningProcessResult(succeeded: true, stdout: version, stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    if arguments.contains("process.execPath") {
                        let path = stage == .unsupportedConfiguredDefault ? unsupportedNodePath : nodePath
                        return ProvisioningProcessResult(succeeded: true, stdout: path + "\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    if arguments == ["--version"] {
                        return ProvisioningProcessResult(succeeded: true, stdout: "12.6.0\n", stderr: "", terminationStatus: 0, timedOut: false)
                    }
                    return nil
                }
            },
            filesystemFacts: { _ in facts },
            executableAvailable: { url in
                if url.path == "/opt/homebrew/bin/pnpm" {
                    return stage == .managedNodeAndHomebrewPnpm
                }
                // The injected spy represents concrete managed Node files as
                // executable; production uses FileManager for the same check.
                return url.path.contains("/node-versions/") && url.path.hasSuffix("/installation/bin/node")
            }
        )
    }
}
#endif
