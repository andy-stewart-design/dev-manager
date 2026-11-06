import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var store: ProjectStore
    @State private var isShowingRemoveConfirmation = false

    var body: some View {
        Form {
            Section("Project") {
                LabeledContent("Name", value: project.name)
                LabeledContent {
                    Text(project.folderPath)
                        .textSelection(.enabled)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Folder")
                }

                folderStatus
            }

            CommandEditor(project: project, store: store)

            Section("Execution") {
                Label("Start and Stop controls will be added with command execution in Step 1.2.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Remove Project…", role: .destructive) {
                    isShowingRemoveConfirmation = true
                }
                .disabled(store.isReadOnly)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle(project.name)
        .alert("Remove \(project.name)?", isPresented: $isShowingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Project", role: .destructive, action: removeProject)
        } message: {
            Text("This removes only the saved project entry from Dev Manager. The folder and all files on disk will be left untouched.")
        }
    }

    @ViewBuilder
    private var folderStatus: some View {
        if let validationError = project.validationError {
            Label(validationError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        } else {
            Label("Folder is available.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func removeProject() {
        do {
            try store.removeProject(id: project.id)
        } catch {
            store.report(error: error)
        }
    }
}
