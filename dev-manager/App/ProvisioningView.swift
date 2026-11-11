#if DEBUG
import SwiftUI

struct ProvisioningView: View {
    @StateObject private var model = ProvisioningModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingAdvancedSheet = false
    @State private var pendingAdvancedConsent: ProvisioningConsent?
    @State private var pendingFixtureHandoff: FixtureHandoff?
    let onFixtureReady: (URL, String) -> Void

    init(onFixtureReady: @escaping (URL, String) -> Void = { _, _ in }) {
        self.onFixtureReady = onFixtureReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Development setup", systemImage: "wrench.and.screwdriver")
                        .font(.title2.weight(.semibold))
                        .contextMenu {
                            Button("Advanced / spike tools…", systemImage: "slider.horizontal.3") {
                                isShowingAdvancedSheet = true
                            }
                        }
                        .help("Right-click the title for Advanced / spike tools…")
                    Text("Set up the tools needed to run projects on this Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Close")
                .help("Close")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.bottom, 12)

            ScrollView {
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

            Divider()
                .padding(.top, 10)

            HStack {
                Spacer()
                Button {
                    performPrimaryAction()
                } label: {
                    Label(model.nextAction.title, systemImage: primaryActionIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!primaryActionIsEnabled)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 650, maxWidth: 760, minHeight: 420, idealHeight: 510, maxHeight: 760)
        .task {
            if model.checks.isEmpty {
                await model.checkAgain()
            }
        }
        .sheet(isPresented: $isShowingAdvancedSheet, onDismiss: handleAdvancedSheetDismissal) {
            AdvancedProvisioningSheet(
                model: model,
                onRequestConsent: presentConsentFromAdvanced,
                onShowFixture: showFixtureFromAdvanced
            )
        }
        .confirmationDialog(
            "Request Apple's Command Line Tools?",
            isPresented: $model.isShowingCommandLineToolsConsent,
            titleVisibility: .visible
        ) {
            Button("Request installer dialog") {
                model.requestCommandLineTools()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("macOS will show its own installer UI. Dev Manager does not collect a password and will not treat the request as installed. Complete or cancel Apple's dialog, then press Check again.")
        }
        .confirmationDialog(
            "Install the pinned runtime and prepare the fixture?",
            isPresented: $model.isShowingRuntimeConsent,
            titleVisibility: .visible
        ) {
            Button("Install fnm, Node, and pnpm") {
                Task { await model.installRuntimeAndPrepareFixture() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Dev Manager will reuse usable tools, install only missing exact versions as the current user, and never edit shell files. Existing conflicting or unusable tools are left unchanged. The fixture is created under Application Support only after all checks pass.")
        }
        .confirmationDialog(
            "Configure the optional ~/.zshrc block?",
            isPresented: $model.isShowingShellConfigurationConsent,
            titleVisibility: .visible
        ) {
            Button("Configure ~/.zshrc") {
                do { try model.configureShell() } catch { }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("After your consent, Dev Manager will back up an existing regular ~/.zshrc, or record that it was absent, then append one marked block using the detected absolute fnm executable and its safely quoted parent directory on PATH. It will refuse symlinks, conflicting initialization, invalid or changed owned content, and never edit ~/.zprofile. This is optional and not needed by the fixture.")
        }
        .confirmationDialog(
            "Restore the optional ~/.zshrc block?",
            isPresented: $model.isShowingShellRestoreConsent,
            titleVisibility: .visible
        ) {
            Button("Restore ~/.zshrc") {
                do { try model.restoreShell() } catch { }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Dev Manager will remove only its unchanged marked block, preserve unrelated content including later edits, and remove ~/.zshrc only when the app created it and nothing else remains. It will refuse unexpected changes instead of restoring a wholesale backup.")
        }
        .confirmationDialog(
            "Download and open Homebrew.pkg?",
            isPresented: $model.isShowingHomebrewConsent,
            titleVisibility: .visible
        ) {
            Button("Download and open Installer") {
                Task { await model.downloadAndOpenHomebrewPackage() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Dev Manager will fetch the exact Homebrew.pkg asset from Homebrew's official GitHub release, save it locally, and open it through macOS Installer. Complete or cancel Apple's UI there; no password is collected and opening the package is not installation success. Press Check again before retrying.")
        }
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

    private var primaryActionIsEnabled: Bool {
        switch model.nextAction {
        case .checkInstallation:
            return !model.isChecking && !model.isRequestingCommandLineTools && !model.isDownloadingHomebrew && !model.isInstallingRuntime
        case .installAppleDeveloperTools:
            return model.canRequestCommandLineTools
        case .installHomebrew:
            return model.canRequestHomebrew
        case .setupNodeAndPnpm:
            return model.canInstallRuntime
        case .configureShellOptional:
            return model.canConfigureShell
        case .done:
            return model.allRuntimeToolsReady
        case .checking, .openingAppleInstaller, .downloadingHomebrew, .installingRuntime, .working, .reviewDetails, .unsupported:
            return false
        }
    }

    private var primaryActionIcon: String {
        switch model.nextAction {
        case .checkInstallation: return "checkmark.magnifyingglass"
        case .installAppleDeveloperTools, .installHomebrew, .setupNodeAndPnpm: return "arrow.down.circle"
        case .configureShellOptional: return "pencil"
        case .done: return "checkmark"
        default: return "ellipsis.circle"
        }
    }

    private func performPrimaryAction() {
        switch model.nextAction {
        case .checkInstallation:
            Task { await model.checkAgain() }
        case .installAppleDeveloperTools:
            model.isShowingCommandLineToolsConsent = true
        case .installHomebrew:
            model.isShowingHomebrewConsent = true
        case .setupNodeAndPnpm:
            model.isShowingRuntimeConsent = true
        case .configureShellOptional:
            model.isShowingShellConfigurationConsent = true
        case .done:
            dismiss()
        default:
            break
        }
    }

    private func presentConsentFromAdvanced(_ consent: ProvisioningConsent) {
        pendingAdvancedConsent = consent
        pendingFixtureHandoff = nil
        isShowingAdvancedSheet = false
    }

    private func showFixtureFromAdvanced() {
        guard let fixtureURL = model.fixtureURL, let fixtureCommand = model.fixtureCommand else { return }
        pendingAdvancedConsent = nil
        pendingFixtureHandoff = FixtureHandoff(url: fixtureURL, command: fixtureCommand)
        isShowingAdvancedSheet = false
    }

    private func handleAdvancedSheetDismissal() {
        if let consent = pendingAdvancedConsent {
            pendingAdvancedConsent = nil
            switch consent {
            case .runtime:
                model.isShowingRuntimeConsent = true
            case .configureShell:
                model.isShowingShellConfigurationConsent = true
            case .restoreShell:
                model.isShowingShellRestoreConsent = true
            }
        } else if let fixture = pendingFixtureHandoff {
            pendingFixtureHandoff = nil
            onFixtureReady(fixture.url, fixture.command)
            dismiss()
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

private enum ProvisioningConsent {
    case runtime
    case configureShell
    case restoreShell
}

private struct FixtureHandoff {
    let url: URL
    let command: String
}

private struct ProvisioningInfoButton: View {
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

private struct AdvancedProvisioningSheet: View {
    @ObservedObject var model: ProvisioningModel
    @Environment(\.dismiss) private var dismiss
    let onRequestConsent: (ProvisioningConsent) -> Void
    let onShowFixture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Advanced / spike tools")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task { await model.checkAgain() }
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isChecking || model.isRequestingCommandLineTools || model.isDownloadingHomebrew || model.isInstallingRuntime || model.isConfiguringShell || model.isVerifyingShell || model.isRestoringShell)

                    Button {
                        onRequestConsent(.runtime)
                    } label: {
                        Label("Install runtime / prepare fixture", systemImage: "shippingbox.and.arrow.down")
                    }
                    .disabled(!model.canInstallRuntime)

                    if model.fixtureURL != nil, model.fixtureCommand != nil {
                        Button("Show fixture project", systemImage: "folder") {
                            onShowFixture()
                        }
                        .disabled(model.isInstallingRuntime)
                    }

                    GroupBox("Optional future interactive Zsh sessions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("After the no-shell-edit fixture proof, you may add one marked block to ~/.zshrc. It makes fnm-managed Node and pnpm available in future interactive Zsh sessions; it is not required for this app or its fixture. ~/.zprofile is never edited.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(model.shellConfigurationStatus)
                                .font(.callout)
                                .textSelection(.enabled)
                            HStack {
                                Button("Configure ~/.zshrc", systemImage: "pencil") {
                                    onRequestConsent(.configureShell)
                                }
                                .disabled(!model.canConfigureShell)
                                Button("Check fresh Zsh", systemImage: "terminal") {
                                    Task { await model.verifyFreshShell() }
                                }
                                .disabled(!model.canVerifyShell)
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    onRequestConsent(.restoreShell)
                                }
                                .disabled(!model.canRestoreShell)
                            }
                            if !model.shellVerificationOutput.isEmpty {
                                outputView(model.shellVerificationOutput)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !model.installationOutput.isEmpty {
                        DisclosureGroup("Installation output") {
                            outputView(model.installationOutput)
                                .padding(.top, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 650, minHeight: 400, idealHeight: 500)
    }

    private func outputView(_ output: String) -> some View {
        ScrollView {
            Text(output)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 100)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}
#endif
