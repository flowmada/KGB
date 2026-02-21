import Foundation
import Testing
@testable import KGB

struct BugReportMatchingTests {
    @Test func flagCommand_setsFlag() {
        let store = CommandStore(persistenceURL: nil)
        let cmd = makeCommand(scheme: "MyApp")
        store.add(cmd)

        store.flagAsBug(cmd.id)

        #expect(store.allCommands.first?.isFlaggedAsBug == true)
    }

    @Test func addCommand_matchesFlaggedBug() {
        let store = CommandStore(persistenceURL: nil)
        let broken = makeCommand(scheme: "MyApp", action: .build)
        store.add(broken)
        store.flagAsBug(broken.id)

        // Simulate a new successful build for the same scheme
        let working = makeCommand(scheme: "MyApp", action: .build)
        store.add(working)

        #expect(store.pendingBugReport != nil)
        #expect(store.pendingBugReport?.brokenCommand.id == broken.id)
        #expect(store.pendingBugReport?.workingCommand.id == working.id)
    }

    @Test func noMatch_differentScheme() {
        let store = CommandStore(persistenceURL: nil)
        let broken = makeCommand(scheme: "AppA")
        store.add(broken)
        store.flagAsBug(broken.id)

        let working = makeCommand(scheme: "AppB")
        store.add(working)

        #expect(store.pendingBugReport == nil)
    }

    private func makeCommand(
        scheme: String,
        action: BuildCommand.BuildAction = .build
    ) -> BuildCommand {
        BuildCommand(
            projectPath: "/path/MyApp.xcodeproj",
            projectType: .project, scheme: scheme, action: action,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        )
    }
}
