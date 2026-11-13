import Darwin
import Foundation

nonisolated enum ProvisioningInspector {
    nonisolated static func inspect() async -> ProvisioningInspection {
        let developerTools = await checkDeveloperTools()
        let homebrew = await checkHomebrew()
        let fnm = await checkFNM()
        let runtime = await checkRuntime(using: fnm.executableURL)
        let fnmCheck = makeFNMCheck(for: fnm, runtime: runtime.context)
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
            let runtime = await checkRuntime(using: fnm.executableURL)
            return ProvisioningTargetedInspection(
                checks: [makeFNMCheck(for: fnm, runtime: runtime.context), runtime.node, runtime.pnpm],
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
        for result: (check: ProvisioningCheck, executableURL: URL?),
        runtime: ProvisioningRuntimeContext?
    ) -> ProvisioningCheck {
        guard result.executableURL == nil, let runtime, !runtime.isManagedByFNM, runtime.hasUsablePnpm else {
            return result.check
        }
        return ProvisioningCheck(
            id: .fnm,
            state: .notRequired("Optional: fnm is not required because this unmanaged Node/pnpm pair is supported and usable. fnm is absent or unusable; no fnm binary was selected.")
        )
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

    private nonisolated static func checkRuntime(using fnmURL: URL?) async -> (node: ProvisioningCheck, pnpm: ProvisioningCheck, context: ProvisioningRuntimeContext?, chosenFNMDirectoryURL: URL?) {
        let budget = RuntimeInspectionBudget()
        let fnmResult = await inspectFNMRuntime(using: fnmURL, budget: budget)

        // A resolvable fnm default is authoritative even when pnpm is absent or
        // unusable. Never replace that Node with a Homebrew/PATH candidate.
        if fnmResult.isAuthoritativeDefault, let nodeContext = fnmResult.nodeContext {
            let node: ProvisioningCheck
            if let attention = fnmResult.nodeAttention {
                node = ProvisioningCheck(id: .node, state: .attention(attention))
            } else {
                node = ProvisioningCheck(id: .node, state: .ready(nodeDetail(for: nodeContext)))
            }
            let pnpm = pnpmCheck(for: nodeContext, observed: fnmResult.pnpmObservation)
            let context = fnmResult.pair ?? nodeContext
            return (node, pnpm, context, fnmResult.chosenFNMDirectoryURL)
        }
        if let pair = fnmResult.pair {
            let checks = makeChecks(context: pair)
            return (checks.node, checks.pnpm, pair, fnmResult.chosenFNMDirectoryURL)
        }

        // A GUI-launched app can have a perfectly usable standard Node when fnm
        // is absent or has no resolvable configured default. Inspect it directly;
        // this fallback is intentionally unavailable for an authoritative fnm default.
        let guiResult = await inspectGUIRuntime(budget: budget)
        if let pair = guiResult.pair {
            let checks = makeChecks(context: pair)
            return (checks.node, checks.pnpm, pair, fnmResult.chosenFNMDirectoryURL)
        }

        var bestPnpm: PnpmObservation?
        if let fallback = fnmResult.nodeContext ?? guiResult.nodeContext {
            let observation = fnmResult.nodeContext != nil ? fnmResult.pnpmObservation : guiResult.pnpmObservation
            let node = ProvisioningCheck(id: .node, state: .ready(nodeDetail(for: fallback)))
            let pnpm = pnpmCheck(for: fallback, observed: observation)
            return (node, pnpm, fallback, fnmResult.chosenFNMDirectoryURL)
        }
        if let observation = fnmResult.pnpmObservation {
            bestPnpm = betterPnpmObservation(bestPnpm, observation)
        }
        if let observation = guiResult.pnpmObservation {
            bestPnpm = betterPnpmObservation(bestPnpm, observation)
        }

        let nodeAttention = fnmResult.nodeAttention ?? guiResult.nodeAttention
        let node: ProvisioningCheck
        if let nodeAttention {
            node = ProvisioningCheck(id: .node, state: .attention(nodeAttention))
        } else {
            node = ProvisioningCheck(id: .node, state: .missing("No supported Node was found. A new install targets Node \(ProvisioningRuntimePolicy.recommendedNodeVersion); supported stable majors are 22, 24, and 26."))
        }
        let pnpm: ProvisioningCheck
        if let bestPnpm {
            pnpm = pnpmCheck(for: nil, observed: bestPnpm)
        } else {
            pnpm = ProvisioningCheck(id: .pnpm, state: .unverified("pnpm will be checked after a usable Node context is selected; the recommended new-install target is pnpm \(ProvisioningRuntimePolicy.recommendedPnpmVersion)."))
        }
        return (node, pnpm, nil, fnmResult.chosenFNMDirectoryURL)
    }

    private nonisolated struct RuntimeInspectionBudget {
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

    private nonisolated struct RuntimeObservation {
        let pair: ProvisioningRuntimeContext?
        let nodeContext: ProvisioningRuntimeContext?
        let pnpmObservation: PnpmObservation?
        let nodeAttention: String?
        let isAuthoritativeDefault: Bool
        let chosenFNMDirectoryURL: URL?

        init(
            pair: ProvisioningRuntimeContext?,
            nodeContext: ProvisioningRuntimeContext?,
            pnpmObservation: PnpmObservation?,
            nodeAttention: String?,
            isAuthoritativeDefault: Bool = false,
            chosenFNMDirectoryURL: URL? = nil
        ) {
            self.pair = pair
            self.nodeContext = nodeContext
            self.pnpmObservation = pnpmObservation
            self.nodeAttention = nodeAttention
            self.isAuthoritativeDefault = isAuthoritativeDefault
            self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
        }
    }

    private nonisolated struct PnpmObservation {
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

    private nonisolated struct FNMRootProbe {
        let root: URL
        let inventory: ProvisioningProcessResult?
        let inventoryVersions: [String]
        let defaultSelector: String?
    }

    private nonisolated static func inspectFNMRuntime(using fnmURL: URL?, budget: RuntimeInspectionBudget) async -> RuntimeObservation {
        guard let fnmURL else { return RuntimeObservation(pair: nil, nodeContext: nil, pnpmObservation: nil, nodeAttention: nil) }

        let initialRoots = ProvisioningFNMContext.candidateDataRoots()
        let evidence = Dictionary(uniqueKeysWithValues: initialRoots.map { ($0, ProvisioningFNMContext.filesystemEvidence(at: $0)) })
        let roots = ProvisioningFNMContext.candidateDataRoots(evidence: evidence)
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
            guard let inventory = await runtimeProbe(fnmURL, arguments: ["list"], environment: environment, budget: budget) else {
                budgetExhausted = true
                firstAttention = firstAttention ?? "fnm's Node inventory check timed out before the local root could be inspected."
                break
            }
            if !inventory.succeeded {
                if inventory.timedOut {
                    budgetExhausted = true
                    firstAttention = firstAttention ?? inventory.failureDescription(for: "fnm list", timeout: ProvisioningConfiguration.commandTimeout)
                } else {
                    firstAttention = firstAttention ?? "fnm's local Node inventory could not be inspected: \(inventory.failureDescription(for: "fnm list", timeout: ProvisioningConfiguration.commandTimeout))"
                }
            }
            guard let defaultProbe = await runtimeProbe(fnmURL, arguments: ["default"], environment: environment, budget: budget) else {
                budgetExhausted = true
                firstAttention = firstAttention ?? "fnm's default Node check timed out before the local root could be inspected."
                break
            }
            if defaultProbe.timedOut {
                budgetExhausted = true
                firstAttention = firstAttention ?? defaultProbe.failureDescription(for: "fnm default", timeout: ProvisioningConfiguration.commandTimeout)
            } else if !defaultProbe.succeeded, defaultProbe.terminationStatus == -1 {
                firstAttention = firstAttention ?? "fnm's default Node check could not start: \(defaultProbe.failureDescription(for: "fnm default", timeout: ProvisioningConfiguration.commandTimeout))"
            }
            let inventoryVersions: [String] = inventory.succeeded
                ? inventory.stdout
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
                    .map(String.init)
                : []
            probes.append(FNMRootProbe(
                root: root,
                inventory: inventory.succeeded ? inventory : nil,
                inventoryVersions: inventoryVersions,
                defaultSelector: defaultProbe.succeeded ? versionSelector(from: defaultProbe.stdout) : nil
            ))
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

        // A concrete, working default wins over every inventory or GUI candidate.
        for probe in probes {
            guard let selector = probe.defaultSelector else { continue }
            let environment = ProvisioningFNMContext.environment(
                basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
                root: probe.root
            )
            let nodeProbe = await probeFNMNode(using: fnmURL, selector: selector, environment: environment, budget: budget)
            guard let node = nodeProbe.probe else {
                if nodeProbe.budgetExhausted { budgetExhausted = true }
                if let failure = nodeProbe.failure { firstAttention = firstAttention ?? failure }
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
                using: fnmURL,
                selector: selector,
                root: probe.root,
                selectedNodeURL: node.executableURL,
                budget: budget
            )
            bestPnpm = betterPnpmObservation(bestPnpm, observation)
            let nodeAttention: String?
            if ProvisioningRuntimePolicy.isSupportedNodeVersion(node.version) {
                nodeAttention = nil
            } else {
                nodeAttention = "fnm's configured default is Node \(node.version), outside supported stable majors 22, 24, and 26; it was not replaced."
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
                    nodeAttention: nodeAttention,
                    isAuthoritativeDefault: true,
                    chosenFNMDirectoryURL: probe.root
                )
            }
            return RuntimeObservation(
                pair: nil,
                nodeContext: context,
                pnpmObservation: observation,
                nodeAttention: nodeAttention,
                isAuthoritativeDefault: true,
                chosenFNMDirectoryURL: probe.root
            )
        }

        // No default was resolvable. Keep the first root with actual CLI inventory
        // as the bounded fallback and retain its root for a later install.
        for probe in probes where probe.inventory != nil && !probe.inventoryVersions.isEmpty {
            fallbackProbe = probe
            break
        }
        let inventoryRoots = probes.filter { $0.inventory != nil && !$0.inventoryVersions.isEmpty }
        let fallbackRoots = inventoryRoots.isEmpty ? probes : inventoryRoots
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
                let nodeProbe = await probeFNMNode(using: fnmURL, selector: selector, environment: environment, budget: budget)
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
                    using: fnmURL,
                    selector: selector,
                    root: probe.root,
                    selectedNodeURL: node.executableURL,
                    budget: budget
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
                        nodeAttention: nil,
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
        if let firstAttention {
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
        environment: [String: String],
        budget: RuntimeInspectionBudget
    ) async -> (probe: FNMNodeProbe?, failure: String?, budgetExhausted: Bool) {
        guard let versionResult = await runtimeProbe(fnmURL, arguments: ["exec", "--using", selector, "node", "--version"], environment: environment, budget: budget) else {
            return (nil, "fnm could not probe existing Node \(selector): the version check timed out.", true)
        }
        guard versionResult.succeeded,
              let reported = versionResult.stdout.firstNonEmptyLine,
              ProvisioningRuntimePolicy.normalizedVersion(reported) != nil else {
            return (nil, "fnm could not probe existing Node \(selector): \(versionResult.failureDescription(for: "fnm exec --using \(selector) node --version", timeout: ProvisioningConfiguration.commandTimeout))", versionResult.timedOut)
        }
        guard let pathResult = await runtimeProbe(fnmURL, arguments: ["exec", "--using", selector, "node", "-p", "process.execPath"], environment: environment, budget: budget) else {
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

    private nonisolated static func inspectGUIRuntime(budget: RuntimeInspectionBudget) async -> RuntimeObservation {
        let candidates = executableCandidates(named: "node", extra: [
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/usr/bin/node")
        ])
        var firstNode: ProvisioningRuntimeContext?
        var bestPnpm: PnpmObservation?
        var nodeAttention: String?
        var budgetExhausted = false
        for nodeURL in candidates {
            guard let result = await runtimeProbe(nodeURL, arguments: ["--version"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment, budget: budget) else {
                budgetExhausted = true
                break
            }
            guard result.succeeded, let reported = result.stdout.firstNonEmptyLine else {
                if nodeAttention == nil {
                    nodeAttention = "Found Node at \(nodeURL.path), but it could not report a usable version: \(result.failureDescription(for: "\(nodeURL.path) --version", timeout: ProvisioningConfiguration.commandTimeout))"
                }
                continue
            }
            guard ProvisioningRuntimePolicy.isSupportedNodeVersion(reported) else {
                if nodeAttention == nil {
                    nodeAttention = "Found Node at \(nodeURL.path), but it reported \(reported), which is outside supported stable majors 22, 24, and 26; other bounded candidates were checked."
                }
                continue
            }
            guard let pathResult = await runtimeProbe(nodeURL, arguments: ["-p", "process.execPath"], environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment, budget: budget) else {
                budgetExhausted = true
                break
            }
            let actualPath = pathResult.succeeded ? (pathResult.stdout.firstNonEmptyLine.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? nodeURL.path) : nodeURL.path
            let context = ProvisioningRuntimeContext(nodeVersion: normalized(reported), nodeExecutableURL: URL(fileURLWithPath: actualPath), pnpmVersion: nil, pnpmExecutableURL: nil, fnmExecutableURL: nil, fnmSelector: nil)
            let observation = await probePnpmCandidates(
                selectedNodeURL: context.nodeExecutableURL,
                prior: [],
                environment: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
                budget: budget
            )
            if firstNode == nil {
                firstNode = context
                bestPnpm = observation
            }
            if let version = observation.version, let pnpmURL = observation.executableURL,
               ProvisioningRuntimePolicy.supportsPair(nodeVersion: context.nodeVersion, pnpmVersion: version) {
                return RuntimeObservation(
                    pair: ProvisioningRuntimeContext(nodeVersion: context.nodeVersion, nodeExecutableURL: context.nodeExecutableURL, pnpmVersion: normalized(version), pnpmExecutableURL: pnpmURL, fnmExecutableURL: nil, fnmSelector: nil),
                    nodeContext: context,
                    pnpmObservation: observation,
                    nodeAttention: nil
                )
            }
            if observation.budgetExhausted {
                budgetExhausted = true
                break
            }
        }
        let attention = budgetExhausted || budget.remainingTimeout == nil
            ? "Runtime inspection budget exhausted before all GUI Node and pnpm candidates could be checked."
            : nodeAttention
        return RuntimeObservation(pair: nil, nodeContext: firstNode, pnpmObservation: bestPnpm, nodeAttention: attention)
    }

    private nonisolated static func probePnpm(
        using fnmURL: URL,
        selector: String,
        root: URL,
        selectedNodeURL: URL,
        budget: RuntimeInspectionBudget
    ) async -> PnpmObservation {
        let environment = ProvisioningFNMContext.environment(
            basedOn: ProvisioningConfiguration.readOnlyRuntimeEnvironment,
            root: root
        )
        guard let pathResult = await runtimeProbe(
            fnmURL,
            arguments: ["exec", "--using", selector, "/usr/bin/which", "pnpm"],
            environment: environment,
            budget: budget
        ) else {
            return PnpmObservation(version: nil, executableURL: nil, failure: "Runtime inspection budget exhausted.", foundExecutable: false, budgetExhausted: true)
        }

        // fnm's result is only a preferred candidate. A failed or stale `which`
        // result must not prevent the known GUI/Homebrew and bounded PATH probes.
        let prior: [URL] = pathResult.succeeded
            ? (pathResult.stdout.firstNonEmptyLine
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
                .map { [$0] } ?? [])
            : []
        let discoveryFailure = pathResult.succeeded
            ? nil
            : pathResult.failureDescription(for: "fnm exec --using \(selector) which pnpm", timeout: ProvisioningConfiguration.commandTimeout)
        return await probePnpmCandidates(
            selectedNodeURL: selectedNodeURL,
            prior: prior,
            environment: environment,
            budget: budget,
            initialFailure: discoveryFailure
        )
    }

    private nonisolated static func probePnpmCandidates(
        selectedNodeURL: URL,
        prior: [URL],
        environment: [String: String],
        budget: RuntimeInspectionBudget,
        initialFailure: String? = nil
    ) async -> PnpmObservation {
        let inheritedPATH = environment["PATH"] ?? ""
        let ordered = ProvisioningExecutablePaths.pnpmCandidates(
            prior: prior,
            selectedNodeURL: selectedNodeURL,
            inheritedPATH: inheritedPATH
        )
        let priorPaths = Set(prior.map { $0.standardizedFileURL.path })
        let candidates = ordered.filter { candidate in
            priorPaths.contains(candidate.standardizedFileURL.path) ||
                FileManager.default.isExecutableFile(atPath: candidate.path)
        }
        var probeEnvironment = environment
        probeEnvironment["PATH"] = ProvisioningExecutablePaths.runtimePATH(
            selectedNodeURL: selectedNodeURL,
            inheritedPATH: inheritedPATH
        )

        var bestObservation: PnpmObservation?
        for pnpmURL in candidates {
            guard let result = await runtimeProbe(
                pnpmURL,
                arguments: ["--version"],
                environment: probeEnvironment,
                budget: budget
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
        return bestObservation ?? PnpmObservation(
            version: nil,
            executableURL: prior.first,
            failure: initialFailure,
            foundExecutable: initialFailure != nil || !prior.isEmpty
        )
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

    private nonisolated static func pnpmCheck(for context: ProvisioningRuntimeContext?, observed: PnpmObservation?) -> ProvisioningCheck {
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
