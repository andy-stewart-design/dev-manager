import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var store: ProjectStore
    @ObservedObject var runner: ProjectRunner
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

            executionSection
            outputSection

            Section {
                Button("Remove Project…", role: .destructive) {
                    isShowingRemoveConfirmation = true
                }
                .disabled(store.isReadOnly || !runner.canRemove(projectID: project.id))
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
    private var executionSection: some View {
        let state = runner.state(for: project.id)
        Section("Execution") {
            HStack {
                if let state {
                    Label(state.phase.title, systemImage: state.phase == .failed ? "xmark.octagon" : "circle.fill")
                        .foregroundStyle(state.phase == .failed ? .red : (state.isActive ? .blue : .secondary))
                    if let message = state.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Label("Not started", systemImage: "circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if runner.canStop(projectID: project.id) {
                    Button("Stop", systemImage: "stop.fill") {
                        runner.stop(projectID: project.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(state?.phase == .stopping)
                } else {
                    Button("Start", systemImage: "play.fill") {
                        _ = runner.start(project: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!runner.canStart(projectID: project.id) || project.validationError != nil || project.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            SiteStatusView(
                state: state?.siteState ?? .inactive,
                isOpeningWebsite: state?.isOpeningWebsite ?? false,
                canOpenWebsite: state?.phase == .running,
                siteActionError: state?.siteActionError,
                onOpen: { site in
                    Task { await runner.openWebsite(projectID: project.id, site: site) }
                }
            )
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        let state = runner.state(for: project.id)
        if let state, state.isActive || !state.logs.isEmpty || state.didTruncateLogs || state.cleanupError != nil {
            Section("Output") {
                ProjectOutputView(state: state)
            }
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
        // The confirmation may outlive a state change in another window. Recheck on
        // the main actor immediately before the synchronous store mutation.
        guard runner.canRemove(projectID: project.id) else {
            store.report(error: ProjectRunnerError.projectBusy)
            return
        }
        do {
            try store.removeProject(id: project.id)
        } catch {
            store.report(error: error)
        }
    }
}
