import SwiftUI

/// Read-only website discovery status. It deliberately has no browser action;
/// opening a site is a later integration step.
struct SiteStatusView: View {
    let state: SiteDiscoveryState

    var body: some View {
        Section("Local Site") {
            switch state.phase {
            case .inactive:
                Label("Not active", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            case .discovering:
                Label("Discovering…", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
            case .responding:
                ForEach(state.sites, id: \.candidate.absoluteString) { site in
                    Label("Ready: \(site.candidate.absoluteString)", systemImage: "globe")
                        .textSelection(.enabled)
                }
            case .noSite:
                Label("No local site detected", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            case let .diagnostic(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }
}
