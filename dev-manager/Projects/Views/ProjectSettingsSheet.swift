import AppKit
import SwiftUI

struct ProjectSettingsSheet: View {
    let project: Project
    @ObservedObject var store: ProjectStore
    @ObservedObject var runner: ProjectRunner
    @Environment(\.dismiss) private var dismiss
    @State private var commandDraft: String
    @State private var errorMessage: String?
    @State private var isShowingRemoveConfirmation = false

    init(project: Project, store: ProjectStore, runner: ProjectRunner) {
        self.project = project
        self.store = store
        self.runner = runner
        _commandDraft = State(initialValue: project.command)
    }

    private var trimmedCommand: String {
        commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCommandChanges: Bool {
        commandDraft != project.command
    }

    private var canSave: Bool {
        !store.isReadOnly && !trimmedCommand.isEmpty && hasCommandChanges
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: project.folderURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private var canRemove: Bool {
        !store.isReadOnly && runner.canRemove(projectID: project.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings for \(project.name)")
                .font(.title2)
                .padding(.horizontal)
                .padding(.top)

            Form {
                Section("Project") {
                    ProjectInfoRow(title: "Name") {
                        Text(project.name)
                            .textSelection(.enabled)
                    }

                    ProjectInfoRow(title: "Folder") {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([project.folderURL])
                        } label: {
                            Text(project.folderPath)
                                .font(.body.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(folderExists ? Color.accentColor : Color.secondary)
                        .disabled(!folderExists)
                        .help(folderExists ? "Reveal folder in Finder" : "The project folder is unavailable.")
                        .accessibilityLabel("Folder")
                        .accessibilityValue(project.folderPath)
                        .accessibilityHint(folderExists ? "Reveals this folder in Finder." : "The project folder is unavailable.")
                    }

                    if !folderExists {
                        Label("The saved project folder is unavailable.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Development Command") {
                    LabeledContent {
                        TextField("Command", text: $commandDraft)
                            .labelsHidden()
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.background)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary)
                            }
                            .accessibilityLabel("Command")
                            .disabled(store.isReadOnly)
                            .onSubmit(saveCommand)
                    } label: {
                        Text("Command")
                    }
                    .labeledContentStyle(LeadingCommandLabeledContentStyle())

                    if trimmedCommand.isEmpty {
                        Label("The development command cannot be blank.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if hasCommandChanges, runner.state(for: project.id)?.isActive == true {
                        Label("This change applies the next time the project is started.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

            }
            .formStyle(.grouped)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Button("Remove Project…", role: .destructive) {
                    isShowingRemoveConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canRemove)
                .help(store.isReadOnly ? "Project settings are read-only." : "Stop this project and wait for cleanup before removing it.")
                .accessibilityHint(store.isReadOnly ? "Project settings are read-only." : "Stop this project and wait for cleanup before removing it.")

                Spacer(minLength: 16)

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save", action: saveCommand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 390)
        .alert("Remove \(project.name)?", isPresented: $isShowingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Project", role: .destructive, action: removeProject)
        } message: {
            Text("This removes only the saved project entry from Dev Manager. The folder and all files on disk will be left untouched.")
        }
    }

    private func saveCommand() {
        guard canSave else { return }
        do {
            try store.updateCommand(for: project.id, command: commandDraft)
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            store.report(error: error)
        }
    }

    private func removeProject() {
        // Confirmation can outlive a run-state change. The runner remains the
        // authority immediately before the stable-ID store mutation.
        guard runner.canRemove(projectID: project.id) else {
            let error = ProjectRunnerError.projectBusy
            errorMessage = error.localizedDescription
            store.report(error: error)
            return
        }

        do {
            try store.removeProject(id: project.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            store.report(error: error)
        }
    }
}

private struct ProjectInfoRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LeadingCommandLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
            configuration.content
            Spacer(minLength: 0)
        }
    }
}
