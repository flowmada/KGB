import SwiftUI

struct PendingRowView: View {
    let pending: CommandStore.PendingExtraction
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if pending.isFailed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.scheme)
                    .font(.system(.body, weight: .medium))
                Text(pending.isFailed ? "Could not read result" : "Waiting for Xcode\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Retry Now") {
                onRetry()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
