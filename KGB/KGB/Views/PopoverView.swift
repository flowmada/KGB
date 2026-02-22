import SwiftUI

struct PopoverView: View {
    let store: CommandStore
    let derivedDataAccess: DerivedDataAccess
    var retryExtraction: (UUID) -> Void = { _ in }

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

            // Main content
            if !derivedDataAccess.hasAccess {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("DerivedData not found")
                        .font(.title3.bold())
                    Text("Use \"Change\" below to select your DerivedData folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer()
            } else if store.isScanning && store.groupedByProject.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning DerivedData...")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if store.groupedByProject.isEmpty && store.pendingExtractions.isEmpty {
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
                        // Pending extractions
                        ForEach(store.pendingExtractions) { pending in
                            PendingRowView(pending: pending) {
                                retryExtraction(pending.id)
                            }
                            Divider().padding(.leading, 8)
                        }

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

            // Footer — DerivedData path + Change button
            Divider()
            HStack(spacing: 8) {
                Text(derivedDataAccess.tildeAbbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(derivedDataAccess.hasAccess ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change") {
                    derivedDataAccess.changeDerivedDataPath()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 480, height: 360)
    }
}

#Preview {
    PopoverView(store: {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "PizzaCoachWatch", destination: "Apple Watch Series 11 (46mm)")
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        ))
        return store
    }(), derivedDataAccess: DerivedDataAccess())
}
