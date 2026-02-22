import SwiftUI

struct CommandRowView: View {
    let command: BuildCommand
    let store: CommandStore
    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command.commandString, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(command.scheme)
                            .font(.system(.body, weight: .medium))
                        Text(command.action.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(command.action == .test
                                ? Color.orange.opacity(0.2)
                                : Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                        Spacer()
                        if showCopied {
                            Text("Copied!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(command.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(command.commandString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if command.isFlaggedAsBug {
                    store.clearBugFlag(command.id)
                } else {
                    store.flagAsBug(command.id)
                }
            } label: {
                Image(systemName: command.isFlaggedAsBug ? "ladybug.fill" : "ladybug")
                    .foregroundStyle(command.isFlaggedAsBug ? .red : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help(command.isFlaggedAsBug ? "Unflag as bug" : "Flag as bug")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contextMenu {
            Button("Delete", role: .destructive) {
                store.removeCommand(command.id)
            }
        }
    }
}
