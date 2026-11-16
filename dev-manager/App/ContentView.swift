import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var runner: ProjectRunner
    @State private var selectedProjectID: UUID?
    @State private var isShowingFolderPicker = false
    @State private var isShowingProvisioning = false

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(
                projects: store.projects,
                selection: $selectedProjectID,
                runPhases: runner.states.mapValues(\.phase),
                isAddDisabled: store.isReadOnly,
                onAdd: { isShowingFolderPicker = true }
            )
            .navigationSplitViewColumnWidth(ideal: 280)
        } detail: {
            if let selectedProjectID,
               let project = store.projects.first(where: { $0.id == selectedProjectID }) {
                ProjectDetailView(project: project, store: store, runner: runner)
                    .id(project.id)
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text("Add a project folder or select one from the list.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = store.errorMessage {
                StoreErrorBanner(message: errorMessage)
            }
        }
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingProvisioning = true
                } label: {
                    Label("Setup", systemImage: "wrench.and.screwdriver")
                }
                .help("Open tool setup and diagnostics")
            }
        }
        .sheet(isPresented: $isShowingProvisioning) {
#if DEBUG
            ProvisioningView { folderURL, command in
                handleFixtureHandoff(folderURL: folderURL, command: command)
            }
#else
            ProvisioningView()
#endif
        }
        .onChange(of: store.projects) { _, projects in
            if let selectedProjectID, projects.contains(where: { $0.id == selectedProjectID }) {
                return
            }
            selectedProjectID = projects.first?.id
        }
        .onAppear {
            selectedProjectID = selectedProjectID ?? store.projects.first?.id
        }
    }

#if DEBUG
    private func handleFixtureHandoff(folderURL: URL, command: String) {
        let normalizedPath = folderURL.standardizedFileURL.path
        do {
            if let existing = store.projects.first(where: { $0.folderURL.standardizedFileURL.path == normalizedPath }) {
                guard existing.command == command else {
                    throw FixtureProjectHandoffError.conflictingCommand(normalizedPath)
                }
                selectedProjectID = existing.id
            } else {
                let project = try store.addProject(folderURL: folderURL, command: command)
                selectedProjectID = project.id
            }
        } catch {
            store.report(error: error)
        }
    }
    private enum FixtureProjectHandoffError: LocalizedError {
        case conflictingCommand(String)

        var errorDescription: String? {
            switch self {
            case let .conflictingCommand(path):
                return "The existing fixture project at \(path) has a user-modified command, so it was left unchanged."
            }
        }
    }
#endif

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let folderURL = urls.first else { return }
            do {
                let project = try store.addProject(folderURL: folderURL)
                selectedProjectID = project.id
            } catch {
                store.report(error: error)
            }
        case let .failure(error):
            store.report(error: error)
        }
    }
}

private struct StoreErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

#Preview {
    ContentView(
        store: ProjectStore(settingsURL: URL(fileURLWithPath: "/tmp/dev-manager-preview-settings.json")),
        runner: ProjectRunner()
    )
}
