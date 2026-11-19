import SwiftUI

enum GitHubGroupPresentation: Equatable {
    case ready, checking, setup, unverified, attention

    static func derive(cli: ProvisioningCheck.State, hasContext: Bool, auth: GitHubAuthStatus?, host: String = "github.com") -> Self {
        if case .attention = cli { return .attention }
        if case .checking = cli { return .checking }
        guard cli.isReady, hasContext else { return .setup }
        guard let auth, auth.host == host else { return .setup }
        switch auth.outcome {
        case .authenticated: return .ready
        case .checking: return .checking
        case .notSignedIn: return .setup
        case .unverified: return .unverified
        case .invalidCredentials, .unavailable, .unsupported: return .attention
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .checking: return "ellipsis.circle"
        case .setup: return "circle.dashed"
        case .unverified: return "questionmark.circle"
        case .attention: return "exclamationmark.triangle.fill"
        }
    }
    var color: Color {
        switch self {
        case .ready: return .green
        case .attention: return .orange
        default: return .secondary
        }
    }
    var label: String {
        switch self {
        case .ready: return "GitHub ready"
        case .checking: return "Checking GitHub"
        case .setup, .unverified: return "GitHub needs setup"
        case .attention: return "GitHub needs attention"
        }
    }
}

struct ProvisioningStatusView: View {
    private enum Layout {
        static let rowMinimumHeight: CGFloat = 32
        static let rowVerticalPadding: CGFloat = 10
        static let groupHeadingBottomPadding: CGFloat = 0
        static let actionColumnMinimumWidth: CGFloat = 116
        static let nodeIndent: CGFloat = 26
        static let statusIconWidth: CGFloat = 18
        static let itemSpacing: CGFloat = 10

        static var nodeChildDividerLeadingInset: CGFloat {
            nodeIndent + statusIconWidth + itemSpacing
        }
    }

    @ObservedObject var model: ProvisioningModel
    let onRequestConsent: (ProvisioningConsent) -> Void

