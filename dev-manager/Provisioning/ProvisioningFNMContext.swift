import Darwin
import Foundation

/// Read-only fnm data-root selection shared by inspection, installation, shell setup,
/// and DEBUG fixture handoff. It deliberately models only fnm's own data directory;
/// no project metadata or shell startup files are consulted.
nonisolated struct ProvisioningFNMRootEvidence: Equatable, Sendable {
    let hasConfiguredDefault: Bool
    let hasInstalledInventory: Bool

    nonisolated enum Inventory: Equatable, Sendable {
        case unknown
        case knownEmpty
        case knownVersions([String])
        case incomplete([String])
    }

    nonisolated enum DefaultAlias: Equatable, Sendable {
        case unknown
        case absent
        case managed
        case external
        case broken
    }

    /// Bounded filesystem facts supplement fnm's human-oriented output. They
    /// never execute anything and only inspect the root, node-versions' direct
    /// children, and aliases/default/bin/node.
    let inventory: Inventory
    let defaultAlias: DefaultAlias
    let managedDefaultVersion: String?
    let rootReadable: Bool

    nonisolated init(
        hasConfiguredDefault: Bool = false,
        hasInstalledInventory: Bool = false,
        inventory: Inventory = .unknown,
        defaultAlias: DefaultAlias = .unknown,
        managedDefaultVersion: String? = nil,
        rootReadable: Bool = true
    ) {
        self.hasConfiguredDefault = hasConfiguredDefault
        self.hasInstalledInventory = hasInstalledInventory
        self.inventory = inventory
        self.defaultAlias = defaultAlias
        self.managedDefaultVersion = managedDefaultVersion
        self.rootReadable = rootReadable
    }

    fileprivate var priority: Int {
        hasConfiguredDefault ? 2 : (hasInstalledInventory ? 1 : 0)
    }
}

