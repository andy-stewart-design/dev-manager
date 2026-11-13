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

nonisolated struct ProvisioningRuntimeContext: Equatable, Sendable {
    let nodeVersion: String
    let nodeExecutableURL: URL
    let pnpmVersion: String?
    let pnpmExecutableURL: URL?
    let fnmExecutableURL: URL?
    let fnmSelector: String?
    /// The exact fnm data root used for every probe and subsequent operation.
    /// This remains optional for unmanaged GUI Node contexts.
    let chosenFNMDirectoryURL: URL?

    nonisolated init(
        nodeVersion: String,
        nodeExecutableURL: URL,
        pnpmVersion: String?,
        pnpmExecutableURL: URL?,
        fnmExecutableURL: URL?,
        fnmSelector: String?,
        chosenFNMDirectoryURL: URL? = nil
    ) {
        self.nodeVersion = nodeVersion
        self.nodeExecutableURL = nodeExecutableURL
        self.pnpmVersion = pnpmVersion
        self.pnpmExecutableURL = pnpmExecutableURL
        self.fnmExecutableURL = fnmExecutableURL
        self.fnmSelector = fnmSelector
        self.chosenFNMDirectoryURL = chosenFNMDirectoryURL
    }

    var isManagedByFNM: Bool {
        fnmExecutableURL != nil && fnmSelector != nil && chosenFNMDirectoryURL != nil
    }
    var hasUsablePnpm: Bool {
        guard let pnpmVersion, pnpmExecutableURL != nil else { return false }
        return ProvisioningRuntimePolicy.isSupportedPnpmVersion(pnpmVersion)
    }
}
