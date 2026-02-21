import Foundation
import Testing
@testable import KGB

struct CommandExtractorTests {
    @Test func extract_buildsCommandFromFixtures() async throws {
        let mockShell = MockShellExecutor(output: fixtureJSON_iOS)
        let mockFS = MockFileChecker(workspaceExists: false)
        let extractor = CommandExtractor(shell: mockShell, fileChecker: mockFS)

        let cmd = try await extractor.extract(
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Test/Test-MyApp-2026.02.21_14-24-35--0800.xcresult",
            projectSourceDir: "/Users/dev/MyApp"
        )

        #expect(cmd.scheme == "MyApp")
        #expect(cmd.action == .test)
        #expect(cmd.deviceName == "iPhone 17 Pro")
        #expect(cmd.osVersion == "26.2")
        #expect(cmd.platform == "iOS Simulator")
    }

    @Test func extract_detectsWorkspace() async throws {
        let mockShell = MockShellExecutor(output: fixtureJSON_iOS)
        let mockFS = MockFileChecker(workspaceExists: true)
        let extractor = CommandExtractor(shell: mockShell, fileChecker: mockFS)

        let cmd = try await extractor.extract(
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Build/Build-MyApp-2026.02.21_11-03-09--0800.xcresult",
            projectSourceDir: "/Users/dev/MyApp"
        )

        #expect(cmd.projectType == .workspace)
    }

    @Test func extract_defaultsToProject() async throws {
        let mockShell = MockShellExecutor(output: fixtureJSON_iOS)
        let mockFS = MockFileChecker(workspaceExists: false)
        let extractor = CommandExtractor(shell: mockShell, fileChecker: mockFS)

        let cmd = try await extractor.extract(
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Build/Build-MyApp-2026.02.21_11-03-09--0800.xcresult",
            projectSourceDir: "/Users/dev/MyApp"
        )

        #expect(cmd.projectType == .project)
    }
}

// MARK: - Test doubles

struct MockShellExecutor: ShellExecuting {
    let output: String
    func run(_ command: String, arguments: [String]) async throws -> Data {
        output.data(using: .utf8)!
    }
}

struct MockFileChecker: FileChecking {
    let workspaceExists: Bool
    func fileExists(atPath path: String) -> Bool { workspaceExists }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        workspaceExists ? ["MyApp.xcworkspace"] : ["MyApp.xcodeproj"]
    }
}

let fixtureJSON_iOS = """
{
  "destination": {
    "architecture": "arm64",
    "deviceId": "883F39DE-9EA1-41DD-A061-630197BB02B5",
    "deviceName": "iPhone 17 Pro",
    "modelName": "iPhone 17 Pro",
    "osBuildNumber": "23C54",
    "osVersion": "26.2",
    "platform": "iOS Simulator"
  },
  "status": "succeeded"
}
"""
