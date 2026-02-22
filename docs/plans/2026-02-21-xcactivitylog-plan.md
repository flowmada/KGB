# xcactivitylog Early Detection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Detect builds immediately via xcactivitylog files in Logs/Build/, show pending entries, and upgrade to full commands when xcresults arrive.

**Architecture:** The DerivedDataWatcher fires for both `.xcactivitylog` and `.xcresult` files. AppDelegate routes each to the appropriate handler. xcactivitylog → BuildLogParser → pending entry in buildOnly state. xcresult → match to existing pending by scheme → extract full command. If no prior pending exists for that scheme, create one in waiting state and extract.

**Tech Stack:** Swift, SwiftUI, zlib (via Process gunzip), Observation framework

**Design doc:** `docs/plans/2026-02-21-xcactivitylog-early-detection-design.md`

**Build/test commands:**
```bash
xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
```

---

### Task 1: Create BuildLogParser

Parse decompressed xcactivitylog text to extract scheme + destination. Uses `gunzip -c` via Process for decompression (consistent with existing Process usage for xcresulttool).

**Files:**
- Create: `KGB/KGB/Services/BuildLogParser.swift`
- Create: `KGB/KGBTests/BuildLogParserTests.swift`

**Step 1: Write the failing test**

Create `KGB/KGBTests/BuildLogParserTests.swift`:

```swift
import Foundation
import Testing
@testable import KGB

struct BuildLogParserTests {
    @Test func parse_extractsWorkspaceSchemeDestination() {
        let text = """
        SLF012#some-header-stuff
        Workspace PizzaCoach | Scheme PizzaCoachWatch | Destination Apple Watch Series 11 (46mm)
        Project PizzaCoach | Configuration Debug | Destination Apple Watch Series 11 (46mm) | SDK Simulator
        some other build log content here
        """

        let result = BuildLogParser.parse(text)

        #expect(result != nil)
        #expect(result?.scheme == "PizzaCoachWatch")
        #expect(result?.destination == "Apple Watch Series 11 (46mm)")
        #expect(result?.projectName == "PizzaCoach")
        #expect(result?.isWorkspace == true)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/BuildLogParserTests/parse_extractsWorkspaceSchemeDestination 2>&1 | xcsift`
Expected: FAIL — BuildLogParser doesn't exist

**Step 3: Write minimal implementation**

Create `KGB/KGB/Services/BuildLogParser.swift`:

```swift
import Foundation

enum BuildLogParser {

    struct BuildLogInfo {
        let scheme: String
        let destination: String
        let projectName: String
        let isWorkspace: Bool
    }

    /// Parse scheme + destination from decompressed xcactivitylog text.
    /// Looks for line matching: "Workspace X | Scheme Y | Destination Z"
    /// or: "Project X | Scheme Y | Destination Z"
    static func parse(_ text: String) -> BuildLogInfo? {
        // Match "Workspace X | Scheme Y | Destination Z" or "Project X | Scheme Y | Destination Z"
        let pattern = #"(Workspace|Project) ([^|]+)\| Scheme ([^|]+)\| Destination ([^\n-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 5 else {
            return nil
        }

        func group(_ i: Int) -> String {
            let range = Range(match.range(at: i), in: text)!
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }

        let type = group(1)
        let projectName = group(2)
        let scheme = group(3)
        let destination = group(4)

        return BuildLogInfo(
            scheme: scheme,
            destination: destination,
            projectName: projectName,
            isWorkspace: type == "Workspace"
        )
    }

    /// Read and decompress an xcactivitylog file, then parse it.
    static func parseFile(at path: String) -> BuildLogInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/BuildLogParserTests/parse_extractsWorkspaceSchemeDestination 2>&1 | xcsift`
Expected: PASS

**Step 5: Add more tests**

Add to `BuildLogParserTests.swift`:

