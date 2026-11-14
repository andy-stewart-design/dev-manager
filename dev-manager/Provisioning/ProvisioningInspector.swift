import Darwin
import Foundation

nonisolated enum ProvisioningInspector {
    nonisolated static func inspect() async -> ProvisioningInspection {
        let developerTools = await checkDeveloperTools()
        let homebrew = await checkHomebrew()
        let fnm = await checkFNM()
        let runtime = await checkRuntime(
            using: fnm.executableURL,
            fnmInspectionFailed: fnm.check.state.isAttention
        )
        let fnmCheck = makeFNMCheck(for: fnm)
        return ProvisioningInspection(
            developerTools: developerTools.check,
            developerToolsExecutableURL: developerTools.executableURL,
            homebrew: homebrew.check,
            fnm: fnmCheck,
            fnmExecutableURL: fnm.executableURL,
            chosenFNMDirectoryURL: runtime.chosenFNMDirectoryURL,
            node: runtime.node,
            pnpm: runtime.pnpm,
            runtimeContext: runtime.context
        )
    }

    nonisolated static func inspect(target id: ProvisioningCheck.ID) async -> ProvisioningTargetedInspection {
        switch id {
        case .developerTools:
            let result = await checkDeveloperTools()
            return ProvisioningTargetedInspection(checks: [result.check], fnmExecutableURL: nil, runtimeContext: nil)
        case .homebrew:
            let result = await checkHomebrew()
            return ProvisioningTargetedInspection(checks: [result.check], fnmExecutableURL: nil, runtimeContext: nil)
        case .fnm, .node, .pnpm:
            // Runtime rows refresh one bounded, coherent context. A failed refresh
            // never leaves the model with the previous context.
            let fnm = await checkFNM()
            let runtime = await checkRuntime(
                using: fnm.executableURL,
                fnmInspectionFailed: fnm.check.state.isAttention
            )
            return ProvisioningTargetedInspection(
                checks: [makeFNMCheck(for: fnm), runtime.node, runtime.pnpm],
                fnmExecutableURL: fnm.executableURL,
                chosenFNMDirectoryURL: runtime.chosenFNMDirectoryURL,
                runtimeContext: runtime.context
            )
        }
    }

    private nonisolated static func checkDeveloperTools() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let selector = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["-p"])
        guard selector.succeeded, let selectedPath = selector.stdout.firstNonEmptyLine else {
            if selector.timedOut {
                return (ProvisioningCheck(id: .developerTools, state: .attention(selector.failureDescription(for: "xcode-select", timeout: ProvisioningConfiguration.commandTimeout))), nil)
            }
            return (ProvisioningCheck(id: .developerTools, state: .missing("No usable developer tools are selected. Request Apple's graphical installer, then Check again.")), nil)
        }

        let clang = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "clang"])
        guard clang.succeeded, let clangPath = clang.stdout.firstNonEmptyLine else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("Selected tools at \(selectedPath) are not usable: \(clang.failureDescription(for: "xcrun --find clang", timeout: ProvisioningConfiguration.commandTimeout))")), nil)
        }

        let sdk = await ProvisioningCommandRunner.run(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--sdk", "macosx", "--show-sdk-path"])
        guard sdk.succeeded else {
            return (ProvisioningCheck(id: .developerTools, state: .attention("clang is at \(clangPath), but the macOS SDK check failed: \(sdk.failureDescription(for: "xcrun --show-sdk-path", timeout: ProvisioningConfiguration.commandTimeout))")), nil)
        }

        return (ProvisioningCheck(id: .developerTools, state: .ready("Selected: \(selectedPath); clang: \(clangPath)")), URL(fileURLWithPath: clangPath))
    }

    private nonisolated static func checkHomebrew() async -> (check: ProvisioningCheck, executableURL: URL?) {
        let brew = ProvisioningConfiguration.homebrewURL
        guard FileManager.default.isExecutableFile(atPath: brew.path) else {
            return (ProvisioningCheck(id: .homebrew, state: .missing("Homebrew was not found at /opt/homebrew/bin/brew.")), nil)
        }

        let result = await ProvisioningCommandRunner.run(brew, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .homebrew, state: .attention("Found \(brew.path), but it did not run as the current user: \(result.failureDescription(for: "brew --version", timeout: ProvisioningConfiguration.commandTimeout))")), brew)
        }
        return (ProvisioningCheck(id: .homebrew, state: .ready("\(result.stdout.firstNonEmptyLine ?? brew.path); \(brew.path) ran as the current user")), brew)
    }

    private nonisolated static func makeFNMCheck(
        for result: (check: ProvisioningCheck, executableURL: URL?)
    ) -> ProvisioningCheck {
        // fnm is the required runtime backend. A usable external Node never
        // changes this row to an optional/satisfied state.
        result.check
    }

    private nonisolated static func checkFNM() async -> (check: ProvisioningCheck, executableURL: URL?) {
        guard let fnm = firstExecutable(named: "fnm", extra: [
            URL(fileURLWithPath: "/opt/homebrew/bin/fnm"),
            URL(fileURLWithPath: "/usr/local/bin/fnm"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/fnm"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/fnm/fnm"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".fnm/fnm")
        ]) else {
            return (ProvisioningCheck(id: .fnm, state: .missing("fnm was not found in the GUI PATH or standard locations; no shell files were sourced.")), nil)
        }

        let result = await ProvisioningCommandRunner.run(fnm, arguments: ["--version"])
        guard result.succeeded else {
            return (ProvisioningCheck(id: .fnm, state: .attention("Found \(fnm.path), but it did not run as the current user: \(result.failureDescription(for: "fnm --version", timeout: ProvisioningConfiguration.commandTimeout))")), nil)
        }
        return (ProvisioningCheck(id: .fnm, state: .ready("\(result.stdout.firstNonEmptyLine ?? "fnm") at \(fnm.path)")), fnm)
    }

    nonisolated static func runtimeChecksWithoutFNM(fnmInspectionFailed: Bool = false) -> (node: ProvisioningCheck, pnpm: ProvisioningCheck) {
        if fnmInspectionFailed {
            return (
                ProvisioningCheck(id: .node, state: .unverified("fnm could not be verified, so a managed Node was not checked.")),
                ProvisioningCheck(id: .pnpm, state: .unverified("A managed Node could not be verified because fnm inspection failed."))
            )
        }
        return (
            ProvisioningCheck(id: .node, state: .missing("No managed Node can be checked until fnm is installed and verified.")),
            ProvisioningCheck(id: .pnpm, state: .unverified("A managed Node is required before pnpm can be checked or installed."))
        )
    }

    private nonisolated static func checkRuntime(
        using fnmURL: URL?,
        fnmInspectionFailed: Bool
    ) async -> (node: ProvisioningCheck, pnpm: ProvisioningCheck, context: ProvisioningRuntimeContext?, chosenFNMDirectoryURL: URL?) {
        guard let fnmURL else {
            // An external Node is intentionally not inspected. A missing fnm is
            // a setup prerequisite, not an external-installer handoff.
            let checks = runtimeChecksWithoutFNM(fnmInspectionFailed: fnmInspectionFailed)
            return (checks.node, checks.pnpm, nil, nil)
        }

        let budget = RuntimeInspectionBudget()
        let fnmResult = await inspectFNMRuntime(using: fnmURL, budget: budget)
        return runtimeChecks(for: fnmResult)
    }

    /// Maps the inspector's three-way runtime decision to rows. Keeping this
    /// beside the injected orchestration lets tests exercise the same route as
    /// production without launching fnm or probing a host executable.
    nonisolated static func runtimeChecks(for observation: RuntimeObservation) -> (
        node: ProvisioningCheck,
        pnpm: ProvisioningCheck,
        context: ProvisioningRuntimeContext?,
        chosenFNMDirectoryURL: URL?
    ) {
        if let nodeContext = observation.nodeContext {
            let node: ProvisioningCheck
            if let attention = observation.nodeAttention {
                node = ProvisioningCheck(id: .node, state: .attention(attention))
            } else {
                let detail = nodeDetail(for: nodeContext) + (observation.nodeNote.map { "; \($0)" } ?? "")
                node = ProvisioningCheck(id: .node, state: .ready(detail))
            }
            let pnpm = pnpmCheck(for: nodeContext, observed: observation.pnpmObservation)
            return (node, pnpm, observation.pair ?? nodeContext, observation.chosenFNMDirectoryURL)
        }

        let node: ProvisioningCheck
        if let attention = observation.nodeAttention {
            node = ProvisioningCheck(id: .node, state: .attention(attention))
        } else {
            node = ProvisioningCheck(id: .node, state: .missing("No supported managed Node was found in fnm. A new install targets Node \(ProvisioningRuntimePolicy.recommendedNodeVersion); supported stable majors are 22, 24, and 26."))
        }
        return (
            node,
            ProvisioningCheck(id: .pnpm, state: .unverified("A managed Node is required before pnpm can be checked or installed.")),
            nil,
            observation.chosenFNMDirectoryURL
        )
    }

    nonisolated struct RuntimeInspectionBudget: Sendable {
        let deadline: Date

        init() {
            deadline = Date().addingTimeInterval(ProvisioningConfiguration.runtimeInspectionBudget)
        }

        var remainingTimeout: TimeInterval? {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            return min(ProvisioningConfiguration.commandTimeout, remaining)
        }
    }

    nonisolated struct RuntimeObservation {
        let pair: ProvisioningRuntimeContext?
        let nodeContext: ProvisioningRuntimeContext?
        let pnpmObservation: PnpmObservation?
        let nodeAttention: String?
        let nodeNote: String?
        let chosenFNMDirectoryURL: URL?

        init(
            pair: ProvisioningRuntimeContext?,
            nodeContext: ProvisioningRuntimeContext?,
            pnpmObservation: PnpmObservation?,
            nodeAttention: String?,
            nodeNote: String? = nil,
            chosenFNMDirectoryURL: URL? = nil
        ) {
            self.pair = pair
            self.nodeContext = nodeContext
            self.pnpmObservation = pnpmObservation
            self.nodeAttention = nodeAttention
            self.nodeNote = nodeNote
            self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
        }
    }

    nonisolated struct PnpmObservation {
        let version: String?
        let executableURL: URL?
        let failure: String?
        let foundExecutable: Bool
        let budgetExhausted: Bool

        init(version: String?, executableURL: URL?, failure: String?, foundExecutable: Bool, budgetExhausted: Bool = false) {
            self.version = version
            self.executableURL = executableURL
            self.failure = failure
            self.foundExecutable = foundExecutable
            self.budgetExhausted = budgetExhausted
        }

        nonisolated static var noCandidate: PnpmObservation {
            PnpmObservation(version: nil, executableURL: nil, failure: nil, foundExecutable: false)
        }
    }

    private nonisolated static func runtimeProbe(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String],
        budget: RuntimeInspectionBudget
    ) async -> ProvisioningProcessResult? {
        guard let timeout = budget.remainingTimeout else { return nil }
        return await ProvisioningCommandRunner.run(executableURL, arguments: arguments, environment: environment, timeout: timeout)
    }

    nonisolated enum FNMDefaultState: Equatable, Sendable {
        case unknown
        case absent
        case managed(String)
        case unmanaged
        case broken
    }

    private nonisolated enum InventoryProbeState {
        case knownEmpty
        case knownVersions
        case unavailable
    }

    private nonisolated struct FNMRootProbe {
        let root: URL
        let inventory: InventoryProbeState
        let inventoryVersions: [String]
        let defaultState: FNMDefaultState
        let filesystemFacts: ProvisioningFNMRootEvidence
        let attention: String?
    }

    private nonisolated static func managedInventoryVersions(from output: String) -> [String] {
        var versions = [String]()
        for token in output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
            let value = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard ProvisioningRuntimePolicy.major(of: value) != nil,
                  ProvisioningRuntimePolicy.normalizedVersion(value) != nil,
                  !versions.contains(value) else { continue }
            versions.append(value)
        }
        return versions
    }

    private nonisolated static func listFailure(_ result: ProvisioningProcessResult) -> String {
        "fnm's local Node inventory could not be inspected: \(result.failureDescription(for: "fnm list", timeout: ProvisioningConfiguration.commandTimeout))"
    }

    private nonisolated static func defaultState(
        _ result: ProvisioningProcessResult,
        filesystemFacts: ProvisioningFNMRootEvidence
    ) -> FNMDefaultState {
        if result.succeeded {
            guard let first = result.stdout.firstNonEmptyLine,
                  let token = first.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .first(where: { $0 != "*" })
                    .map(String.init) else {
                return .broken
            }
            let lowered = token.lowercased()
            if lowered == "system" || lowered == "external" || filesystemFacts.defaultAlias == .external { return .unmanaged }
            guard ProvisioningRuntimePolicy.normalizedVersion(token) != nil else { return .broken }
            return .managed(token.hasPrefix("v") ? String(token.dropFirst()) : token)
        }
        if result.timedOut || result.terminationStatus == -1 { return .unknown }
        switch filesystemFacts.defaultAlias {
        case .absent:
            return .unknown
        case .managed:
            return .unknown
        case .external:
            return .unmanaged
        case .broken, .unknown:
            return .broken
        }
    }

    private nonisolated static func inspectFNMRuntime(using fnmURL: URL?, budget: RuntimeInspectionBudget) async -> RuntimeObservation {
        await inspectFNMRuntime(
            using: fnmURL,
            budget: budget,
            run: { executable, arguments, environment, timeout in
                await runtimeProbe(executable, arguments: arguments, environment: environment, budget: budget)
            },
            filesystemFacts: { ProvisioningFNMContext.filesystemFacts(at: $0) },
            executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
        )
    }

    /// The same orchestration used by production inspection, with only command
    /// execution and bounded filesystem facts injected for deterministic tests.
    nonisolated static func inspectFNMRuntime(
        using fnmURL: URL?,
        budget: RuntimeInspectionBudget,
        run: @escaping @Sendable (URL, [String], [String: String], TimeInterval) async -> ProvisioningProcessResult?,
        filesystemFacts: @escaping @Sendable (URL) -> ProvisioningFNMRootEvidence,
        executableAvailable: @escaping @Sendable (URL) -> Bool,
        rootEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) async -> RuntimeObservation {
        guard let fnmURL else { return RuntimeObservation(pair: nil, nodeContext: nil, pnpmObservation: nil, nodeAttention: nil) }

        // Discover every legitimate root and collect bounded evidence before
        // selecting one. Root precedence is explicit and authoritative: an
        // explicit FNM_DIR or XDG root is exclusive; otherwise filesystem
        // evidence ranks the implicit roots. Probing never crosses that choice.
        let initialRoots = ProvisioningFNMContext.candidateDataRoots(
            environment: rootEnvironment,
            homeDirectory: homeDirectory
        )
        let evidence = Dictionary(uniqueKeysWithValues: initialRoots.map { ($0, filesystemFacts($0)) })
        guard let authoritativeRoot = ProvisioningFNMContext.authoritativeDataRoot(
            environment: rootEnvironment,
            homeDirectory: homeDirectory,
            evidence: evidence
        ) else {
            return RuntimeObservation(
                pair: nil,
                nodeContext: nil,
                pnpmObservation: nil,
                nodeAttention: "Could not discover an fnm data root."
            )
        }
        let roots = [authoritativeRoot]
        var probes = [FNMRootProbe]()
        var budgetExhausted = false
        var firstAttention: String?

        // Every fnm command is scoped to exactly one candidate root. This avoids
        // the GUI process environment or fnm's own default leaking across roots.
        for root in roots {
            let environment = ProvisioningFNMContext.environment(
                basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
                root: root
            )
            let facts = filesystemFacts(root)
            let filesystemVersions: [String]
            if case let .knownVersions(versions) = facts.inventory { filesystemVersions = versions } else { filesystemVersions = [] }
            let knownEmptyAbsent = facts.rootReadable && facts.defaultAlias == .absent && {
                if case .knownEmpty = facts.inventory { return true }
                return false
            }()
            // A readable empty root is authoritative normal absence. In
            // particular, do not turn fnm's empty-store/default wording into a
            // command failure, and do not spend CLI probes on a proven-empty root.
            if knownEmptyAbsent {
                probes.append(FNMRootProbe(root: root, inventory: .knownEmpty, inventoryVersions: [], defaultState: .absent, filesystemFacts: facts, attention: nil))
                continue
            }

            let hasKnownManagedDefault = facts.defaultAlias == .managed
            var inventoryState: InventoryProbeState = filesystemVersions.isEmpty ? .knownEmpty : .knownVersions
            var inventoryVersions = filesystemVersions
            var rootAttention: String?

            if !hasKnownManagedDefault {
                guard let inventoryResult = await run(fnmURL, ["list"], environment, budget.remainingTimeout ?? 0) else {
                    budgetExhausted = true
                    rootAttention = "fnm's Node inventory check timed out before the local root could be inspected."
                    let state: FNMDefaultState = {
                        switch facts.defaultAlias {
                        case .absent: return .absent
                        case .broken: return .broken
                        default: return .unknown
                        }
                    }()
                    probes.append(FNMRootProbe(root: root, inventory: .unavailable, inventoryVersions: inventoryVersions, defaultState: state, filesystemFacts: facts, attention: rootAttention))
                    break
                }
                if inventoryResult.succeeded {
                    let listed = managedInventoryVersions(from: inventoryResult.stdout)
                    if !listed.isEmpty { inventoryVersions = listed }
                    inventoryState = inventoryVersions.isEmpty ? .knownEmpty : .knownVersions
                } else {
                    inventoryState = .unavailable
                    rootAttention = listFailure(inventoryResult)
                    if inventoryResult.timedOut || inventoryResult.terminationStatus == -1 || budget.remainingTimeout == nil { budgetExhausted = true }
                }
            }

            let state: FNMDefaultState
            if facts.defaultAlias == .absent {
                // Filesystem facts establish an absent default even when an
                // inventory command is needed to select an existing version.
                state = .absent
            } else if facts.defaultAlias == .external {
                // An outside-store alias is already authoritatively unmanaged;
                // do not turn an unnecessary default rendering into a warning.
                state = .unmanaged
            } else if facts.defaultAlias == .broken {
                // A present broken alias is not absence. Do not let a successful
                // or failed human-oriented fnm rendering turn it into a reason
                // to select another installed version.
                state = .broken
                rootAttention = rootAttention ?? "fnm's configured default is malformed or points outside its managed store."
            } else {
                guard let defaultProbe = await run(fnmURL, ["default"], environment, budget.remainingTimeout ?? 0) else {
                    budgetExhausted = true
                    rootAttention = rootAttention ?? "fnm's default Node check timed out before the local root could be inspected."
                    probes.append(FNMRootProbe(root: root, inventory: inventoryState, inventoryVersions: inventoryVersions, defaultState: .unknown, filesystemFacts: facts, attention: rootAttention))
                    break
                }
                state = defaultState(defaultProbe, filesystemFacts: facts)
                if case .unknown = state {
                    if defaultProbe.timedOut || budget.remainingTimeout == nil { budgetExhausted = true }
                    rootAttention = rootAttention ?? "fnm's default Node check could not be resolved: \(defaultProbe.failureDescription(for: "fnm default", timeout: ProvisioningConfiguration.commandTimeout))"
                } else if case .broken = state {
                    rootAttention = rootAttention ?? "fnm's configured default is malformed or points outside its managed store."
                }
            }
            if case .incomplete = facts.inventory, rootAttention == nil {
                rootAttention = "fnm's local node-versions store contains an incomplete or malformed installation."
            } else if case .unknown = facts.inventory, rootAttention == nil {
                rootAttention = "fnm's local node-versions store could not be read."
            } else if !facts.rootReadable, rootAttention == nil {
                rootAttention = "fnm's selected data root could not be read."
            }
            if case .unknown = facts.defaultAlias, rootAttention == nil {
                rootAttention = "fnm's default alias could not be read."
            }
            probes.append(FNMRootProbe(root: root, inventory: inventoryState, inventoryVersions: inventoryVersions, defaultState: state, filesystemFacts: facts, attention: rootAttention))
        }

        guard !probes.isEmpty else {
            let detail = firstAttention ?? (budgetExhausted
                ? "Runtime inspection budget exhausted before fnm's local Node roots could be checked."
                : "Could not inspect fnm's local Node roots.")
            return RuntimeObservation(pair: nil, nodeContext: nil, pnpmObservation: nil, nodeAttention: detail, chosenFNMDirectoryURL: roots.first)
        }

        var fallbackProbe: FNMRootProbe?
        var firstNode: ProvisioningRuntimeContext?
        var bestPnpm: PnpmObservation?
        var hadUnusableSupportedNode = false
        var hadConfiguredDefaultFailure = false

        // A concrete, working configured default wins over every inventory
        // candidate. A broken configured default is attention, never a reason
        // to silently choose another installed version.
        for probe in probes {
            guard case let .managed(selector) = probe.defaultState else {
                if case .unknown = probe.defaultState { hadConfiguredDefaultFailure = true }
                if case .broken = probe.defaultState { hadConfiguredDefaultFailure = true }
                continue
            }
            let environment = ProvisioningFNMContext.environment(
                basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
                root: probe.root
            )
            let nodeProbe = await probeFNMNode(using: fnmURL, selector: selector, root: probe.root, environment: environment, budget: budget, run: run, executableAvailable: executableAvailable)
            guard let node = nodeProbe.probe else {
                hadConfiguredDefaultFailure = true
                if nodeProbe.budgetExhausted { budgetExhausted = true }
                if let failure = nodeProbe.failure { firstAttention = firstAttention ?? failure }
                continue
            }
            guard ProvisioningRuntimePolicy.isManagedNodeExecutable(node.executableURL, within: probe.root) else {
                firstAttention = firstAttention ?? "fnm's configured default resolved to a Node outside its managed node-versions store."
                continue
            }
            let context = ProvisioningRuntimeContext(
                nodeVersion: node.version,
                nodeExecutableURL: node.executableURL,
                pnpmVersion: nil,
                pnpmExecutableURL: nil,
                fnmExecutableURL: fnmURL,
                fnmSelector: selector,
                chosenFNMDirectoryURL: probe.root
            )
            let observation = await probePnpm(
                root: probe.root,
                selectedNodeURL: node.executableURL,
                budget: budget,
                run: run,
                executableAvailable: executableAvailable
            )
            bestPnpm = betterPnpmObservation(bestPnpm, observation)
            let nodeAttention: String?
            let unsupportedDefaultAttention: String? = ProvisioningRuntimePolicy.isSupportedNodeVersion(node.version)
                ? nil
                : "fnm's configured default is Node \(node.version), outside supported stable majors 22, 24, and 26; it was not replaced."
            let combinedAttention = [probe.attention, unsupportedDefaultAttention]
                .compactMap { $0 }
                .joined(separator: "; ")
            nodeAttention = combinedAttention.isEmpty ? nil : combinedAttention
            if let pnpmVersion = observation.version, let pnpmURL = observation.executableURL,
               ProvisioningRuntimePolicy.supportsPair(nodeVersion: context.nodeVersion, pnpmVersion: pnpmVersion) {
                return RuntimeObservation(
                    pair: ProvisioningRuntimeContext(
                        nodeVersion: context.nodeVersion,
                        nodeExecutableURL: context.nodeExecutableURL,
                        pnpmVersion: normalized(pnpmVersion),
                        pnpmExecutableURL: pnpmURL,
                        fnmExecutableURL: fnmURL,
                        fnmSelector: selector,
                        chosenFNMDirectoryURL: probe.root
                    ),
                    nodeContext: context,
                    pnpmObservation: observation,
                    nodeAttention: nodeAttention,
                    chosenFNMDirectoryURL: probe.root
                )
            }
            return RuntimeObservation(
                pair: nil,
                nodeContext: context,
                pnpmObservation: observation,
                nodeAttention: nodeAttention,
                chosenFNMDirectoryURL: probe.root
            )
        }

        // No default was resolvable. Keep the first root with actual CLI inventory
        // as the bounded fallback and retain its root for a later install.
        for probe in probes where probe.inventory != .unavailable && !probe.inventoryVersions.isEmpty {
            fallbackProbe = probe
            break
        }
        let inventoryRoots = probes.filter { probe in
            guard probe.inventory != .unavailable, !probe.inventoryVersions.isEmpty else { return false }
            switch probe.defaultState {
            case .absent, .unmanaged: return true
            case .unknown, .broken, .managed: return false
            }
        }
        let fallbackRoots: [FNMRootProbe]
        if inventoryRoots.isEmpty && !hadConfiguredDefaultFailure {
            fallbackRoots = probes.filter { probe in
                switch probe.defaultState {
                case .absent, .unmanaged: return true
                case .unknown, .broken, .managed: return false
                }
            }
        } else {
            fallbackRoots = inventoryRoots
        }
        var unsupportedInventoryVersion: String?
        for probe in fallbackRoots {
            if let token = probe.inventoryVersions.first(where: { token in
                guard ProvisioningRuntimePolicy.major(of: token) != nil else { return false }
                if case .supported = ProvisioningRuntimePolicy.nodeStatus(token) { return false }
                return true
            }) {
                unsupportedInventoryVersion = token
                break
            }
        }
        for probe in fallbackRoots {
            let selectors = ProvisioningRuntimePolicy.orderedStableNodeCandidates(defaultVersion: nil, inventory: probe.inventoryVersions)
            for selector in selectors.prefix(ProvisioningRuntimePolicy.maximumFNMRuntimeCandidates) {
                let environment = ProvisioningFNMContext.environment(
                    basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
                    root: probe.root
                )
                let nodeProbe = await probeFNMNode(using: fnmURL, selector: selector, root: probe.root, environment: environment, budget: budget, run: run, executableAvailable: executableAvailable)
                guard let node = nodeProbe.probe else {
                    if nodeProbe.budgetExhausted { budgetExhausted = true }
                    if let failure = nodeProbe.failure { firstAttention = firstAttention ?? failure }
                    if budgetExhausted { break }
                    continue
                }
                guard ProvisioningRuntimePolicy.isSupportedNodeVersion(node.version) else {
                    unsupportedInventoryVersion = unsupportedInventoryVersion ?? node.version
                    hadUnusableSupportedNode = true
                    continue
                }
                guard ProvisioningRuntimePolicy.isManagedNodeExecutable(node.executableURL, within: probe.root) else {
                    firstAttention = firstAttention ?? "fnm inventory entry \(selector) resolved to a Node outside its managed node-versions store."
                    continue
                }
                let context = ProvisioningRuntimeContext(
                    nodeVersion: node.version,
                    nodeExecutableURL: node.executableURL,
                    pnpmVersion: nil,
                    pnpmExecutableURL: nil,
                    fnmExecutableURL: fnmURL,
                    fnmSelector: selector,
                    chosenFNMDirectoryURL: probe.root
                )
                let observation = await probePnpm(
                    root: probe.root,
                    selectedNodeURL: node.executableURL,
                    budget: budget,
                    run: run,
                    executableAvailable: executableAvailable
                )
                if firstNode == nil {
                    firstNode = context
                    bestPnpm = observation
                }
                if let pnpmVersion = observation.version, let pnpmURL = observation.executableURL,
                   ProvisioningRuntimePolicy.supportsPair(nodeVersion: context.nodeVersion, pnpmVersion: pnpmVersion) {
                    return RuntimeObservation(
                        pair: ProvisioningRuntimeContext(
                            nodeVersion: context.nodeVersion,
                            nodeExecutableURL: context.nodeExecutableURL,
                            pnpmVersion: normalized(pnpmVersion),
                            pnpmExecutableURL: pnpmURL,
                            fnmExecutableURL: fnmURL,
                            fnmSelector: selector,
                            chosenFNMDirectoryURL: probe.root
                        ),
                        nodeContext: context,
                        pnpmObservation: observation,
                        nodeAttention: probe.attention,
                        nodeNote: probe.defaultState == .unmanaged ? "fnm's unmanaged default was not changed; this existing managed Node was selected" : nil,
                        chosenFNMDirectoryURL: probe.root
                    )
                }
                if observation.budgetExhausted {
                    budgetExhausted = true
                    break
                }
            }
            if budgetExhausted { break }
        }

        let attention: String?
        if let selectedRoot = firstNode?.chosenFNMDirectoryURL,
           let selectedRootAttention = probes.first(where: { $0.root == selectedRoot })?.attention {
            // The selected root is authoritative. Preserve its unreadability or
            // incomplete-inventory evidence even when a usable fallback Node was
            // found; there are no alternate roots whose failures should leak in.
            attention = selectedRootAttention
        } else if firstNode != nil {
            attention = nil
        } else if let rootAttention = probes.compactMap(\.attention).first {
            attention = rootAttention
        } else if let firstAttention {
            attention = firstAttention
        } else if budgetExhausted || budget.remainingTimeout == nil {
            attention = "Runtime inspection budget exhausted before all Node and pnpm candidates could be checked."
        } else if hadUnusableSupportedNode {
            attention = "A Node entry in fnm's local inventory could not be used; other bounded candidates were checked."
        } else if let unsupportedInventoryVersion {
            attention = "fnm has Node \(unsupportedInventoryVersion), which is outside the supported stable majors 22, 24, and 26; other bounded candidates were checked."
        } else {
            attention = nil
        }
        return RuntimeObservation(
            pair: nil,
            nodeContext: firstNode,
            pnpmObservation: bestPnpm,
            nodeAttention: attention,
            nodeNote: firstNode.flatMap { context in
                probes.first(where: { $0.root == context.chosenFNMDirectoryURL && $0.defaultState == .unmanaged })
                    .map { _ in "fnm's unmanaged default was not changed; this existing managed Node was selected" }
            },
            chosenFNMDirectoryURL: firstNode?.chosenFNMDirectoryURL ?? fallbackProbe?.root ?? probes.first?.root
        )
    }

    private nonisolated struct FNMNodeProbe {
        let version: String
        let executableURL: URL
    }

    private nonisolated static func probeFNMNode(
        using fnmURL: URL,
        selector: String,
        root: URL,
        environment: [String: String],
        budget: RuntimeInspectionBudget,
        run: @Sendable (URL, [String], [String: String], TimeInterval) async -> ProvisioningProcessResult?,
        executableAvailable: @Sendable (URL) -> Bool
    ) async -> (probe: FNMNodeProbe?, failure: String?, budgetExhausted: Bool) {
        guard let normalizedSelector = ProvisioningRuntimePolicy.normalizedVersion(selector) else {
            return (nil, "fnm candidate \(selector) is not a concrete semantic version.", false)
        }
        let expectedNode = root.appendingPathComponent("node-versions/v\(normalizedSelector)/installation/bin/node")
        // Validate the concrete store path before any fnm exec. This prevents
        // fnm from falling through to an ambient standalone Node.
        guard ProvisioningRuntimePolicy.isManagedNodeExecutable(expectedNode, within: root),
              executableAvailable(expectedNode) else {
            return (nil, "fnm candidate \(normalizedSelector) has no executable in its managed node-versions store.", false)
        }
        guard let versionResult = await run(fnmURL, ["exec", "--using", selector, "node", "--version"], environment, budget.remainingTimeout ?? 0) else {
            return (nil, "fnm could not probe existing Node \(selector): the version check timed out.", true)
        }
        guard versionResult.succeeded,
              let reported = versionResult.stdout.firstNonEmptyLine,
              ProvisioningRuntimePolicy.normalizedVersion(reported) != nil else {
            return (nil, "fnm could not probe existing Node \(selector): \(versionResult.failureDescription(for: "fnm exec --using \(selector) node --version", timeout: ProvisioningConfiguration.commandTimeout))", versionResult.timedOut)
        }
        guard let pathResult = await run(fnmURL, ["exec", "--using", selector, "node", "-p", "process.execPath"], environment, budget.remainingTimeout ?? 0) else {
            return (nil, "fnm could not resolve existing Node \(selector)'s executable path: the path check timed out.", true)
        }
        guard pathResult.succeeded,
              let path = pathResult.stdout.firstNonEmptyLine,
              path.hasPrefix("/") else {
            return (nil, "fnm could not resolve existing Node \(selector)'s executable path: \(pathResult.failureDescription(for: "fnm exec --using \(selector) node -p process.execPath", timeout: ProvisioningConfiguration.commandTimeout))", pathResult.timedOut)
        }
        return (FNMNodeProbe(version: runtimeVersion(reported), executableURL: URL(fileURLWithPath: path)), nil, false)
    }

    private nonisolated static func versionSelector(from output: String) -> String? {
        guard let token = output.firstNonEmptyLine?.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init),
              ProvisioningRuntimePolicy.normalizedVersion(token) != nil else { return nil }
        return token.hasPrefix("v") ? String(token.dropFirst()) : token
    }

    private nonisolated static func probePnpm(
        root: URL,
        selectedNodeURL: URL,
        budget: RuntimeInspectionBudget,
        run: @Sendable (URL, [String], [String: String], TimeInterval) async -> ProvisioningProcessResult?,
        executableAvailable: @Sendable (URL) -> Bool
    ) async -> PnpmObservation {
        let environment = ProvisioningFNMContext.environment(
            basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
            root: root
        )
        // The shared absolute candidate list covers the selected Node bin,
        // Homebrew, and the bounded inherited PATH. A missing lookup is simply
        // no candidate; it is not evidence that pnpm was found and failed.
        return await probePnpmCandidates(
            selectedNodeURL: selectedNodeURL,
            prior: [],
            environment: environment,
            budget: budget,
            run: run,
            executableAvailable: executableAvailable
        )
    }

    private nonisolated static func probePnpmCandidates(
        selectedNodeURL: URL,
        prior: [URL],
        environment: [String: String],
        budget: RuntimeInspectionBudget,
        run: @Sendable (URL, [String], [String: String], TimeInterval) async -> ProvisioningProcessResult?,
        executableAvailable: @Sendable (URL) -> Bool
    ) async -> PnpmObservation {
        guard budget.remainingTimeout != nil else {
            return PnpmObservation(
                version: nil,
                executableURL: nil,
                failure: "Runtime inspection budget exhausted.",
                foundExecutable: false,
                budgetExhausted: true
            )
        }

        let inheritedPATH = environment["PATH"] ?? ""
        let ordered = ProvisioningExecutablePaths.pnpmCandidates(
            prior: prior,
            selectedNodeURL: selectedNodeURL,
            inheritedPATH: inheritedPATH
        )
        let priorPaths = Set(prior.map { $0.standardizedFileURL.path })
        let candidates = ordered.filter { candidate in
            priorPaths.contains(candidate.standardizedFileURL.path) ||
                executableAvailable(candidate)
        }
        var probeEnvironment = environment
        probeEnvironment["PATH"] = ProvisioningExecutablePaths.runtimePATH(
            selectedNodeURL: selectedNodeURL,
            inheritedPATH: inheritedPATH
        )

        var bestObservation: PnpmObservation?
        for pnpmURL in candidates {
            guard let result = await run(
                pnpmURL,
                ["--version"],
                probeEnvironment,
                budget.remainingTimeout ?? 0
            ) else {
                let observation = PnpmObservation(
                    version: nil,
                    executableURL: bestObservation?.executableURL ?? pnpmURL,
                    failure: "Runtime inspection budget exhausted.",
                    foundExecutable: bestObservation?.foundExecutable ?? true,
                    budgetExhausted: true
                )
                return betterPnpmObservation(bestObservation, observation) ?? observation
            }
            let observation: PnpmObservation
            if result.succeeded, let version = result.stdout.firstNonEmptyLine {
                observation = PnpmObservation(version: reportedVersion(version), executableURL: pnpmURL, failure: nil, foundExecutable: true)
            } else {
                observation = PnpmObservation(
                    version: nil,
                    executableURL: pnpmURL,
                    failure: result.failureDescription(for: "\(pnpmURL.path) --version", timeout: ProvisioningConfiguration.commandTimeout),
                    foundExecutable: true
                )
            }
            if let version = observation.version,
               ProvisioningRuntimePolicy.isSupportedPnpmVersion(version) {
                return observation
            }
            bestObservation = betterPnpmObservation(bestObservation, observation)
        }
        return bestObservation ?? PnpmObservation.noCandidate
    }

    private nonisolated static func betterPnpmObservation(_ current: PnpmObservation?, _ candidate: PnpmObservation) -> PnpmObservation? {
        guard let current else { return candidate }
        func rank(_ observation: PnpmObservation) -> Int {
            if observation.budgetExhausted { return 4 }
            if observation.version != nil { return 3 }
            if observation.foundExecutable { return 2 }
            return 1
        }
        return rank(candidate) > rank(current) ? candidate : current
    }

    private nonisolated static func makeChecks(context: ProvisioningRuntimeContext) -> (node: ProvisioningCheck, pnpm: ProvisioningCheck, context: ProvisioningRuntimeContext?) {
        let node = ProvisioningCheck(id: .node, state: .ready(nodeDetail(for: context)))
        let pnpmDetail = context.pnpmVersion.map { "pnpm \($0); path: \(context.pnpmExecutableURL?.path ?? "unknown"); selected Node: \(context.nodeVersion)" } ?? "pnpm is not available in selected Node \(context.nodeVersion) context."
        let pnpm = ProvisioningCheck(id: .pnpm, state: .ready(pnpmDetail))
        return (node, pnpm, context)
    }

    nonisolated static func pnpmCheck(for context: ProvisioningRuntimeContext?, observed: PnpmObservation?) -> ProvisioningCheck {
        guard let observed else {
            return ProvisioningCheck(id: .pnpm, state: .missing("pnpm is not installed in the selected Node context. A new install targets pnpm \(ProvisioningRuntimePolicy.recommendedPnpmVersion); supported stable majors are 10, 11, and 12."))
        }
        if observed.budgetExhausted {
            return ProvisioningCheck(id: .pnpm, state: .attention("Runtime inspection budget exhausted before pnpm could be fully checked; run Check again."))
        }
        if let version = observed.version {
            if ProvisioningRuntimePolicy.isSupportedPnpmVersion(version) {
                let selected = context?.nodeVersion ?? "the selected Node"
                return ProvisioningCheck(id: .pnpm, state: .ready("pnpm \(version); path: \(observed.executableURL?.path ?? "unknown"); selected Node: \(selected)"))
            }
            return ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm \(version) at \(observed.executableURL?.path ?? "unknown"), outside supported stable majors 10, 11, and 12; it was not replaced."))
        }
        if observed.foundExecutable {
            return ProvisioningCheck(id: .pnpm, state: .attention("Found pnpm at \(observed.executableURL?.path ?? "unknown"), but its version probe was unusable: \(observed.failure ?? "unknown failure"). It was not replaced."))
        }
        return ProvisioningCheck(id: .pnpm, state: .missing("pnpm is not installed in the selected Node context. A new install targets pnpm \(ProvisioningRuntimePolicy.recommendedPnpmVersion); supported stable majors are 10, 11, and 12."))
    }

    private nonisolated static func nodeDetail(for context: ProvisioningRuntimeContext) -> String {
        "Node \(context.nodeVersion); path: \(context.nodeExecutableURL.path)"
    }

    private nonisolated static func normalized(_ value: String) -> String {
        ProvisioningRuntimePolicy.normalizedVersion(value) ?? reportedVersion(value)
    }

    private nonisolated static func runtimeVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private nonisolated static func reportedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    private nonisolated static func executableCandidates(named name: String, extra: [URL], prioritizeExtra: Bool = false) -> [URL] {
        var inherited = [URL]()
        for component in ProvisioningConfiguration.guiSafePATH.split(separator: ":")
            .prefix(ProvisioningRuntimePolicy.maximumInheritedPATHEntries)
            .map(String.init) where !component.isEmpty {
            inherited.append(URL(fileURLWithPath: component, isDirectory: true).appendingPathComponent(name))
        }
        let maximum = ProvisioningRuntimePolicy.maximumExecutableCandidates
        if prioritizeExtra {
            // Preserve the inherited PATH preference, but reserve bounded slots
            // for standard locations so a stale PATH entry cannot hide a
            // supported executable in /opt/homebrew, /usr/local, or /usr/bin.
            let standard = uniqueExecutable(extra)
            let inherited = uniqueExecutable(inherited)
            let inheritedPrefixCount = max(0, maximum - standard.count)
            var values = Array(inherited.prefix(inheritedPrefixCount))
            values.append(contentsOf: standard.prefix(maximum - values.count))
            if values.count < maximum {
                values.append(contentsOf: inherited.dropFirst(values.count).prefix(maximum - values.count))
            }
            return values
        }
        return Array(uniqueExecutable(inherited + extra).prefix(maximum))
    }

    private nonisolated static func firstExecutable(named name: String, extra: [URL]) -> URL? {
        executableCandidates(named: name, extra: extra).first
    }

    private nonisolated static func uniqueExecutable(_ candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        return candidates.filter {
            let path = $0.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return FileManager.default.isExecutableFile(atPath: path)
        }
    }
}
