import Foundation

/// The small, app-owned support snapshot used by the provisioning surface.
///
/// These are supported major families, not exact patch pins and not a claim that
/// either project is an LTS/security-upgrade service. A successful pnpm probe is
/// still required in the selected Node context. Sources: nodejs.org/en/about/previous-releases,
/// github.com/nodejs/Release#release-schedule, and pnpm.io/installation.
nonisolated enum ProvisioningRuntimePolicy {
    nonisolated static let supportedNodeMajors: Set<Int> = [22, 24, 26]
    nonisolated static let supportedPnpmMajors: Set<Int> = [10, 11, 12]

    // Installation targets only: they are not general readiness requirements.
    nonisolated static let recommendedNodeVersion = "24.22.2"
    nonisolated static let recommendedPnpmVersion = "12.18.0"
    nonisolated static let maximumFNMRuntimeCandidates = 8
    nonisolated static let maximumExecutableCandidates = 8
    nonisolated static let maximumInheritedPATHEntries = 32

    nonisolated enum VersionStatus: Equatable, Sendable {
        case supported(major: Int)
        case prerelease
        case unsupported
        case unusable
    }

    nonisolated static func nodeStatus(_ version: String) -> VersionStatus {
        status(version, supportedMajors: supportedNodeMajors)
    }

    nonisolated static func pnpmStatus(_ version: String) -> VersionStatus {
        status(version, supportedMajors: supportedPnpmMajors)
    }

    nonisolated static func isSupportedNodeVersion(_ version: String) -> Bool {
        if case .supported = nodeStatus(version) { return true }
        return false
    }

    nonisolated static func isSupportedPnpmVersion(_ version: String) -> Bool {
        if case .supported = pnpmStatus(version) { return true }
        return false
    }

    nonisolated static func supportsPair(nodeVersion: String, pnpmVersion: String) -> Bool {
        isSupportedNodeVersion(nodeVersion) && isSupportedPnpmVersion(pnpmVersion)
    }

    /// Accept only a concrete executable whose canonical target is inside fnm's
    /// node-versions store. Canonicalization intentionally accepts aliases such
    /// as `aliases/default` when they resolve into that store, while system,
    /// outside-store, and prefix-collision paths are rejected.
    nonisolated static func isManagedNodeExecutable(_ executable: URL, within root: URL) -> Bool {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let executableComponents = executable.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard executableComponents.count == rootComponents.count + 5,
              Array(executableComponents.prefix(rootComponents.count)) == rootComponents else { return false }
        let relative = Array(executableComponents.dropFirst(rootComponents.count))
        guard relative[0] == "node-versions",
              relative[1].hasPrefix("v"),
              normalizedRuntimeVersion(String(relative[1].dropFirst())) != nil,
              relative[2] == "installation" else { return false }
        return relative[3] == "bin" && relative[4] == "node"
    }

    nonisolated static func major(of version: String) -> Int? {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard let plusFree = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        guard let main = plusFree.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        let parts = main.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        return Int(first)
    }

    nonisolated static func normalizedVersion(_ version: String) -> String? {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard let main = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        let components = main.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let base = components.first else { return nil }
        let numbers = base.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count >= 3, numbers.allSatisfy({ Int($0) != nil }) else { return nil }
        return numbers.prefix(3).joined(separator: ".")
    }

    /// Normalizes a concrete runtime version without discarding prerelease
    /// information. `normalizedVersion` is intentionally lossy for store and
    /// support-family comparisons; probe results must use this form instead.
    nonisolated static func normalizedRuntimeVersion(_ version: String) -> String? {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard !withoutPrefix.isEmpty else { return nil }

        let plusParts = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard plusParts.count <= 2, let main = plusParts.first, !main.isEmpty else { return nil }
        let mainParts = main.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let base = mainParts.first, !base.isEmpty else { return nil }
        let numbers = base.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ validNumericVersionComponent(String($0)) }) else { return nil }

        if mainParts.count == 2 {
            let identifiers = mainParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ validRuntimeIdentifier(String($0), disallowLeadingZeroNumeric: true) }) else { return nil }
        }
        if plusParts.count == 2 {
            let identifiers = plusParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ validRuntimeIdentifier(String($0), disallowLeadingZeroNumeric: false) }) else { return nil }
        }
        return withoutPrefix
    }

    private nonisolated static func validNumericVersionComponent(_ component: String) -> Bool {
        let scalars = Array(component.unicodeScalars)
        guard !scalars.isEmpty,
              scalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { return false }
        return scalars.count == 1 || scalars[0].value != 48
    }

    private nonisolated static func validRuntimeIdentifier(_ identifier: String, disallowLeadingZeroNumeric: Bool) -> Bool {
        let scalars = Array(identifier.unicodeScalars)
        guard !scalars.isEmpty,
              scalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57) ||
                  ($0.value >= 65 && $0.value <= 90) ||
                  ($0.value >= 97 && $0.value <= 122) ||
                  $0.value == 45
              }) else { return false }
        if disallowLeadingZeroNumeric,
           scalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
           scalars.count > 1,
           scalars[0].value == 48 {
            return false
        }
        return true
    }

    nonisolated static func expectedManagedNodeExecutable(
        for selector: String,
        within root: URL,
        executableAvailable: @Sendable (URL) -> Bool
    ) -> (url: URL?, failure: String?) {
        guard let normalized = normalizedRuntimeVersion(selector) else {
            return (nil, "fnm candidate \(selector) is not a concrete semantic version.")
        }
        let expected = root.appendingPathComponent("node-versions/v\(normalized)/installation/bin/node")
        let canonicalExpected = expected.resolvingSymlinksInPath().standardizedFileURL
        guard isManagedNodeExecutable(expected, within: root),
              executableAvailable(expected),
              managedNodeStoreVersion(canonicalExpected, within: root) == normalized else {
            return (nil, "fnm candidate \(normalized) has no executable in its managed node-versions store.")
        }
        return (expected, nil)
    }

    nonisolated static func managedNodeStoreVersion(_ executable: URL, within root: URL) -> String? {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let executableComponents = executable.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard executableComponents.count == rootComponents.count + 5,
              Array(executableComponents.prefix(rootComponents.count)) == rootComponents else { return nil }
        let relative = Array(executableComponents.dropFirst(rootComponents.count))
        guard relative[0] == "node-versions",
              relative[1].hasPrefix("v"),
              relative[2] == "installation",
              relative[3] == "bin",
              relative[4] == "node" else { return nil }
        return normalizedRuntimeVersion(String(relative[1].dropFirst()))
    }

    nonisolated static func displayVersion(_ version: String) -> String {
        let normalized = normalizedVersion(version) ?? version.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("v") ? normalized : "v\(normalized)"
    }

    /// Keeps the fnm default first, then preserves the bounded local inventory
    /// order. This is selection only; it never changes fnm's default.
    nonisolated static func orderedStableNodeCandidates(defaultVersion: String?, inventory: [String]) -> [String] {
        var result = [String]()
        var values = inventory
        if let defaultVersion { values.insert(defaultVersion, at: 0) }
        for value in values {
            // Check the selector as reported before normalization. Stripping a
            // prerelease suffix first would turn an RC into a false stable
            // candidate (for example, 24.22.0-rc.1 -> 24.22.0).
            guard case .supported = nodeStatus(value),
                  let normalized = normalizedVersion(value),
                  !result.contains(normalized) else { continue }
            result.append(normalized)
            if result.count == maximumFNMRuntimeCandidates { break }
        }
        return result
    }

    private nonisolated static func status(_ version: String, supportedMajors: Set<Int>) -> VersionStatus {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let major = major(of: value) else { return .unusable }
        let withoutPrefix = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard let plusFree = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true).first else { return .unusable }
        if plusFree.contains(where: { $0 == "-" }) { return .prerelease }
        guard normalizedVersion(value) != nil else { return .unusable }
        return supportedMajors.contains(major) ? .supported(major: major) : .unsupported
    }
}

