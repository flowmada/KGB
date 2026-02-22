import SwiftUI

struct PopoverView: View {
    let store: CommandStore
    let derivedDataAccess: DerivedDataAccess

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
                SettingsLink {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Bug report banner
            if let report = store.pendingBugReport {
                VStack(spacing: 6) {
                    Text("A fix was detected! Send a bug report?")
                        .font(.callout)
                    Button("Send Report") {
                        BugReportComposer.openMailto(report)
                        store.clearBugFlag(report.brokenCommand.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))

                Divider()
            }

            if !derivedDataAccess.hasAccess {
                // Onboarding — request DerivedData access
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Welcome to KGB")
                        .font(.title3.bold())
                    Text("KGB watches your DerivedData folder for Xcode builds and gives you one-click copyable xcodebuild commands.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Grant Access to DerivedData") {
                        derivedDataAccess.requestAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else if store.groupedByProject.isEmpty {
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
                                    CommandRowView(command: cmd, store: store)
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
    }(), derivedDataAccess: DerivedDataAccess())
}
