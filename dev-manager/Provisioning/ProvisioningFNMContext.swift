import Foundation

/// Read-only fnm data-root selection shared by inspection, installation, shell setup,
/// and DEBUG fixture handoff. It deliberately models only fnm's own data directory;
/// no project metadata or shell startup files are consulted.
nonisolated struct ProvisioningFNMRootEvidence: Equatable, Sendable {
    let hasConfiguredDefault: Bool
    let hasInstalledInventory: Bool

    nonisolated init(hasConfiguredDefault: Bool = false, hasInstalledInventory: Bool = false) {
        self.hasConfiguredDefault = hasConfiguredDefault
        self.hasInstalledInventory = hasInstalledInventory
    }

    fileprivate var priority: Int {
        hasConfiguredDefault ? 2 : (hasInstalledInventory ? 1 : 0)
    }
}

nonisolated enum ProvisioningFNMContext {
    nonisolated static let maximumRootCandidates = 4

    /// Returns an explicit FNM_DIR or XDG root alone; only implicit macOS and
    /// legacy roots are compared by read-only filesystem evidence.
    nonisolated static func candidateDataRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        evidence: [URL: ProvisioningFNMRootEvidence] = [:]
    ) -> [URL] {
        let explicit = nonEmptyURL(environment["FNM_DIR"])
        let xdgRoot = nonEmptyURL(environment["XDG_DATA_HOME"])?.appendingPathComponent("fnm", isDirectory: true)
        return orderedDataRoots(
            explicitFNMDirectory: explicit,
            xdgFNMDirectory: xdgRoot,
            homeDirectory: homeDirectory,
            evidence: evidence
        )
    }

    nonisolated static func orderedDataRoots(
        explicitFNMDirectory: URL?,
        xdgFNMDirectory: URL?,
        homeDirectory: URL,
        evidence: [URL: ProvisioningFNMRootEvidence] = [:]
    ) -> [URL] {
        let macRoot = homeDirectory.appendingPathComponent("Library/Application Support/fnm", isDirectory: true)
        let legacyRoot = homeDirectory.appendingPathComponent(".local/share/fnm", isDirectory: true)
        // An explicit root is authoritative. Do not let evidence from an
        // implicitly discovered root redirect a user's configured FNM_DIR.
        let raw: [URL]
        if let explicitFNMDirectory {
            raw = [explicitFNMDirectory]
        } else if let xdgFNMDirectory {
            raw = [xdgFNMDirectory]
        } else {
            raw = [macRoot, legacyRoot]
        }
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

    /// Filesystem metadata is only used to order read-only probes. A missing or
    /// empty candidate is still retained so an explicit FNM_DIR can be selected
    /// for a future consented install.
    nonisolated static func filesystemEvidence(at root: URL) -> ProvisioningFNMRootEvidence {
        let fileManager = FileManager.default
        let aliasURL = root.appendingPathComponent("aliases/default", isDirectory: true)
        let hasDefault: Bool = {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: aliasURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            let nodeURL = aliasURL.appendingPathComponent("bin/node")
            guard fileManager.fileExists(atPath: nodeURL.path),
                  fileManager.isExecutableFile(atPath: nodeURL.path) else { return false }
            guard let attributes = try? fileManager.attributesOfItem(atPath: nodeURL.path),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? NSNumber else { return false }
            return permissions.intValue & 0o111 != 0
        }()
        let inventoryURL = root.appendingPathComponent("node-versions", isDirectory: true)
        let hasInventory: Bool = {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: inventoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return (try? fileManager.contentsOfDirectory(atPath: inventoryURL.path).isEmpty == false) ?? false
        }()
        return ProvisioningFNMRootEvidence(hasConfiguredDefault: hasDefault, hasInstalledInventory: hasInventory)
    }

    nonisolated static func environment(
        basedOn base: [String: String],
        root: URL
    ) -> [String: String] {
        var result = base
        result["FNM_DIR"] = root.standardizedFileURL.path
        return result
    }

    private nonisolated static func nonEmptyURL(_ value: String?) -> URL? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
