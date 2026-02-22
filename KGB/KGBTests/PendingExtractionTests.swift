import Foundation
import Testing
@testable import KGB

struct PendingExtractionTests {
    @Test func addPending_createsBuildOnlyEntry() {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "MyApp", destination: "iPhone 17 Pro")
        #expect(store.pendingExtractions.count == 1)
        #expect(store.pendingExtractions.first?.scheme == "MyApp")
        #expect(store.pendingExtractions.first?.destination == "iPhone 17 Pro")
        #expect(store.pendingExtractions.first?.state == .buildOnly)
        #expect(store.pendingExtractions.first?.xcresultPath == nil)
    }

    @Test func addPending_createsWaitingEntryWithXcresultPath() {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "MyApp", xcresultPath: "/path/result.xcresult", state: .waiting)
        #expect(store.pendingExtractions.first?.state == .waiting)
        #expect(store.pendingExtractions.first?.xcresultPath == "/path/result.xcresult")
    }

    @Test func resolvePending_removesPendingAndAddsCommand() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp", destination: "iPhone 17 Pro")

        let cmd = BuildCommand(
            projectPath: "/path/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        )
        store.resolvePending(pendingId, with: cmd)

        #expect(store.pendingExtractions.isEmpty)
        #expect(store.allCommands.count == 1)
    }

    @Test func updatePendingState_changesState() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp")
        #expect(store.pendingExtractions.first?.state == .buildOnly)

        store.updatePendingState(pendingId, to: .waiting)
        #expect(store.pendingExtractions.first?.state == .waiting)

        store.updatePendingState(pendingId, to: .failed)
        #expect(store.pendingExtractions.first?.state == .failed)
    }

    @Test func updatePendingXcresultPath_setsPath() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp")
        #expect(store.pendingExtractions.first?.xcresultPath == nil)

        store.updatePendingXcresultPath(pendingId, path: "/path/result.xcresult")
        #expect(store.pendingExtractions.first?.xcresultPath == "/path/result.xcresult")
    }

    @Test func pendingForScheme_findsBuildOnlyEntry() {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "MyApp", destination: "iPhone 17 Pro")
        store.addPending(scheme: "OtherApp", destination: "My Mac")

        let found = store.pendingForScheme("MyApp")
        #expect(found?.scheme == "MyApp")
    }

    @Test func pendingForScheme_ignoresWaitingEntries() {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "MyApp", xcresultPath: "/path", state: .waiting)

        let found = store.pendingForScheme("MyApp")
        #expect(found == nil)
    }

    @Test func removePending_removesPendingEntry() {
        let store = CommandStore(persistenceURL: nil)
        let pendingId = store.addPending(scheme: "MyApp")
        store.removePending(pendingId)
        #expect(store.pendingExtractions.isEmpty)
    }
}
