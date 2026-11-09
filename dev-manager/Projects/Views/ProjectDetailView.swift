import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @ObservedObject var store: ProjectStore
    @ObservedObject var runner: ProjectRunner
    @State private var settingsProject: Project?
    private let executionRowMinimumHeight: CGFloat = 32

    var body: some View {
        Form {
            executionSection
            outputSection
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Capture the identity and values used to open the sheet. The
                    // sheet saves by this stable ID, not by a later selection.
                    settingsProject = project
                } label: {
                    Label("Project Settings", systemImage: "gearshape")
                }
                .accessibilityLabel("Project Settings")
                .help("Project Settings")
            }
        }
        .sheet(item: $settingsProject) { capturedProject in
            ProjectSettingsSheet(project: capturedProject, store: store, runner: runner)
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
            .frame(minHeight: executionRowMinimumHeight)

            SiteStatusView(
                state: state?.siteState ?? .inactive,
                isOpeningWebsite: state?.isOpeningWebsite ?? false,
                canOpenWebsite: state?.phase == .running,
                siteActionError: state?.siteActionError,
                onOpen: { site in
                    Task { await runner.openWebsite(projectID: project.id, site: site) }
                }
            )
            .frame(minHeight: executionRowMinimumHeight, alignment: .leading)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        let state = runner.state(for: project.id)
        Section("Output") {
            ProjectOutputView(state: state)
        }
    }
}
