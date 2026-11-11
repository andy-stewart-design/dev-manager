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
                ProvisioningStatusView(model: model)
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
        case .checkInstallation: return "arrow.clockwise"
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
}

nonisolated enum ProvisioningConsent: Sendable {
    case runtime
    case configureShell
    case restoreShell
}

nonisolated struct FixtureHandoff: Sendable {
    let url: URL
    let command: String
}
#endif
