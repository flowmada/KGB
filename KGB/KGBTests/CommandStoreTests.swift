import Foundation
import Testing
@testable import KGB

struct CommandStoreTests {
    @Test func add_storesCommand() {
        let store = CommandStore(persistenceURL: nil)
        let cmd = makeCommand(scheme: "MyApp", action: .build)
        store.add(cmd)
        #expect(store.allCommands.count == 1)
    }

    @Test func groupedByProject_groupsCorrectly() {
        let store = CommandStore(persistenceURL: nil)
        store.add(makeCommand(scheme: "AppA", projectPath: "/path/ProjectA.xcodeproj"))
        store.add(makeCommand(scheme: "AppB", projectPath: "/path/ProjectB.xcodeproj"))
        store.add(makeCommand(scheme: "AppA", projectPath: "/path/ProjectA.xcodeproj"))

        let groups = store.groupedByProject
        #expect(groups.count == 2)
    }

    @Test func groupedByProject_mostRecentProjectFirst() {
        let store = CommandStore(persistenceURL: nil)
        let older = Date().addingTimeInterval(-3600)
        let newer = Date()

        store.add(makeCommand(scheme: "Old", projectPath: "/path/Old.xcodeproj", timestamp: older))
        store.add(makeCommand(scheme: "New", projectPath: "/path/New.xcodeproj", timestamp: newer))

        let groups = store.groupedByProject
        #expect(groups.first?.projectName == "New")
    }

    @Test func persistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kgb-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = CommandStore(persistenceURL: url)
        store1.add(makeCommand(scheme: "MyApp"))
        store1.save()

        let store2 = CommandStore(persistenceURL: url)
        store2.load()
        #expect(store2.allCommands.count == 1)
        #expect(store2.allCommands.first?.scheme == "MyApp")
    }

    @Test func removeCommand_removesCommandAndSaves() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kgb-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = CommandStore(persistenceURL: url)
        let cmd = makeCommand(scheme: "MyApp")
        store.add(cmd)
        #expect(store.allCommands.count == 1)

        store.removeCommand(cmd.id)
        #expect(store.allCommands.isEmpty)

        // Verify it persisted
        let store2 = CommandStore(persistenceURL: url)
        #expect(store2.allCommands.isEmpty)
    }

    @Test func removeCommand_withUnknownId_doesNothing() {
        let store = CommandStore(persistenceURL: nil)
        store.add(makeCommand(scheme: "MyApp"))
        #expect(store.allCommands.count == 1)

        store.removeCommand(UUID())
        #expect(store.allCommands.count == 1)
    }

    // MARK: - Helpers

    private func makeCommand(
        scheme: String,
        projectPath: String = "/path/MyApp.xcodeproj",
        action: BuildCommand.BuildAction = .build,
        timestamp: Date = Date()
    ) -> BuildCommand {
        BuildCommand(
            projectPath: projectPath,
            projectType: .project,
            scheme: scheme,
            action: action,
            platform: "iOS Simulator",
            deviceName: "iPhone 17 Pro",
            osVersion: "26.2",
            timestamp: timestamp
        )
    }
}
