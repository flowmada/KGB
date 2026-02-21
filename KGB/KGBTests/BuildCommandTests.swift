import Foundation
import Testing
@testable import KGB

struct BuildCommandTests {
    @Test func commandString_iOSSimulatorBuild() {
        let cmd = BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project,
            scheme: "MyApp",
            action: .build,
            platform: "iOS Simulator",
            deviceName: "iPhone 17 Pro",
            osVersion: "26.2",
            timestamp: Date()
        )

        #expect(cmd.commandString == """
            xcodebuild build \
            -project /Users/dev/MyApp/MyApp.xcodeproj \
            -scheme MyApp \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
            """)
    }

    @Test func commandString_watchOSSimulatorTest() {
        let cmd = BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project,
            scheme: "MyAppWatch",
            action: .test,
            platform: "watchOS Simulator",
            deviceName: "Apple Watch Series 11 (46mm)",
            osVersion: "26.0",
            timestamp: Date()
        )

        #expect(cmd.commandString.hasPrefix("xcodebuild test"))
        #expect(cmd.commandString.contains("-scheme MyAppWatch"))
        #expect(cmd.commandString.contains("watchOS Simulator"))
    }

    @Test func commandString_workspace() {
        let cmd = BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcworkspace",
            projectType: .workspace,
            scheme: "MyApp",
            action: .build,
            platform: "iOS Simulator",
            deviceName: "iPhone 17 Pro",
            osVersion: "26.2",
            timestamp: Date()
        )

        #expect(cmd.commandString.contains("-workspace /Users/dev/MyApp/MyApp.xcworkspace"))
        #expect(!cmd.commandString.contains("-project"))
    }
}