```swift
@Test func parse_extractsProjectSchemeDestination() {
    let text = """
    SLF012#header
    Project SkillSnitch | Configuration Debug | Destination My Mac | SDK macOS 26.2
    Workspace SkillSnitch | Scheme SkillSnitch | Destination My Mac
    more content
    """

    let result = BuildLogParser.parse(text)

    #expect(result != nil)
    #expect(result?.scheme == "SkillSnitch")
    #expect(result?.destination == "My Mac")
    #expect(result?.projectName == "SkillSnitch")
    #expect(result?.isWorkspace == true)
}

@Test func parse_returnsNilForUnrecognizedFormat() {
    let text = "this is not a valid xcactivitylog"

    let result = BuildLogParser.parse(text)

    #expect(result == nil)
}

@Test func parse_handlesProjectOnly() {
    // Some builds might have Project line but no Workspace line
    let text = """
    SLF012#header
    Project MyLib | Scheme MyLib | Destination My Mac
    more content
    """

    let result = BuildLogParser.parse(text)

    #expect(result != nil)
    #expect(result?.scheme == "MyLib")
    #expect(result?.isWorkspace == false)
}
```

**Step 6: Run all BuildLogParser tests**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/BuildLogParserTests 2>&1 | xcsift`
Expected: 4 tests PASS

**Step 7: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass (33 existing + 4 new = 37)

**Step 8: Commit**

```
feat: add BuildLogParser for xcactivitylog extraction
```

---

### Task 2: Update PendingExtraction model

Replace `isFailed: Bool` with a `State` enum (`.waiting`, `.buildOnly`, `.failed`). Add optional `destination` field (from xcactivitylog). Make `xcresultPath` optional (nil for xcactivitylog-only entries).

**Files:**
- Modify: `KGB/KGB/Services/CommandStore.swift`
- Modify: `KGB/KGBTests/PendingExtractionTests.swift`

**Step 1: Update PendingExtraction struct**

In `CommandStore.swift`, replace the existing `PendingExtraction` struct:

```swift
struct PendingExtraction: Identifiable {
    let id: UUID
    let scheme: String
    let destination: String?
    var xcresultPath: String?
    var state: State

    enum State {
        case waiting    // spinner, actively trying to extract xcresult
        case buildOnly  // have build info, no full command yet
        case failed     // couldn't parse xcactivitylog
    }

    init(id: UUID = UUID(), scheme: String, destination: String? = nil,
         xcresultPath: String? = nil, state: State = .buildOnly) {
        self.id = id
        self.scheme = scheme
        self.destination = destination
        self.xcresultPath = xcresultPath
        self.state = state
    }
}
```

**Step 2: Update CommandStore methods**

Replace existing pending methods:

```swift
@discardableResult
func addPending(scheme: String, destination: String? = nil,
                xcresultPath: String? = nil, state: PendingExtraction.State = .buildOnly) -> UUID {
    let pending = PendingExtraction(scheme: scheme, destination: destination,
                                     xcresultPath: xcresultPath, state: state)
    pendingExtractions.append(pending)
    return pending.id
}

func resolvePending(_ id: UUID, with command: BuildCommand) {
    pendingExtractions.removeAll { $0.id == id }
    add(command)
}

func updatePendingState(_ id: UUID, to state: PendingExtraction.State) {
    if let idx = pendingExtractions.firstIndex(where: { $0.id == id }) {
        pendingExtractions[idx].state = state
    }
}

func updatePendingXcresultPath(_ id: UUID, path: String) {
    if let idx = pendingExtractions.firstIndex(where: { $0.id == id }) {
        pendingExtractions[idx].xcresultPath = path
    }
}

func pendingForScheme(_ scheme: String) -> PendingExtraction? {
    pendingExtractions.first { $0.scheme == scheme && $0.state == .buildOnly }
}

func removePending(_ id: UUID) {
    pendingExtractions.removeAll { $0.id == id }
}
```

Remove the old `failPending`, `resetPending` methods — replaced by `updatePendingState`.

**Step 3: Update tests**

Replace `PendingExtractionTests.swift` entirely:

```swift
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
```

**Step 4: Run tests**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/PendingExtractionTests 2>&1 | xcsift`
Expected: 8 tests PASS

**Step 5: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass. Some existing code in AppDelegate references old methods (`failPending`, `resetPending`) — these will cause build errors. Fix them:

