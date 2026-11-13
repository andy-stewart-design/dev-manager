import SwiftUI

struct ProvisioningView: View {
    @StateObject private var model = ProvisioningModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingAdvancedSheet = false
    @State private var pendingConsent: ProvisioningConsent?
#if DEBUG
    @State private var pendingFixtureHandoff: FixtureHandoff?
    let onFixtureReady: (URL, String) -> Void

    init(onFixtureReady: @escaping (URL, String) -> Void = { _, _ in }) {
        self.onFixtureReady = onFixtureReady
    }
#else
    init() {}
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Development setup", systemImage: "wrench.and.screwdriver")
                        .font(.title2.weight(.semibold))
                        .contextMenu {
                            Button("Advanced setup…", systemImage: "slider.horizontal.3") {
                                isShowingAdvancedSheet = true
                            }
                        }
                        .help("Right-click the title for Advanced setup…")
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

            if !model.hasLoadedInitialInspection {
                VStack {
                    Spacer()
                    inspectionLoadingView
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ProvisioningStatusView(model: model, onRequestConsent: requestConsent)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 650, maxWidth: 760, minHeight: 420, idealHeight: 510, maxHeight: 760)
        .task {
            if model.checks.isEmpty {
                await model.checkAgain()
            }
        }
        .sheet(isPresented: $isShowingAdvancedSheet, onDismiss: handleAdvancedSheetDismissal) {
#if DEBUG
            AdvancedProvisioningSheet(
                model: model,
                onRequestConsent: presentConsentFromAdvanced,
                onShowFixture: showFixtureFromAdvanced
            )
#else
            AdvancedProvisioningSheet(
                model: model,
                onRequestConsent: presentConsentFromAdvanced
            )
#endif
        }
        .confirmationDialog(
            toolConsentTitle,
            isPresented: $model.isShowingToolConsent,
            titleVisibility: .visible
        ) {
            if let consent = pendingConsent, case let .tool(id) = consent {
                Button(toolConsentButtonTitle(for: id)) {
                    pendingConsent = nil
                    Task { await model.installTool(id) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingConsent = nil
            }
        } message: {
            Text(toolConsentMessage)
        }
#if DEBUG
        .confirmationDialog(
            "Prepare the fixture project?",
            isPresented: $model.isShowingFixtureConsent,
            titleVisibility: .visible
        ) {
            Button("Prepare fixture project") {
                pendingConsent = nil
                do { try model.prepareFixture() } catch { }
            }
            Button("Cancel", role: .cancel) {
                pendingConsent = nil
            }
        } message: {
            Text("Dev Manager will create or reuse only its owned fixture project under Application Support. It will not install or change any tools.")
        }
#endif
        .confirmationDialog(
            "Configure the optional ~/.zshrc block?",
            isPresented: $model.isShowingShellConfigurationConsent,
            titleVisibility: .visible
        ) {
            Button("Configure ~/.zshrc") {
                pendingConsent = nil
                do { try model.configureShell() } catch { }
            }
            Button("Cancel", role: .cancel) {
                pendingConsent = nil
            }
        } message: {
            Text("After your consent, Dev Manager will back up an existing regular ~/.zshrc, or record that it was absent, then append one marked block using the detected absolute fnm executable and its safely quoted parent directory on PATH. It will refuse symlinks, conflicting initialization, invalid or changed owned content, and never edit ~/.zprofile. This is optional and does not change project files.")
        }
        .confirmationDialog(
            "Restore the optional ~/.zshrc block?",
            isPresented: $model.isShowingShellRestoreConsent,
            titleVisibility: .visible
        ) {
            Button("Restore ~/.zshrc") {
                pendingConsent = nil
                do { try model.restoreShell() } catch { }
            }
            Button("Cancel", role: .cancel) {
                pendingConsent = nil
            }
        } message: {
            Text("Dev Manager will remove only its unchanged marked block, preserve unrelated content including later edits, and remove ~/.zshrc only when the app created it and nothing else remains. It will refuse unexpected changes instead of restoring a wholesale backup.")
        }
    }

    private var inspectionLoadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Inspecting installed tools…")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inspecting installed tools…")
    }

