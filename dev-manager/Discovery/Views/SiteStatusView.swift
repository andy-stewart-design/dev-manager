import SwiftUI

/// Website discovery status and the narrow browser-action surface. The runner
/// facade performs the last-moment run and ownership validation.
struct SiteStatusView: View {
    let state: SiteDiscoveryState
    let isOpeningWebsite: Bool
    let siteActionError: String?
    let onOpen: (LocalSite) -> Void

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
                if state.sites.count == 1, let site = state.sites.first {
                    Button("Open in Browser: \(site.candidate.absoluteString)", systemImage: "safari") {
                        onOpen(site)
                    }
                    .disabled(isOpeningWebsite)
                } else if state.sites.count > 1 {
                    Menu("Open in Browser", systemImage: "safari") {
                        ForEach(state.sites, id: \.candidate.absoluteString) { site in
                            Button(site.candidate.absoluteString) { onOpen(site) }
                        }
                    }
                    .disabled(isOpeningWebsite)
                }
                if let siteActionError {
                    Label(siteActionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
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
