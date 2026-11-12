#if DEBUG
import SwiftUI

struct AdvancedProvisioningSheet: View {
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