- `commandStore.failPending(pendingId)` → `commandStore.updatePendingState(pendingId, to: .buildOnly)` (exhausted retries fall back to buildOnly, not failed)
- `commandStore.resetPending(pendingId)` → `commandStore.updatePendingState(pendingId, to: .waiting)` (retry now resets to waiting)

In the Retry Now closure in AppDelegate, update:
```swift
// Old: commandStore.resetPending(pendingId)
commandStore.updatePendingState(pendingId, to: .waiting)
```

In `attemptExtraction`, update exhausted retries and non-retryable errors:
```swift
// Old: self.commandStore.failPending(pendingId)
self.commandStore.updatePendingState(pendingId, to: .buildOnly)
```

Also update the `addPending` call in `startWatching()`:
```swift
// Old: let pendingId = self.commandStore.addPending(scheme: scheme, xcresultPath: xcresultPath)
let pendingId = self.commandStore.addPending(scheme: scheme, xcresultPath: xcresultPath, state: .waiting)
```

**Step 6: Build and run full test suite again**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass

**Step 7: Commit**

```
refactor: update PendingExtraction with State enum and destination
```

---

### Task 3: Update PendingRowView for three states

Render waiting (spinner), buildOnly (info + message), and failed (error) states.

**Files:**
- Modify: `KGB/KGB/Views/PendingRowView.swift`

**Step 1: Rewrite PendingRowView**

Replace `KGB/KGB/Views/PendingRowView.swift`:

```swift
import SwiftUI

struct PendingRowView: View {
    let pending: CommandStore.PendingExtraction
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pending.scheme)
                        .font(.system(.body, weight: .medium))
                    if let destination = pending.destination {
                        Text(destination)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                statusText
            }

            Spacer()

            if pending.state == .waiting {
                Button("Retry Now") {
                    onRetry()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch pending.state {
        case .waiting:
            ProgressView()
                .controlSize(.small)
        case .buildOnly:
            Image(systemName: "hammer")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch pending.state {
        case .waiting:
            Text("Waiting for Xcode\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .buildOnly:
            Text("Run (\u{2318}R) and stop to capture full command")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text("Could not read build log")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
```

**Step 2: Update PopoverView preview**

In `PopoverView.swift`, update the preview to show a buildOnly entry:

```swift
store.addPending(scheme: "PizzaCoachWatch", destination: "Apple Watch Series 11 (46mm)")
```