    init(model: ProvisioningModel, onRequestConsent: @escaping (ProvisioningConsent) -> Void = { _ in }) {
        self.model = model
        self.onRequestConsent = onRequestConsent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let presentation = model.messagePresentation,
               presentation.isError || (model.activeToolID == nil && model.activeInspectionID == nil) {
                noticeView(presentation)
            } else if let issue = model.supportedEnvironmentIssue {
                noticeView(.error("Machine-changing setup is disabled: \(issue)"))
            }

            VStack(alignment: .leading, spacing: 0) {
                statusRow(for: .developerTools)
                fullWidthDivider
                statusRow(for: .homebrew)
                fullWidthDivider
                gitHubEnvironment
                fullWidthDivider
                nodeEnvironment

                if model.allRuntimeToolsReady {
                    fullWidthDivider
                    optionalShellRow
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gitHubEnvironment: some View {
        let presentation = GitHubGroupPresentation.derive(
            cli: checkState(for: .githubCLI), hasContext: model.githubCLIContext != nil,
            auth: model.gitHubAuthStatus, host: model.selectedAuthHost
        )
        return VStack(alignment: .leading, spacing: 0) {
            rowLayout(
                leadingStatus: {
                    Image(systemName: presentation.icon)
                        .foregroundStyle(presentation.color)
                        .accessibilityLabel(presentation.label)
                },
                titleInfo: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("GitHub").fontWeight(.medium)
                    }
                },
                details: { EmptyView() },
                trailingAction: { EmptyView() },
                bottomPadding: Layout.groupHeadingBottomPadding
            )
            statusRow(for: .githubCLI, indented: true)
            nodeChildDivider
            gitHubAuthenticationRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gitHubAuthenticationRow: some View {
        let available = checkState(for: .githubCLI).isReady && model.githubCLIContext != nil
        let status = available ? model.gitHubAuthStatus : nil
        let presentation = authPresentation(status, available: available)
        let host = model.selectedAuthHost
        return rowLayout(
            leadingStatus: {
                Image(systemName: presentation.icon)
                    .foregroundStyle(presentation.color)
                    .accessibilityLabel(presentation.label)
            },
            titleInfo: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Authentication").fontWeight(.medium)
                    Text("\(host)")
                        .font(.callout)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                    ProvisioningInfoButton(title: "Authentication", detail: authDetail(status, host: host, available: available) + (model.plaintextWarningHosts.contains(host) ? " The CLI reported plaintext credential storage for this host." : ""))
                }
            },
            details: {
                if let status, let attention = authAttention(status) {
                    Text(attention)
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                        .textSelection(.enabled)
                }
            },
            trailingAction: {
                HStack {
                    if model.isCheckingGitHubAuth { ProgressView().controlSize(.small) }
                    Button { model.refreshGitHubAuthStatus() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Check status")
                        .disabled(!available || model.isBusy || model.isCheckingGitHubAuth)
                    Button("Sign in") { model.presentLogin() }
                        .buttonStyle(.bordered)
                        .disabled(!model.canPresentLogin)
                }
                .frame(minWidth: Layout.actionColumnMinimumWidth, alignment: .trailing)
            },
            leadingInset: Layout.nodeIndent
        )
    }

    private func authPresentation(_ status: GitHubAuthStatus?, available: Bool) -> (icon: String, color: Color, label: String) {
        guard available, let status else { return ("circle.dashed", .secondary, "Authentication not checked") }
        switch status.outcome {
        case .authenticated: return ("checkmark.circle.fill", .green, "Authenticated")
        case .notSignedIn: return ("circle.dashed", .secondary, "Not signed in")
        case .checking: return ("ellipsis.circle", .secondary, "Checking")
        case .invalidCredentials: return ("exclamationmark.triangle.fill", .orange, "Needs attention")
        case .unavailable, .unsupported: return ("exclamationmark.triangle.fill", .orange, "Authentication needs attention")
        case .unverified: return ("questionmark.circle", .secondary, "Authentication unverified")
        }
    }

    private var nodeEnvironment: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow(
                title: "Node environment",
                state: runtimeEnvironmentState,
                detail: runtimeEnvironmentDetail,
                showInfo: false,
                showDetails: false,
                bottomPadding: Layout.groupHeadingBottomPadding
            )
            VStack(alignment: .leading, spacing: 0) {
                statusRow(for: .fnm, indented: true)
                nodeChildDivider
                statusRow(for: .node, indented: true)
                nodeChildDivider
                statusRow(for: .pnpm, indented: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullWidthDivider: some View {
        Divider()
            .frame(maxWidth: .infinity)
    }

    private var nodeChildDivider: some View {
        Divider()
            .padding(.leading, Layout.nodeChildDividerLeadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionalShellRow: some View {
        let inspection = model.shellInspection
        let presentation = shellPresentation(inspection)
        return rowLayout(
            leadingStatus: {
                Image(systemName: presentation.icon)
                    .foregroundStyle(presentation.color)
                    .accessibilityLabel(presentation.accessibilityLabel)
            },
            titleInfo: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Optional shell configuration")
                        .fontWeight(.medium)
                    ProvisioningInfoButton(title: "Optional shell configuration", detail: presentation.detail)
                }
            },
            details: {
                EmptyView()
            },
            trailingAction: {
                if case .notConfigured = inspection, model.canConfigureShell {
                    Button("Configure") {
                        onRequestConsent(.configureShell)
                    }
                    .buttonStyle(.bordered)
                    .frame(minWidth: Layout.actionColumnMinimumWidth, alignment: .trailing)
                    .help("Optionally add the app-owned fnm block to ~/.zshrc for future interactive Zsh sessions.")
                }
            }
        )
    }

    private func shellPresentation(_ inspection: ProvisioningShellConfiguration.Inspection) -> (detail: String, icon: String, color: Color, accessibilityLabel: String) {
        switch inspection {
        case let .configured(message):
            return (message, "checkmark.circle.fill", .green, "App-managed and ready")
        case let .configuredExternally(message):
            return (message, "checkmark.circle.fill", .green, "Recognized external setup")
        case let .notConfigured(message):
            return (message, "circle.dashed", .secondary, "Optional and not configured")
        case let .unverified(message):
            return (message, "questionmark.circle", .secondary, "Shell setup is unverified")
        case let .conflict(message):
            return (message, "exclamationmark.triangle.fill", .orange, "Needs attention")
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
            statusRow(
                title: id.title,
                state: check.state,
                detail: detail(for: check.state),
                id: id,
                indented: indented,
                version: version(for: id, state: check.state)
            )
        }
    }

    @ViewBuilder
    private func statusRow(
        title: String,
        state: ProvisioningCheck.State,
        detail: String,
        id: ProvisioningCheck.ID? = nil,
        indented: Bool = false,
        showInfo: Bool = true,
        showDetails: Bool = true,
        bottomPadding: CGFloat? = nil,
        version: String? = nil
    ) -> some View {
        let action = id.map { model.rowAction(for: $0) }
        rowLayout(
            leadingStatus: {
                statusIcon(for: state)
                    .foregroundStyle(color(for: state))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: state))
            },
            titleInfo: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title)
                        .fontWeight(.medium)
                    if let version {
                        Text(version)
                            .font(.callout)
                            .fontWeight(.regular)
                            .foregroundStyle(.secondary)
                    }
                    if showInfo {
                        ProvisioningInfoButton(title: title, detail: detail)
                    }
                }
            },
            details: {
                if showDetails && isActionable(state) {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(Color.orange)
                        .textSelection(.enabled)
                }
            },
            trailingAction: {
                if let id, let action {
                    rowAction(action, for: id)
                }
            },
            leadingInset: indented ? Layout.nodeIndent : 0,
            bottomPadding: bottomPadding
        )
    }

    private func authAttention(_ status: GitHubAuthStatus) -> String? {
        switch status.outcome {
        case .invalidCredentials: return "Credentials could not be verified."
        case .unsupported(let reason):
            switch reason {
            case .invalidHost: return "The authentication host is invalid."
            case .cliVersion: return "A supported GitHub CLI version is required."
            case .capability: return "GitHub CLI does not support this authentication check."
            }
        case .unavailable(let reason):
            switch reason {
            case .timeout: return "The authentication check timed out."
            case .network: return "The authentication check encountered a network issue."
            case .tls: return "The authentication check encountered a TLS issue."
            }
        default: return nil
        }
    }

    private func authDetail(_ status: GitHubAuthStatus?, host: String, available: Bool) -> String {
        guard available else { return "Host: \(host)\nInstall GitHub CLI to check authentication." }
        guard let status else { return "Host: \(host)\nAuthentication status has not been checked." }
        let description: String
        switch status.outcome {
        case .checking: description = "Checking authentication status."
        case .notSignedIn: description = "Not signed in."
        case let .authenticated(login, source):
            let sourceName: String
            switch source {
            case .environment(let credential): sourceName = "App environment (\(credential.rawValue))"
            case .stored: sourceName = "Stored credential"
            case .keychain: sourceName = "Keychain"
            case .unknown: sourceName = "Unknown"
            }
            description = "Signed in as \(login).\nCredential source: \(sourceName)."
        case .invalidCredentials, .unsupported, .unavailable:
            description = authAttention(status) ?? "Authentication status unavailable."
        case .unverified: description = "Authentication status is unverified."
        }
        var detail = "Host: \(host)\nStatus: \(description)"
        if let credential = status.environmentCredential {
            detail += "\nEnvironment credential present: \(credential.rawValue)."
        }
        return detail
    }

    @ViewBuilder
    private func rowLayout<LeadingStatus: View, TitleInfo: View, Details: View, TrailingAction: View>(
        @ViewBuilder leadingStatus: () -> LeadingStatus,
        @ViewBuilder titleInfo: () -> TitleInfo,
        @ViewBuilder details: () -> Details,
        @ViewBuilder trailingAction: () -> TrailingAction,
        leadingInset: CGFloat = 0,
        bottomPadding: CGFloat? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: Layout.itemSpacing) {
            HStack(alignment: .center, spacing: Layout.itemSpacing) {
                leadingStatus()
                    .frame(width: Layout.statusIconWidth, height: Layout.statusIconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    titleInfo()
                    details()
                }
            }
            .padding(.leading, leadingInset)
            Spacer(minLength: 4)
            trailingAction()
        }
        .frame(maxWidth: .infinity, minHeight: Layout.rowMinimumHeight, alignment: .center)
        .padding(.top, Layout.rowVerticalPadding)
        .padding(.bottom, bottomPadding ?? Layout.rowVerticalPadding)
    }

    @ViewBuilder
    private func rowAction(_ action: ProvisioningModel.ToolRowAction, for id: ProvisioningCheck.ID) -> some View {
        switch action {
        case .none:
            EmptyView()
        case let .progress(label):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: Layout.actionColumnMinimumWidth, alignment: .trailing)
            .accessibilityLabel(label)
        case let .install(label, reason, enabled):
            Button(label) {
                onRequestConsent(.tool(id))
            }
            .buttonStyle(.bordered)
            .frame(minWidth: Layout.actionColumnMinimumWidth, alignment: .trailing)
            .disabled(!enabled)
            .help(reason)
            .accessibilityHint(reason)
        case let .check(label, reason, enabled):
            Button(label) {
                Task { await model.checkTool(id) }
            }
            .buttonStyle(.bordered)
            .frame(minWidth: Layout.actionColumnMinimumWidth, alignment: .trailing)
            .disabled(!enabled)
            .help(reason)
            .accessibilityHint(reason)
        }
    }

    private var runtimeEnvironmentState: ProvisioningCheck.State {
        let states = [checkState(for: .fnm), checkState(for: .node), checkState(for: .pnpm)]
        if states.allSatisfy(\.isSatisfied) {
            return .ready("All managed runtime components are ready.")
        }
        if states.contains(where: isActionable) { return .attention("One or more components needs attention.") }
        if states.contains(where: isStateChecking) { return .checking }
        if states.contains(where: isStateWaiting) { return .waiting("Waiting for a prerequisite check.") }
        if states.contains(where: isStateMissing) { return .missing("Install each missing component after its prerequisite is ready.") }
        return .unverified("Verify all three components before running projects.")
    }

    private var runtimeEnvironmentDetail: String {
        let details = [ProvisioningCheck.ID.fnm, .node, .pnpm].compactMap { id in
            model.checks.first(where: { $0.id == id }).map { "\(id.title): \(detail(for: $0.state))" }
        }
        return details.isEmpty ? "fnm, managed Node, and pnpm must be ready." : details.joined(separator: "\n")
    }

    private func version(for id: ProvisioningCheck.ID, state: ProvisioningCheck.State) -> String? {
        guard state.isReady else { return nil }
        switch id {
        case .node: return model.runtimeContext?.node.version
        case .pnpm: return model.runtimeContext?.pnpm?.version
        case .githubCLI: return model.githubCLIContext?.version
        default: return nil
        }
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
        case .checking:
            Image(systemName: "ellipsis.circle")
        case .ready:
            Image(systemName: "checkmark.circle.fill")
        case .unverified:
            Image(systemName: "circle.dashed")
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