    private var toolConsentTitle: String {
        guard let pendingConsent, case let .tool(id) = pendingConsent else { return "Install selected tool?" }
        return "Install \(id.title)?"
    }

    private var toolConsentMessage: String {
        guard let pendingConsent else { return "Review the selected tool before continuing." }
        switch pendingConsent {
        case let .tool(id):
            return toolEffect(for: id)
#if DEBUG
        case .prepareFixture:
            return "Prepare only the owned fixture project."
#endif
        case .configureShell, .restoreShell:
            return "Review this optional shell action before continuing."
        }
    }

    private func toolConsentButtonTitle(for id: ProvisioningCheck.ID) -> String {
        switch id {
        case .developerTools: return "Request Apple installer"
        case .homebrew: return "Download and open Homebrew.pkg"
        default: return "Install \(id.title)"
        }
    }

    private func toolEffect(for id: ProvisioningCheck.ID) -> String {
        switch id {
        case .developerTools:
            return "Dev Manager will request Apple's graphical Command Line Tools installer. Opening the dialog is not completion; finish or cancel it, then use Check installation. No password is collected."
        case .homebrew:
            return "Dev Manager will download the official Homebrew.pkg and open it in macOS Installer. Complete or cancel that external installer, then use Check installation. No runtime tools will be installed by this action."
        case .fnm:
            return "Dev Manager will install fnm through the already verified Homebrew installation only. It will not install Node or pnpm, and will not edit shell files."
        case .node:
            return "Dev Manager will install the recommended Node \(ProvisioningRuntimePolicy.recommendedNodeVersion) through the already verified fnm installation only because no usable supported Node was detected. It will not replace an accepted existing Node or install pnpm."
        case .pnpm:
            let selectedNode = model.runtimeContext?.nodeVersion ?? "the selected Node context"
            return "Dev Manager will install the recommended pnpm \(ProvisioningRuntimePolicy.recommendedPnpmVersion) inside the selected Node \(selectedNode) context only because pnpm is missing. It will not replace an existing usable pnpm."
        }
    }

    private func requestConsent(_ consent: ProvisioningConsent) {
        pendingConsent = consent
        switch consent {
        case .tool:
            model.isShowingToolConsent = true
#if DEBUG
        case .prepareFixture:
            model.isShowingFixtureConsent = true
#endif
        case .configureShell:
            model.isShowingShellConfigurationConsent = true
        case .restoreShell:
            model.isShowingShellRestoreConsent = true
        }
    }

    private func presentConsentFromAdvanced(_ consent: ProvisioningConsent) {
        pendingConsent = consent
        isShowingAdvancedSheet = false
    }

#if DEBUG
    private func showFixtureFromAdvanced() {
        guard let fixtureURL = model.fixtureURL, let fixtureCommand = model.fixtureCommand else { return }
        pendingConsent = nil
        pendingFixtureHandoff = FixtureHandoff(url: fixtureURL, command: fixtureCommand)
        isShowingAdvancedSheet = false
    }
#endif

    private func handleAdvancedSheetDismissal() {
        guard let consent = pendingConsent else {
#if DEBUG
            if let fixture = pendingFixtureHandoff {
                pendingFixtureHandoff = nil
                onFixtureReady(fixture.url, fixture.command)
                dismiss()
            }
#endif
            return
        }
        switch consent {
        case .tool:
            model.isShowingToolConsent = true
#if DEBUG
        case .prepareFixture:
            model.isShowingFixtureConsent = true
#endif
        case .configureShell:
            model.isShowingShellConfigurationConsent = true
        case .restoreShell:
            model.isShowingShellRestoreConsent = true
        }
    }
}

nonisolated enum ProvisioningConsent: Sendable {
    case tool(ProvisioningCheck.ID)
#if DEBUG
    case prepareFixture
#endif
    case configureShell
    case restoreShell
}

#if DEBUG
nonisolated struct FixtureHandoff: Sendable {
    let url: URL
    let command: String
}
#endif
