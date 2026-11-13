import Foundation

/// Pure ordering and PATH composition for read-only runtime probes. It does not
/// inspect the filesystem or mutate the process environment.
nonisolated enum ProvisioningExecutablePaths {
    nonisolated static let knownPnpmLocations = [
        URL(fileURLWithPath: "/opt/homebrew/bin/pnpm"),
        URL(fileURLWithPath: "/usr/local/bin/pnpm"),
        URL(fileURLWithPath: "/usr/bin/pnpm"),
        URL(fileURLWithPath: "/bin/pnpm")
    ]

    nonisolated static func orderedCandidates(
        name: String,
        prior: [URL] = [],
        known: [URL] = [],
        inheritedPATH: String,
        maximum: Int = ProvisioningRuntimePolicy.maximumExecutableCandidates
    ) -> [URL] {
        let inherited = inheritedPATH
            .split(separator: ":")
            .prefix(ProvisioningRuntimePolicy.maximumInheritedPATHEntries)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(name) }
        return Array(unique(prior + known + inherited).prefix(maximum))
    }

    nonisolated static func pnpmCandidates(
        prior: [URL] = [],
        selectedNodeURL: URL? = nil,
        inheritedPATH: String,
        maximum: Int = ProvisioningRuntimePolicy.maximumExecutableCandidates
    ) -> [URL] {
        let selectedNodePnpm = selectedNodeURL.map {
            $0.deletingLastPathComponent().appendingPathComponent("pnpm")
        }.map { [$0] } ?? []
        return orderedCandidates(
            name: "pnpm",
            prior: prior + selectedNodePnpm,
            known: knownPnpmLocations,
            inheritedPATH: inheritedPATH,
            maximum: maximum
        )
    }

    /// The selected Node directory wins for a direct external pnpm probe. The
    /// inherited PATH and fixed system locations remain available afterward,
    /// without changing the app's global environment.
    nonisolated static func runtimePATH(
        selectedNodeURL: URL,
        inheritedPATH: String,
        safeSystemPATH: String = ProvisioningConfiguration.safeSystemPATH,
        maximum: Int = ProvisioningRuntimePolicy.maximumInheritedPATHEntries
    ) -> String {
        let selected = [selectedNodeURL.deletingLastPathComponent().path]
        let inherited = pathComponents(inheritedPATH)
        let safe = pathComponents(safeSystemPATH)
        let inheritedLimit = max(0, maximum - selected.count - safe.count)
        return uniquePathComponents(selected + Array(inherited.prefix(inheritedLimit)) + safe)
            .prefix(maximum)
            .joined(separator: ":")
    }

    private nonisolated static func pathComponents(_ path: String) -> [String] {
        path.split(separator: ":").filter { !$0.isEmpty }.map(String.init)
    }

    private nonisolated static func unique(_ candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private nonisolated static func uniquePathComponents(_ components: [String]) -> [String] {
        var seen = Set<String>()
        return components.filter { seen.insert($0).inserted }
    }
}
