import SwiftUI

struct CommandEditor: View {
    let project: Project
    @ObservedObject var store: ProjectStore
    @State private var commandDraft: String
    @State private var didSaveCommand = false

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
        _commandDraft = State(initialValue: project.command)
    }

    var body: some View {
        Section("Development Command") {
            LabeledContent {
                HStack(spacing: 8) {
                    TextField("", text: $commandDraft)
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
                        .onSubmit(saveCommand)

                    Button("Save Command", action: saveCommand)
                        .disabled(commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || commandDraft == project.command || store.isReadOnly)
                    if didSaveCommand {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } label: {
                Text("Command")
            }
            .labeledContentStyle(LeadingCommandLabeledContentStyle())

            if commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("The development command cannot be blank.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text("The command is saved as text and is not run when the project is added or restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: project.command) { _, command in
            commandDraft = command
            didSaveCommand = false
        }
    }

    private func saveCommand() {
        do {
            try store.updateCommand(for: project.id, command: commandDraft)
            didSaveCommand = true
        } catch {
            didSaveCommand = false
            store.report(error: error)
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
