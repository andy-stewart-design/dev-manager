import SwiftUI

/// Shared process-phase presentation for the Execution section and project rows.
struct RunStatusLabel: View {
    let phase: RunPhase?
    let colorOverride: Color?

    init(phase: RunPhase?, colorOverride: Color? = nil) {
        self.phase = phase
        self.colorOverride = colorOverride
    }

    var body: some View {
        Label(title, systemImage: symbolName)
            .foregroundStyle(color)
            .help(title)
            .accessibilityLabel(title)
    }

    private var title: String {
        phase?.title ?? "Not started"
    }

    private var symbolName: String {
        phase == .running ? "circle.fill" : "circle"
    }

    private var color: Color {
        if let colorOverride {
            return colorOverride
        }
        switch phase {
        case .failed: return .red
        case .launching, .running, .stopping: return .blue
        case .none, .exited: return .secondary
        }
    }
}