nonisolated struct ProvisioningManagedNode: Equatable, Sendable {
    let version: String
    let executableURL: URL

    private init(version: String, executableURL: URL) {
        self.version = version
        self.executableURL = executableURL
    }

    /// Creates the only Node value that runtime inspection may hand to the
    /// model. The selector, store path, reported version, and canonical binary
    /// must all describe the same concrete managed installation.
    nonisolated static func validated(
        reportedVersion: String,
        actualExecutablePath: String,
        selector: String,
        expectedExecutableURL: URL,
        root: URL,
        executableAvailable: @Sendable (URL) -> Bool
    ) -> (node: ProvisioningManagedNode?, failure: String?) {
        // Keep the probe's raw path as data until this invariant is checked.
        // URL(fileURLWithPath:) resolves relative paths against the process cwd.
        guard !actualExecutablePath.isEmpty, actualExecutablePath.hasPrefix("/") else {
            return (nil, "Node \(selector) reported a non-absolute executable path.")
        }
        let actualExecutableURL = URL(fileURLWithPath: actualExecutablePath)
        guard let actualVersion = ProvisioningRuntimePolicy.normalizedRuntimeVersion(reportedVersion) else {
            return (nil, "Node reported an invalid version \(reportedVersion).")
        }
        guard let selectedVersion = ProvisioningRuntimePolicy.normalizedRuntimeVersion(selector) else {
            return (nil, "fnm selector \(selector) is not a concrete semantic version.")
        }
        guard let expected = ProvisioningRuntimePolicy.expectedManagedNodeExecutable(
            for: selector,
            within: root,
            executableAvailable: executableAvailable
        ).url, expected == expectedExecutableURL else {
            return (nil, "fnm candidate \(selectedVersion) has no executable in its managed node-versions store.")
        }
        let canonicalActual = actualExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalExpected = expectedExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        guard ProvisioningRuntimePolicy.managedNodeStoreVersion(canonicalExpected, within: root) == selectedVersion else {
            return (nil, "fnm candidate \(selectedVersion) resolved to a different managed store version.")
        }
        guard executableAvailable(canonicalActual) else {
            return (nil, "Node \(selectedVersion) reported a missing or non-executable binary at \(canonicalActual.path).")
        }
        guard ProvisioningRuntimePolicy.isManagedNodeExecutable(canonicalActual, within: root) else {
            return (nil, "Node \(selectedVersion) reported an executable outside its managed node-versions store.")
        }
        guard canonicalActual == canonicalExpected else {
            return (nil, "Node \(selectedVersion) reported a different managed executable at \(canonicalActual.path).")
        }
        guard actualVersion == selectedVersion else {
            return (nil, "Node selector \(selectedVersion) reported version \(actualVersion); the selected managed installation is inconsistent.")
        }
        return (ProvisioningManagedNode(version: actualVersion, executableURL: canonicalActual), nil)
    }
}

