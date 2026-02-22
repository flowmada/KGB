import SwiftUI

struct PendingRowView: View {
    let pending: CommandStore.PendingExtraction
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pending.scheme)
                        .font(.system(.body, weight: .medium))
                    if let destination = pending.destination {
                        Text(destination)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                statusText
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
        .contextMenu {
            Button("Dismiss", role: .destructive) {
                onDismiss()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch pending.state {
        case .waiting:
            ProgressView()
                .controlSize(.small)
        case .buildOnly:
            Image(systemName: "hammer")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var statusText: some View {
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
}
