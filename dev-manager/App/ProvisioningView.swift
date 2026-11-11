#if DEBUG
import SwiftUI

struct ProvisioningView: View {
    @StateObject private var model = ProvisioningModel()
    @Environment(\.dismiss) private var dismiss
    let onFixtureReady: (URL, String) -> Void

    init(onFixtureReady: @escaping (URL, String) -> Void = { _, _ in }) {
        self.onFixtureReady = onFixtureReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Development setup", systemImage: "wrench.and.screwdriver")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Debug-only diagnostics. Checks are read-only and do not source or edit shell files.")
                .foregroundStyle(.secondary)

            if let issue = model.supportedEnvironmentIssue {
                Label("Machine-changing setup is disabled: \(issue).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            List(model.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    statusIcon(for: check.state)
                        .foregroundStyle(color(for: check.state))
                        .frame(width: 18, height: 18)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: check.state))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.id.title)
                            .fontWeight(.medium)
                        Text(detail(for: check.state))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)

            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !model.installationOutput.isEmpty {
                ScrollView {
                    Text(model.installationOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
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
                            model.isShowingShellConfigurationConsent = true
                        }
                        .disabled(!model.canConfigureShell)
                        Button("Check fresh Zsh", systemImage: "terminal") {
                            Task { await model.verifyFreshShell() }
                        }
                        .disabled(!model.canVerifyShell)
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            model.isShowingShellRestoreConsent = true
                        }
                        .disabled(!model.canRestoreShell)
                    }
                    if !model.shellVerificationOutput.isEmpty {
                        ScrollView {
                            Text(model.shellVerificationOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 70)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    Task { await model.checkAgain() }
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .disabled(model.isChecking || model.isRequestingCommandLineTools || model.isDownloadingHomebrew || model.isInstallingRuntime || model.isConfiguringShell || model.isVerifyingShell || model.isRestoringShell)

                Button {
                    model.isShowingCommandLineToolsConsent = true
                } label: {
                    Label("Request Command Line Tools…", systemImage: "arrow.down.circle")
                }
                .disabled(!model.canRequestCommandLineTools)

                Button {
                    model.isShowingHomebrewConsent = true
                } label: {
                    Label("Download Homebrew.pkg…", systemImage: "shippingbox")
                }
                .disabled(!model.canRequestHomebrew)

                Spacer()
            }

            HStack {
                Button {
                    model.isShowingRuntimeConsent = true
                } label: {
                    Label("Install runtime / prepare fixture", systemImage: "shippingbox.and.arrow.down")
                }
                .disabled(!model.canInstallRuntime)

                if let fixtureURL = model.fixtureURL, let fixtureCommand = model.fixtureCommand {
                    Button("Show fixture project", systemImage: "folder") {
                        onFixtureReady(fixtureURL, fixtureCommand)
                        dismiss()
                    }
                    .disabled(model.isInstallingRuntime)
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(width: 700, height: 690)
        .task {
            if model.checks.isEmpty {
                await model.checkAgain()
            }
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

    private func detail(for state: ProvisioningCheck.State) -> String {
        switch state {
        case .checking: return "Checking…"
        case let .waiting(detail), let .unverified(detail), let .ready(detail), let .missing(detail), let .attention(detail): return detail
        }
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
        case .checking: return .secondary
        case .waiting: return .secondary
        case .unverified: return .secondary
        case .ready: return .green
        case .missing: return .secondary
        case .attention: return .orange
        }
    }
}
#endif
