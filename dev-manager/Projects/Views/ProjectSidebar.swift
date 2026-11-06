import SwiftUI

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selection: UUID?
    let isAddDisabled: Bool
    let onAdd: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                ProjectRow(project: project)
                    .tag(project.id)
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem {
                Button(action: onAdd) {
                    Label("Add Project", systemImage: "plus")
                }
                .disabled(isAddDisabled)
                .help("Register a local project folder")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.validationError == nil ? "folder" : "folder.badge.questionmark")
                .foregroundStyle(project.validationError == nil ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                Text(project.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
