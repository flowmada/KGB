import SwiftUI

struct PendingRowView: View {
    let pending: CommandStore.PendingExtraction
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if pending.state == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if pending.state == .buildOnly {
                Image(systemName: "hammer")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.scheme)
                    .font(.system(.body, weight: .medium))
                switch pending.state {
                case .waiting:
                    Text("Waiting for Xcode\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .buildOnly:
                    Text("Run (\u{2318}R) and stop to capture full command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed:
                    Text("Could not read build log")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if pending.state == .waiting {
                Button("Retry Now") {
                    onRetry()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
