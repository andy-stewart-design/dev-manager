import SwiftUI

/// Bounded terminal output for the current run. The parent owns the Output
/// section so lifecycle and discovery content remain grouped separately.
struct ProjectOutputView: View {
    let state: RunState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if state.logs.isEmpty {
                        Text("Waiting for output…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(state.logs) { entry in
                                Text("[\(entry.label)] \(entry.text)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 120, maxHeight: 280)
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            if state.didTruncateLogs {
                Label("Older output was trimmed after the 2 MiB per-project log limit.", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let cleanupError = state.cleanupError {
                Label(cleanupError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