nonisolated enum ProvisioningFNMContext {
    nonisolated static let maximumRootCandidates = 4

    nonisolated static func candidateDataRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        evidence: [URL: ProvisioningFNMRootEvidence] = [:]
    ) -> [URL] {
        let explicit = nonEmptyURL(environment["FNM_DIR"])
        let xdgRoot = nonEmptyURL(environment["XDG_DATA_HOME"])?.appendingPathComponent("fnm", isDirectory: true)
        return orderedDataRoots(explicitFNMDirectory: explicit, xdgFNMDirectory: xdgRoot, homeDirectory: homeDirectory, evidence: evidence)
    }

    nonisolated static func orderedDataRoots(
        explicitFNMDirectory: URL?,
        xdgFNMDirectory: URL?,
        homeDirectory: URL,
        evidence: [URL: ProvisioningFNMRootEvidence] = [:]
    ) -> [URL] {
        let macRoot = homeDirectory.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacyRoot = homeDirectory.appendingPathComponent(".local/share/fnm", isDirectory: true)
        let raw: [URL]
        if let explicitFNMDirectory { raw = [explicitFNMDirectory] }
        else if let xdgFNMDirectory { raw = [xdgFNMDirectory] }
        else { raw = [macRoot, legacyRoot] }
        var unique = [URL]()
        var seen = Set<String>()
        for root in raw {
            let normalized = root.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { continue }
            unique.append(normalized)
        }
        return unique.enumerated().sorted { left, right in
            let leftEvidence = evidence[left.element]?.priority ?? 0
            let rightEvidence = evidence[right.element]?.priority ?? 0
            if leftEvidence != rightEvidence { return leftEvidence > rightEvidence }
            return left.offset < right.offset
        }.prefix(maximumRootCandidates).map { $0.element }
    }

    nonisolated static func filesystemEvidence(at root: URL) -> ProvisioningFNMRootEvidence {
        filesystemFacts(at: root)
    }

    /// Read only a bounded, direct-child inventory. Missing roots and missing
    /// stores are normal absence. lstat/stat are used instead of fileExists so
    /// dangling links and permission failures cannot become false absence.
    nonisolated static func filesystemFacts(at root: URL) -> ProvisioningFNMRootEvidence {
        let rootPath = pathState(root.path)
        switch rootPath {
        case .missing:
            return ProvisioningFNMRootEvidence(inventory: .knownEmpty, defaultAlias: .absent)
        case .unreadable:
            return ProvisioningFNMRootEvidence(inventory: .unknown, defaultAlias: .unknown, rootReadable: false)
        case .broken, .regular:
            return ProvisioningFNMRootEvidence(inventory: .unknown, defaultAlias: .broken, rootReadable: false)
        case .directory:
            break
        }
        guard directoryReadable(root.path), (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
            return ProvisioningFNMRootEvidence(inventory: .unknown, defaultAlias: .unknown, rootReadable: false)
        }

        let inventoryURL = root.appendingPathComponent("node-versions", isDirectory: true)
        let inventory = inventoryFacts(at: inventoryURL, root: root)
        let alias = defaultAliasEvidence(at: root)
        let versions: [String]
        if case let .knownVersions(values) = inventory { versions = values } else { versions = [] }
        return ProvisioningFNMRootEvidence(
            hasConfiguredDefault: alias.version != nil,
            hasInstalledInventory: !versions.isEmpty,
            inventory: inventory,
            defaultAlias: alias.state,
            managedDefaultVersion: alias.version,
            rootReadable: true
        )
    }

    private nonisolated enum PathState {
        case missing, directory, regular, broken, unreadable
    }

    private nonisolated static func pathState(_ path: String) -> PathState {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return errno == ENOENT ? .missing : (errno == EACCES || errno == EPERM ? .unreadable : .broken)
        }
        let type = info.st_mode & S_IFMT
        if type == S_IFLNK {
            guard stat(path, &info) == 0 else {
                return errno == ENOENT ? .broken : (errno == EACCES || errno == EPERM ? .unreadable : .broken)
            }
        }
        let resolvedType = info.st_mode & S_IFMT
        if resolvedType == S_IFDIR {
            return directoryModeReadable(info.st_mode) ? .directory : .unreadable
        }
        if resolvedType == S_IFREG { return .regular }
        return .broken
    }

    private nonisolated static func directoryModeReadable(_ mode: mode_t) -> Bool {
        (mode & (S_IRUSR | S_IRGRP | S_IROTH)) != 0 &&
        (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0
    }

    private nonisolated static func directoryReadable(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return directoryModeReadable(info.st_mode)
    }

    private nonisolated static func inventoryFacts(at inventoryURL: URL, root: URL) -> ProvisioningFNMRootEvidence.Inventory {
        switch pathState(inventoryURL.path) {
        case .missing: return .knownEmpty
        case .unreadable: return .unknown
        case .broken, .regular: return .incomplete(["node-versions"])
        case .directory: break
        }
        guard directoryReadable(inventoryURL.path),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: inventoryURL.path) else { return .unknown }
        var valid = [String]()
        var incomplete = [String]()
        for entry in entries {
            let entryURL = inventoryURL.appendingPathComponent(entry, isDirectory: true)
            guard let normalized = ProvisioningRuntimePolicy.normalizedVersion(entry),
                  entry == "v\(normalized)" else {
                // Stray files and malformed folders are deliberately not
                // installed inventory, but retain an explicit incomplete fact.
                incomplete.append(entry)
                continue
            }
            guard pathState(entryURL.path) == .directory else {
                incomplete.append(entry)
                continue
            }
            let node = entryURL.appendingPathComponent("installation/bin/node")
            guard concreteExecutable(node, within: root) else {
                incomplete.append(entry)
                continue
            }
            valid.append(normalized)
        }
        if !valid.isEmpty { return .knownVersions(valid.sorted()) }
        return incomplete.isEmpty ? .knownEmpty : .incomplete(incomplete.sorted())
    }

    private nonisolated static func defaultAliasEvidence(at root: URL) -> (state: ProvisioningFNMRootEvidence.DefaultAlias, version: String?) {
        let alias = root.appendingPathComponent("aliases/default", isDirectory: true)
        switch pathState(alias.path) {
        case .missing: return (.absent, nil)
        case .unreadable: return (.unknown, nil)
        case .broken, .regular: return (.broken, nil)
        case .directory: break
        }
        let node = alias.appendingPathComponent("bin/node")
        switch pathState(node.path) {
        case .missing, .broken: return (.broken, nil)
        case .unreadable: return (.unknown, nil)
        case .directory: return (.broken, nil)
        case .regular: break
        }
        guard regularReadableExecutable(node.path) else { return (.unknown, nil) }
        guard concreteExecutable(node, within: root) else {
            // A readable executable outside the store is an intentional
            // unmanaged/system alias, not a malformed managed installation.
            let resolved = node.resolvingSymlinksInPath().standardizedFileURL
            if pathState(node.path) == .regular || ProvisioningRuntimePolicy.isManagedNodeExecutable(resolved, within: root) == false {
                return (.external, nil)
            }
            return (.broken, nil)
        }
        let resolved = node.resolvingSymlinksInPath().standardizedFileURL
        let components = resolved.pathComponents
        guard let index = components.firstIndex(of: "node-versions"), index + 1 < components.count else { return (.external, nil) }
        let version = String(components[index + 1].dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return (.managed, ProvisioningRuntimePolicy.normalizedVersion(version))
    }

    private nonisolated static func regularReadableExecutable(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
        return (info.st_mode & (S_IRUSR | S_IRGRP | S_IROTH)) != 0 &&
            (info.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0
    }

    private nonisolated static func concreteExecutable(_ node: URL, within root: URL) -> Bool {
        let state = pathState(node.path)
        guard state == .regular, regularReadableExecutable(node.path), FileManager.default.isExecutableFile(atPath: node.path) else { return false }
        let resolved = node.resolvingSymlinksInPath().standardizedFileURL
        guard ProvisioningRuntimePolicy.isManagedNodeExecutable(resolved, within: root),
              let version = resolved.pathComponents.drop(while: { $0 != "node-versions" }).dropFirst().first,
              ProvisioningRuntimePolicy.normalizedVersion(version) != nil else { return false }
        return true
    }

    nonisolated static func environment(basedOn base: [String: String], root: URL) -> [String: String] {
        var result = base
        result["FNM_DIR"] = root.standardizedFileURL.path
        return result
    }

    private nonisolated static func nonEmptyURL(_ value: String?) -> URL? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
