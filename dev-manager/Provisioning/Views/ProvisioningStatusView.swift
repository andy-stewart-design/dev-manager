#if DEBUG
import SwiftUI

struct ProvisioningStatusView: View {
    @ObservedObject var model: ProvisioningModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let presentation = model.messagePresentation {
                noticeView(presentation)
            } else if let issue = model.supportedEnvironmentIssue {
                noticeView(.error("Machine-changing setup is disabled: \(issue)"))
            }

            statusRow(for: .developerTools)
            Divider()
            statusRow(for: .homebrew)
            Divider()
            nodeEnvironment
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var nodeEnvironment: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(
                title: "Node environment",
                state: runtimeEnvironmentState,
                detail: runtimeEnvironmentDetail,
                showInfo: false
            )
            VStack(alignment: .leading, spacing: 7) {
                statusRow(for: .fnm, indented: true)
                statusRow(for: .node, indented: true)
                statusRow(for: .pnpm, indented: true)
            }
        }
    }

    private func noticeView(_ presentation: ProvisioningModel.MessagePresentation) -> some View {
        Label {
            Text(presentation.text)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: presentation.isError ? "exclamationmark.triangle.fill" : "ellipsis.circle")
        }
        .font(.callout)
        .foregroundStyle(presentation.isError ? Color.orange : Color.secondary)
    }

    @ViewBuilder
    private func statusRow(for id: ProvisioningCheck.ID, indented: Bool = false) -> some View {
        if let check = model.checks.first(where: { $0.id == id }) {
            statusRow(title: id.title, state: check.state, detail: detail(for: check.state), indented: indented)
        }
    }

    private func statusRow(
        title: String,
        state: ProvisioningCheck.State,
        detail: String,
        indented: Bool = false,
        showInfo: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(for: state)
                .foregroundStyle(color(for: state))
                .frame(width: 18, height: 18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: state))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .fontWeight(.medium)
                    if showInfo {
                        ProvisioningInfoButton(title: title, detail: detail)
                    }
                }
                if isActionable(state) {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.leading, indented ? 26 : 0)
    }

    private var runtimeEnvironmentState: ProvisioningCheck.State {
        let states = [checkState(for: .fnm), checkState(for: .node), checkState(for: .pnpm)]
        if states.allSatisfy(\.isReady) { return .ready("All three components are ready.") }
        if states.contains(where: isStateAttention) { return .attention("One or more components needs attention.") }
        if states.contains(where: isStateChecking) { return .checking }
        if states.contains(where: isStateWaiting) { return .waiting("Waiting for a prerequisite check.") }
        if states.contains(where: isStateMissing) { return .missing("Install the missing components to run projects.") }
        return .unverified("Verify all three components before running projects.")
    }

    private var runtimeEnvironmentDetail: String {
        let details = [ProvisioningCheck.ID.fnm, .node, .pnpm].compactMap { id in
            model.checks.first(where: { $0.id == id }).map { "\(id.title): \(detail(for: $0.state))" }
        }
        return details.isEmpty ? "fnm, Node, and pnpm must all be ready." : details.joined(separator: "\n")
    }

    private func checkState(for id: ProvisioningCheck.ID) -> ProvisioningCheck.State {
        model.checks.first(where: { $0.id == id })?.state ?? .checking
    }

    private func detail(for state: ProvisioningCheck.State) -> String {
        switch state {
        case .checking: return "The app is checking this requirement."
        case let .waiting(detail), let .unverified(detail), let .ready(detail), let .missing(detail), let .attention(detail): return detail
        }
    }

    private func isActionable(_ state: ProvisioningCheck.State) -> Bool {
        if case .attention = state { return true }
        return false
    }

    private func isStateAttention(_ state: ProvisioningCheck.State) -> Bool {
        if case .attention = state { return true }
        return false
    }

    private func isStateChecking(_ state: ProvisioningCheck.State) -> Bool {
        if case .checking = state { return true }
        return false
    }

    private func isStateWaiting(_ state: ProvisioningCheck.State) -> Bool {
        if case .waiting = state { return true }
        return false
    }

    private func isStateMissing(_ state: ProvisioningCheck.State) -> Bool {
        if case .missing = state { return true }
        return false
    }

    @ViewBuilder
    private func statusIcon(for state: ProvisioningCheck.State) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "hourglass")
        case .unverified:
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.25, dash: [2, 2]))
                    .frame(width: 15, height: 15)
                Text("?")
                    .font(.system(size: 10, weight: .semibold))
            }
        case .checking:
            Image(systemName: "ellipsis.circle")
        case .ready:
            Image(systemName: "checkmark.circle.fill")
        case .missing:
            Image(systemName: "circle.dashed")
        case .attention:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private func accessibilityLabel(for state: ProvisioningCheck.State) -> String {
        switch state {
        case .checking: return "Checking"
        case .waiting: return "Waiting for external installer"
        case .unverified: return "Not yet verified"
        case .ready: return "Ready"
        case .missing: return "Missing"
        case .attention: return "Needs attention"
        }
    }

    private func color(for state: ProvisioningCheck.State) -> Color {
        switch state {
        case .checking, .waiting, .unverified, .missing: return .secondary
        case .ready: return .green
        case .attention: return .orange
        }
    }
}

struct ProvisioningInfoButton: View {
    let title: String
    let detail: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Show details for \(title)")
        .accessibilityHint("Opens selectable technical details")
        .help("Show technical details")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .textSelection(.enabled)
                    .frame(maxWidth: 380, alignment: .leading)
            }
            .padding(12)
        }
    }
}
#endif
