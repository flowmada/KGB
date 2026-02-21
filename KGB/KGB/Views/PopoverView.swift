import SwiftUI

struct PopoverView: View {
    let store: CommandStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("KGB")
                    .font(.headline)
                Text("Known Good Build")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if store.groupedByProject.isEmpty {
                Spacer()
                Text("No builds detected yet")
                    .foregroundStyle(.secondary)
                Text("Build something in Xcode to get started")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.groupedByProject) { group in
                            Section {
                                ForEach(group.commands) { cmd in
                                    CommandRowView(command: cmd)
                                    Divider().padding(.leading, 8)
                                }
                            } header: {
                                Text(group.projectName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 360)
    }
}

#Preview {
    PopoverView(store: {
        let store = CommandStore(persistenceURL: nil)
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        ))
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .test,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date().addingTimeInterval(-600)
        ))
        return store
    }())
}
