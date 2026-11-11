import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var runner: ProjectRunner
    @State private var selectedProjectID: UUID?
    @State private var isShowingFolderPicker = false
#if DEBUG
    @State private var isShowingProvisioning = false
#endif

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
#if DEBUG
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingProvisioning = true
                } label: {
                    Label("Setup", systemImage: "wrench.and.screwdriver")
                }
                .help("Open development-only tool setup diagnostics")
            }
        }
        .sheet(isPresented: $isShowingProvisioning) {
            ProvisioningView()
        }
#endif
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
