import Foundation
import Testing
@testable import KGB

struct BugReportComposerTests {
    @Test func redactHomePath() {
        let input = "/Users/awolf/source2025/MyApp/MyApp.xcodeproj"
        let result = BugReportComposer.redactHomePath(input)
        #expect(result == "/Users/<redacted>/source2025/MyApp/MyApp.xcodeproj")
        #expect(!result.contains("awolf"))
    }

    @Test func composeBody_containsBothCommands() {
        let broken = makeCommand(scheme: "MyApp")
        let working = makeCommand(scheme: "MyApp")
        let report = CommandStore.BugReport(brokenCommand: broken, workingCommand: working)

        let body = BugReportComposer.composeBody(report)

        #expect(body.contains("BROKEN COMMAND"))
        #expect(body.contains("WORKING COMMAND"))
        #expect(body.contains("xcodebuild"))
        #expect(!body.contains(NSHomeDirectory()))
    }

    private func makeCommand(scheme: String) -> BuildCommand {
        BuildCommand(
            projectPath: NSHomeDirectory() + "/Projects/MyApp.xcodeproj",
            projectType: .project, scheme: scheme, action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        )
    }
}
