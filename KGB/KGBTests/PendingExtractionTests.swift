import Foundation
import Testing
@testable import KGB

struct PendingExtractionTests {
    @Test func addPending_createsPendingEntry() {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "MyApp", xcresultPath: "/path/to/result.xcresult")
        #expect(store.pendingExtractions.count == 1)
        #expect(store.pendingExtractions.first?.scheme == "MyApp")
        #expect(store.pendingExtractions.first?.isFailed == false)
    }

    @Test func resolvePending_removesPendingAndAddsCommand() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp", xcresultPath: "/path/result.xcresult")
        #expect(store.pendingExtractions.count == 1)

        let cmd = BuildCommand(
            projectPath: "/path/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        )
        store.resolvePending(pendingId, with: cmd)

        #expect(store.pendingExtractions.isEmpty)
        #expect(store.allCommands.count == 1)
        #expect(store.allCommands.first?.scheme == "MyApp")
    }

    @Test func failPending_marksPendingAsFailed() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp", xcresultPath: "/path/result.xcresult")
        store.failPending(pendingId)

        #expect(store.pendingExtractions.first?.isFailed == true)
    }

    @Test func removePending_removesPendingEntry() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp", xcresultPath: "/path/result.xcresult")
        store.removePending(pendingId)

        #expect(store.pendingExtractions.isEmpty)
    }
}