(Remove the `xcresultPath` argument since it's now optional and defaults to nil.)

**Step 3: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 4: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass

**Step 5: Commit**

```
feat: update PendingRowView with three states — waiting, buildOnly, failed
```

---

### Task 4: Update DerivedDataWatcher to detect xcactivitylog files

The watcher currently only fires for `.xcresult` paths. Add `.xcactivitylog` detection. AppDelegate will check the extension to route appropriately.

**Files:**
- Modify: `KGB/KGB/Services/DerivedDataWatcher.swift`

**Step 1: Update the path detection method**

In `DerivedDataWatcher.swift`, rename `xcresultPath(from:)` to `buildArtifactPath(from:)` and add xcactivitylog support:

```swift
/// Returns the normalized path if it refers to an `.xcresult` bundle or `.xcactivitylog` file, or `nil` otherwise.
func buildArtifactPath(from eventPath: String) -> String? {
    if eventPath.hasSuffix(".xcresult") || eventPath.hasSuffix(".xcresult/") {
        return eventPath.hasSuffix("/") ? String(eventPath.dropLast()) : eventPath
    }
    if eventPath.hasSuffix(".xcactivitylog") {
        return eventPath
    }
    return nil
}
```

**Step 2: Update the callback in start()**

In the FSEventStream callback, change:

```swift
// Old:
if let result = watcher.xcresultPath(from: paths[i]) {
// New:
if let result = watcher.buildArtifactPath(from: paths[i]) {
```

**Step 3: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 4: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass

**Step 5: Commit**

```
feat: detect xcactivitylog files in DerivedDataWatcher
```

---

### Task 5: Route xcactivitylog vs xcresult in AppDelegate

Update AppDelegate to handle both file types. xcactivitylog → parse with BuildLogParser → add buildOnly pending entry. xcresult → match to existing pending by scheme (upgrade to waiting) or create new pending → extract with retry.

**Files:**
- Modify: `KGB/KGB/App/AppDelegate.swift`

**Step 1: Add xcactivitylog handler**

Add a new method:

```swift
private func handleBuildLog(_ path: String) {
    guard let info = BuildLogParser.parseFile(at: path) else {
        logger.warning("Could not parse build log: \(path)")
        return
    }
    logger.info("Build log detected: \(info.scheme) → \(info.destination)")
    commandStore.addPending(scheme: info.scheme, destination: info.destination)
}
```

**Step 2: Update the watcher callback to route by extension**

Replace the `startWatching()` method:

```swift
private func startWatching() {
    let derivedDataPath = derivedDataAccess.derivedDataPath

    watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] path in
        guard let self else { return }

        if path.hasSuffix(".xcactivitylog") {
            logger.info("Watcher detected build log: \(path)")
            Task { @MainActor in
                self.handleBuildLog(path)
            }
        } else if path.hasSuffix(".xcresult") {
            logger.info("Watcher detected xcresult: \(path)")
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let scheme = XCResultParser.parseFilename(filename)?.scheme ?? "Unknown"

            Task { @MainActor in
                // Try to match to existing buildOnly pending entry
                if let existing = self.commandStore.pendingForScheme(scheme) {
                    self.commandStore.updatePendingXcresultPath(existing.id, path: path)
                    self.commandStore.updatePendingState(existing.id, to: .waiting)
                    self.attemptExtraction(pendingId: existing.id, xcresultPath: path)
                } else {
                    // No prior build log — create new pending entry
                    let pendingId = self.commandStore.addPending(
                        scheme: scheme, xcresultPath: path, state: .waiting
                    )
                    self.attemptExtraction(pendingId: pendingId, xcresultPath: path)
                }
            }
        }
    }
    watcher?.start()
}
```

**Step 3: Update Retry Now closure**

Update the popover creation in `applicationDidFinishLaunching`. The Retry Now button should only work for entries that have an xcresultPath:

```swift
popover.contentViewController = NSHostingController(
    rootView: PopoverView(store: commandStore, derivedDataAccess: derivedDataAccess) { [weak self] pendingId in
        guard let self,
              let pending = commandStore.pendingExtractions.first(where: { $0.id == pendingId }),
              let xcresultPath = pending.xcresultPath else { return }
        // Cancel existing retry task
        retryTasks[pendingId]?.cancel()
        retryTasks.removeValue(forKey: pendingId)
        // Reset to waiting and restart extraction
        commandStore.updatePendingState(pendingId, to: .waiting)
        attemptExtraction(pendingId: pendingId, xcresultPath: xcresultPath)
    }
)
```

**Step 4: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 5: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass

**Step 6: Commit**

```
feat: route xcactivitylog and xcresult to separate handlers
```

---

### Task 6: Manual integration test

**Step 1: Build and launch KGB**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`

Launch from Xcode or DerivedData.

**Step 2: Test Cmd+B (build only)**

Open any project in Xcode, hit Cmd+B. Open KGB popover.
- Expected: Entry appears with scheme + destination + hammer icon + "Run (⌘R) and stop to capture full command"
- No spinner — this is a build-only entry

**Step 3: Test Cmd+R (run)**

Hit Cmd+R. Open KGB popover.
- Expected: A new entry appears (or the build-only entry upgrades)
- While the app is running: entry shows as buildOnly with destination
- Hit Stop in Xcode
- Expected: xcresult detected, entry transitions to spinner briefly, then resolves to full command with copy-to-clipboard

**Step 4: Test Cmd+U (test)**

Hit Cmd+U. Open KGB popover.
- Expected: Build-only entry appears immediately, then when tests finish, xcresult detected and entry upgrades to full command

**Step 5: Verify watchOS (if available)**

Open PizzaCoach, hit Cmd+R targeting watchOS simulator.
- Expected: Build-only entry appears with "Apple Watch Series 11 (46mm)" destination
- Hit Stop
- Expected: Entry resolves to full command

**Step 6: Commit if fixes needed**

```
fix: adjustments from manual integration testing
```
