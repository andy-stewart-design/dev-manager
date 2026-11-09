import SwiftUI

/// Bounded terminal output for the selected project. The parent owns the Output
/// section so lifecycle and discovery content remain grouped separately.
struct ProjectOutputView: View {
    let state: RunState?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let state, !state.logs.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(state.logs) { entry in
                                Text("[\(entry.label)] \(entry.text)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text(state?.isActive == true ? "Waiting for output…" : "No output yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 280)
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            if state?.didTruncateLogs == true {
                Label("Older output was trimmed after the 2 MiB per-project log limit.", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let cleanupError = state?.cleanupError {
                Label(cleanupError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
