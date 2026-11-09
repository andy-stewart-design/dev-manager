import SwiftUI

/// Website discovery content used by the Execution section. Website state is
/// independent from the command lifecycle; browser actions are offered only
/// for a currently ready, running site.
struct SiteStatusView: View {
    let state: SiteDiscoveryState
    let isOpeningWebsite: Bool
    let canOpenWebsite: Bool
    let siteActionError: String?
    let onOpen: (LocalSite) -> Void

    var body: some View {
        switch state.phase {
        case .inactive:
            Label("Not active", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        case .discovering:
            Label("Discovering…", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .responding:
            readyContent
        case .noSite:
            Label("No local site detected", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case let .diagnostic(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if state.sites.count == 1, let site = state.sites.first {
            readyRow(description: site.candidate.absoluteString) {
                Button("Open in Browser", systemImage: "safari") {
                    onOpen(site)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canOpenWebsite || isOpeningWebsite)
            }
        } else if state.sites.count > 1 {
            readyRow(description: "Multiple local sites detected") {
                Menu("Open in Browser", systemImage: "safari") {
                    ForEach(state.sites, id: \.candidate.absoluteString) { site in
                        Button(site.candidate.absoluteString) { onOpen(site) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canOpenWebsite || isOpeningWebsite)
            }
        } else {
            Label("Ready, but no site URL is available", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }

        if let siteActionError {
            Label(siteActionError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private func readyRow<Controls: View>(description: String, @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .center) {
            Label {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Ready")
                        .font(.body)
                        .foregroundStyle(.green)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(description)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer(minLength: 8)
            controls()
        }
    }
}