nonisolated struct ProvisioningRuntimeContext: Equatable, Sendable {
    let nodeVersion: String
    let nodeExecutableURL: URL
    let pnpmVersion: String?
    let pnpmExecutableURL: URL?
    let fnmExecutableURL: URL?
    let fnmSelector: String?
    /// The exact fnm data root used for every probe and subsequent operation.
    /// Inspector-created contexts are validated against this managed store.
    let chosenFNMDirectoryURL: URL

    nonisolated init(
        nodeVersion: String,
        nodeExecutableURL: URL,
        pnpmVersion: String?,
        pnpmExecutableURL: URL?,
        fnmExecutableURL: URL,
        fnmSelector: String,
        chosenFNMDirectoryURL: URL
    ) {
        self.nodeVersion = nodeVersion
        self.nodeExecutableURL = nodeExecutableURL
        self.pnpmVersion = pnpmVersion
        self.pnpmExecutableURL = pnpmExecutableURL
        self.fnmExecutableURL = fnmExecutableURL
        self.fnmSelector = fnmSelector
        self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
    }

    /// Structural validation is deliberately path-component based, so a root
    /// such as `/tmp/fnm-evil` cannot pass a naive string-prefix check.
    var isManagedByFNM: Bool {
        guard let fnmSelector, fnmExecutableURL != nil else { return false }
        return !fnmSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ProvisioningRuntimePolicy.isManagedNodeExecutable(nodeExecutableURL, within: chosenFNMDirectoryURL)
    }
    var hasUsablePnpm: Bool {
        guard let pnpmVersion, pnpmExecutableURL != nil else { return false }
        return ProvisioningRuntimePolicy.isSupportedPnpmVersion(pnpmVersion)
    }
}
