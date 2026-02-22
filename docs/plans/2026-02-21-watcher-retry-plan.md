# Watcher Retry with Pending UI — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When the FSEvents watcher detects an xcresult bundle, show a pending spinner row immediately and retry extraction until the bundle is ready, with a manual "Retry Now" button.

**Architecture:** Add a `PendingExtraction` model to `CommandStore` that tracks in-flight retries. The AppDelegate watcher callback adds a pending entry and starts a retry loop. PopoverView renders pending entries as spinner rows with a "Retry Now" button. On success, the pending entry is replaced with a real `BuildCommand`. On exhaustion, it shows a failure state.

**Tech Stack:** Swift, SwiftUI, Observation framework

**Design doc:** `docs/plans/2026-02-21-watcher-race-condition-design.md`

**Build/test commands:**
```bash
xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
```

---

### Task 1: Add PendingExtraction model to CommandStore

Add the pending entry concept. A pending extraction has an ID, scheme name (from filename), xcresult path, and a status (pending/failed).

**Files:**
- Modify: `KGB/KGB/Services/CommandStore.swift:1-102`

**Step 1: Write the failing test**

Add new test file:
- Create: `KGB/KGBTests/PendingExtractionTests.swift`

```swift
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
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/PendingExtractionTests/addPending_createsPendingEntry 2>&1 | xcsift`
Expected: FAIL — `addPending` and `pendingExtractions` don't exist yet

**Step 3: Write minimal implementation**

Add to `CommandStore.swift`, before the `// MARK: - Bug Reporting` section:

```swift
struct PendingExtraction: Identifiable {
    let id: UUID
    let scheme: String
    let xcresultPath: String
    var isFailed: Bool

    init(id: UUID = UUID(), scheme: String, xcresultPath: String, isFailed: Bool = false) {
        self.id = id
        self.scheme = scheme
        self.xcresultPath = xcresultPath
        self.isFailed = isFailed
    }
}
```

Add the property to `CommandStore` after `isScanning`:

```swift
private(set) var pendingExtractions: [PendingExtraction] = []
```

Add methods after `add(_:)`:

```swift
func addPending(scheme: String, xcresultPath: String) -> UUID {
    let pending = PendingExtraction(scheme: scheme, xcresultPath: xcresultPath)
    pendingExtractions.append(pending)
    return pending.id
}

func resolvePending(_ id: UUID, with command: BuildCommand) {
    pendingExtractions.removeAll { $0.id == id }
    add(command)
}

func failPending(_ id: UUID) {
    if let idx = pendingExtractions.firstIndex(where: { $0.id == id }) {
        pendingExtractions[idx].isFailed = true
    }
}

func removePending(_ id: UUID) {
    pendingExtractions.removeAll { $0.id == id }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/PendingExtractionTests/addPending_createsPendingEntry 2>&1 | xcsift`
Expected: PASS

**Step 5: Add remaining PendingExtraction tests**

Add to `PendingExtractionTests.swift`:

```swift
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
```

**Step 6: Run all PendingExtraction tests**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/PendingExtractionTests 2>&1 | xcsift`
Expected: 4 tests PASS

**Step 7: Run full test suite to check for regressions**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All tests pass (28 existing + 4 new = 32)

**Step 8: Commit**

```
feat: add PendingExtraction model to CommandStore
```

---

### Task 2: Add PendingRowView to PopoverView

Show pending extractions as spinner rows with "Retry Now" button. Show failed state when retries are exhausted.

**Files:**
- Create: `KGB/KGB/Views/PendingRowView.swift`
- Modify: `KGB/KGB/Views/PopoverView.swift:77-96`

**Step 1: Create PendingRowView**

Create `KGB/KGB/Views/PendingRowView.swift`:

```swift
import SwiftUI

struct PendingRowView: View {
    let pending: CommandStore.PendingExtraction
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if pending.isFailed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.scheme)
                    .font(.system(.body, weight: .medium))
                Text(pending.isFailed ? "Could not read result" : "Waiting for Xcode\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Retry Now") {
                onRetry()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
```

**Step 2: Build to verify PendingRowView compiles**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 3: Add pending rows to PopoverView**

In `PopoverView.swift`, inside the `ScrollView` block (the `else` branch of the main content), add pending rows before the `ForEach(store.groupedByProject)` loop:

```swift
// Pending extractions
ForEach(store.pendingExtractions) { pending in
    PendingRowView(pending: pending) {
        retryExtraction(pending.id)
    }
    Divider().padding(.leading, 8)
}
```

Add the `retryExtraction` callback as a property on `PopoverView`:

```swift
var retryExtraction: (UUID) -> Void = { _ in }
```

Also show pending rows in the empty-state branch — if there are pending extractions, we should show the scroll view, not the empty state. Update the condition from:

```swift
} else if store.groupedByProject.isEmpty {
```

to:

```swift
} else if store.groupedByProject.isEmpty && store.pendingExtractions.isEmpty {
```

And add a new branch before the existing `ScrollView` else-branch for when we have only pending items (no completed commands yet):

The simplest approach: just always show the ScrollView if there are pending extractions OR grouped commands. Merge the last two conditions:

```swift
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
                // ... existing group rendering unchanged
            }
        }
    }
}
```

**Step 4: Update PopoverView callsite in AppDelegate**

In `AppDelegate.swift:28-30`, the popover creation will need the `retryExtraction` closure. For now, pass an empty closure — we'll wire it up in Task 3:

```swift
popover.contentViewController = NSHostingController(
    rootView: PopoverView(store: commandStore, derivedDataAccess: derivedDataAccess)
)
```

No change needed yet — the default value `{ _ in }` handles this.

**Step 5: Update the Preview**

Update the `#Preview` at the bottom of `PopoverView.swift` to add a pending extraction for visual testing:

```swift
#Preview {
    PopoverView(store: {
        let store = CommandStore(persistenceURL: nil)
        store.addPending(scheme: "PizzaCoachWatch", xcresultPath: "/tmp/fake.xcresult")
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        ))
        return store
    }(), derivedDataAccess: DerivedDataAccess())
}
```

**Step 6: Build to verify everything compiles**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 7: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All 32 tests pass

**Step 8: Commit**

```
feat: add PendingRowView with spinner and Retry Now button
```

---

### Task 3: Wire up retry loop in AppDelegate

Replace the current fire-and-forget watcher callback with a retry loop. On watcher detection: add a pending entry, then retry extraction every 5 seconds up to 12 times. Cancel on success. Wire the "Retry Now" button.

**Files:**
- Modify: `KGB/KGB/App/AppDelegate.swift:44-69`

**Step 1: Add retry state tracking**

Add a property to `AppDelegate` to track active retry tasks so they can be cancelled:

```swift
private var retryTasks: [UUID: Task<Void, Never>] = [:]
```

**Step 2: Extract retry logic into a method**

Add a new method `attemptExtraction` that handles the retry loop:

```swift
private func attemptExtraction(pendingId: UUID, xcresultPath: String, attempt: Int = 1) {
    let maxAttempts = 12
    let delaySeconds: UInt64 = 5
    let derivedDataPath = derivedDataAccess.derivedDataPath

    let task = Task {
        var currentAttempt = attempt
        while currentAttempt <= maxAttempts {
            if Task.isCancelled { return }

            let projectSourceDir = scanner.resolveProjectSourceDir(
                derivedDataPath: derivedDataPath,
                xcresultPath: xcresultPath
            )

            do {
                let command = try await scanner.extractor.extract(
                    xcresultPath: xcresultPath,
                    projectSourceDir: projectSourceDir
                )
                await MainActor.run {
                    commandStore.resolvePending(pendingId, with: command)
                    retryTasks.removeValue(forKey: pendingId)
                }
                if currentAttempt > 1 {
                    logger.info("Extracted \(command.scheme) after \(currentAttempt) attempts")
                }
                return
            } catch let error as XCResultParser.ParseError where isRetryable(error) {
                logger.debug("Retry \(currentAttempt)/\(maxAttempts) for \(xcresultPath), waiting \(delaySeconds)s")
                currentAttempt += 1
                if currentAttempt <= maxAttempts {
                    try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                }
            } catch {
                // Non-retryable error — fail immediately
                logger.warning("Watcher failed \(xcresultPath): \(error)")
                await MainActor.run {
                    commandStore.failPending(pendingId)
                    retryTasks.removeValue(forKey: pendingId)
                }
                return
            }
        }

        // Exhausted all retries
        logger.warning("Failed to extract \(xcresultPath) after \(maxAttempts) attempts")
        await MainActor.run {
            commandStore.failPending(pendingId)
            retryTasks.removeValue(forKey: pendingId)
        }
    }

    retryTasks[pendingId] = task
}

private func isRetryable(_ error: XCResultParser.ParseError) -> Bool {
    if case .invalidJSON = error { return true }
    return false
}
```

**Step 3: Update startWatching() to use pending + retry**

Replace the watcher callback in `startWatching()`:

```swift
private func startWatching() {
    let derivedDataPath = derivedDataAccess.derivedDataPath

    watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] xcresultPath in
        guard let self else { return }
        logger.info("Watcher detected: \(xcresultPath)")

        // Parse scheme from filename for the pending row
        let filename = URL(fileURLWithPath: xcresultPath).lastPathComponent
        let scheme = XCResultParser.parseFilename(filename)?.scheme ?? "Unknown"

        Task { @MainActor in
            let pendingId = self.commandStore.addPending(scheme: scheme, xcresultPath: xcresultPath)
            self.attemptExtraction(pendingId: pendingId, xcresultPath: xcresultPath)
        }
    }
    watcher?.start()
}
```

**Step 4: Wire Retry Now button**

Update the popover creation in `applicationDidFinishLaunching` to pass the retry closure:

```swift
popover.contentViewController = NSHostingController(
    rootView: PopoverView(store: commandStore, derivedDataAccess: derivedDataAccess) { [weak self] pendingId in
        guard let self,
              let pending = commandStore.pendingExtractions.first(where: { $0.id == pendingId }) else { return }
        // Cancel existing retry task
        retryTasks[pendingId]?.cancel()
        retryTasks.removeValue(forKey: pendingId)
        // Restart extraction immediately
        attemptExtraction(pendingId: pendingId, xcresultPath: pending.xcresultPath)
    }
)
```

**Step 5: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 6: Run full test suite**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: All 32 tests pass

**Step 7: Commit**

```
feat: wire retry loop with pending UI in watcher callback
```

---

### Task 4: Manual integration test

This is not an automated test — it verifies the full flow end-to-end.

**Step 1: Build and run the app**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`

Then launch the built app from DerivedData or Xcode.

**Step 2: Trigger a build in Xcode**

Open any project in Xcode, hit Cmd+R. Watch the KGB popover:
1. A spinner row should appear immediately with the scheme name + "Waiting for Xcode..."
2. After a few seconds, the spinner row should be replaced with the real command row
3. Check console logs for retry debug messages

**Step 3: Test Retry Now button**

If possible, trigger a build and quickly open the popover to click "Retry Now" while the spinner is showing.

**Step 4: Commit (if any fixes needed)**

```
fix: adjustments from manual integration testing
```

---

### Open Items (not in scope for this plan)

1. **Cmd+B doesn't produce xcresults** — Xcode limitation. UX decision needed for empty state messaging.
2. **Clean build messaging** — Dev-time issue, probably not user-facing.
