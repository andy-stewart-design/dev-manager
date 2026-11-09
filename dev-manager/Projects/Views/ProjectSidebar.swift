import SwiftUI

struct ProjectSidebar: View {
    let projects: [Project]
    @Binding var selection: UUID?
    let runPhases: [UUID: RunPhase]
    let isAddDisabled: Bool
    let onAdd: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                ProjectRow(project: project, phase: runPhases[project.id])
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
    let phase: RunPhase?

    var body: some View {
        HStack(spacing: 8) {
            RunStatusLabel(phase: phase, colorOverride: .white)
                .labelStyle(.iconOnly)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                Text(project.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let validationError = project.validationError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(validationError.localizedDescription)
                    .accessibilityLabel("Folder warning: \(validationError.localizedDescription)")
            }
        }
        .padding(.vertical, 2)
    }
}
