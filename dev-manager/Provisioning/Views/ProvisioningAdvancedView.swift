import AppKit
import SwiftUI

struct AdvancedProvisioningSheet: View {
    @ObservedObject var model: ProvisioningModel
    @Environment(\.dismiss) private var dismiss
    let onRequestConsent: (ProvisioningConsent) -> Void
#if DEBUG
    let onShowFixture: () -> Void
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Advanced setup")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let presentation = model.messagePresentation,
                       presentation.isError || (model.activeInspectionID != nil && model.activeInspectionTargetID == nil && model.activeToolID == nil) {
                        Label {
                            Text(presentation.text)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: presentation.isError ? "exclamationmark.triangle.fill" : "ellipsis.circle")
                        }
                        .font(.callout)
                        .foregroundStyle(presentation.isError ? Color.orange : Color.secondary)
                    }

                    Button {
                        Task { await model.checkAgain() }
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)

#if DEBUG
                    Button {
                        onRequestConsent(.prepareFixture)
                    } label: {
                        Label("Prepare fixture project", systemImage: "shippingbox")
                    }
                    .disabled(!model.canPrepareFixture)
                    .help("Prepare the owned fixture only after fnm, Node, and pnpm are ready. No tools are installed by this action.")

                    if model.fixtureURL != nil, model.fixtureCommand != nil {
                        Button("Show fixture project", systemImage: "folder") {
                            onShowFixture()
                        }
                        .disabled(model.isBusy)
                    }
#endif
                    GroupBox("Optional future interactive Zsh sessions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You may add one marked block to ~/.zshrc. It makes fnm-managed Node and pnpm available in future interactive Zsh sessions; it is optional for this app. ~/.zprofile is never edited.")
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
                                .help("Available only when no shell setup is found; Dev Manager will not overwrite recognized or ambiguous external fnm setup.")
                                Button("Check fresh Zsh", systemImage: "terminal") {
                                    Task { await model.verifyFreshShell() }
                                }
                                .disabled(!model.canVerifyShell)
                                .help("Explicitly verify a fresh interactive Zsh. A recognized external initializer is not proof that every shell runs it.")
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    onRequestConsent(.restoreShell)
                                }
                                .disabled(!model.canRestoreShell)
                                .help("Restore only an unchanged app-owned block or acknowledge a recoverable app-owned receipt; external setup is never adopted.")
                            }
                            if !model.shellVerificationOutput.isEmpty {
                                outputView(model.shellVerificationOutput)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let warning = model.installationLogWarning {
                        Label {
                            Text(warning)
                                .textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

                    if let failureLogURL = model.installationFailureLogURL {
                        Button("Reveal failed installation log", systemImage: "doc.text.magnifyingglass") {
                            revealLog(failureLogURL)
                        }
                        .help("Reveal the log written for the latest runtime installation failure.")
                    } else if let logURL = model.installationLogURL {
                        Button("Reveal installation log", systemImage: "doc.text.magnifyingglass") {
                            revealLog(logURL)
                        }
                        .help("Reveal the app-owned provisioning installation log.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 650, minHeight: 400, idealHeight: 500)
    }

    private func revealLog(_ url: URL) {
        guard ProvisioningInstallationLog.existingLogURL() == url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
