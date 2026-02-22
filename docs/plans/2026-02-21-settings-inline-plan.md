# Inline Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move DerivedData path display + folder picker into the popover footer, eliminating the separate Settings window.

**Architecture:** Replace `SettingsView.swift` and all `SettingsLink` references with an inline footer in `PopoverView`. The footer shows the current path (tilde-abbreviated) and a "Change" button that opens `NSOpenPanel`. Path color reflects access state (secondary = ok, red = error).

**Tech Stack:** SwiftUI, AppKit (`NSOpenPanel` for folder picker)

**Design doc:** `docs/plans/2026-02-21-settings-inline-design.md`

**Build/test commands:**
```bash
xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
```

---

### Task 1: Add `tildeAbbreviated` helper to DerivedDataAccess

The footer needs to display `~/Library/.../DerivedData` instead of the full path. Add a computed property.

**Files:**
- Modify: `KGB/KGB/Services/DerivedDataAccess.swift:10-14`

**Step 1: Add the computed property**

Add after `derivedDataPath`:

```swift
var tildeAbbreviatedPath: String {
    let home = NSHomeDirectory()
    if derivedDataPath.hasPrefix(home) {
        return "~" + derivedDataPath.dropFirst(home.count)
    }
    return derivedDataPath
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 3: Commit**

```
feat: add tildeAbbreviatedPath to DerivedDataAccess
```

---

### Task 2: Add `changeDerivedDataPath()` to DerivedDataAccess

The footer "Change" button needs to open an `NSOpenPanel` and persist the selection. Add this to `DerivedDataAccess` so the view stays declarative.

**Files:**
- Modify: `KGB/KGB/Services/DerivedDataAccess.swift`

**Step 1: Add the method**

Add after `checkAccess()`:

```swift
func changeDerivedDataPath() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: derivedDataPath)
    panel.prompt = "Select"
    panel.message = "Choose your DerivedData folder"

    if panel.runModal() == .OK, let url = panel.url {
        UserDefaults.standard.set(url.path, forKey: "derivedDataPath")
        checkAccess()
    }
}
```

Note: `NSOpenPanel` needs `import AppKit`. Add it at the top of the file.

**Step 2: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 3: Commit**

```
feat: add changeDerivedDataPath with NSOpenPanel folder picker
```

---

### Task 3: Rewrite PopoverView with inline footer

Replace the gear icon SettingsLink and "Open Settings" button with an always-visible footer row.

**Files:**
- Modify: `KGB/KGB/Views/PopoverView.swift`

**Step 1: Replace the full PopoverView body**

The new structure:
1. Header: remove the `SettingsLink` gear icon entirely
2. Content area: remove the `SettingsLink "Open Settings"` button from the error state, simplify the error message
3. Footer: new `Divider` + `HStack` with path text + "Change" button

New `PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    let store: CommandStore
    let derivedDataAccess: DerivedDataAccess

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
            } else if store.groupedByProject.isEmpty {
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
                    .foregroundStyle(derivedDataAccess.hasAccess ? .secondary : .red)
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
```

Update the `#Preview` to remove the `derivedDataAccess` parameter change (it still works as-is since `DerivedDataAccess()` is kept).

**Step 2: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 3: Commit**

```
feat: inline DerivedData path footer in popover, remove SettingsLinks
```

---

### Task 4: Delete SettingsView and clean up KGBApp

**Files:**
- Delete: `KGB/KGB/Views/SettingsView.swift`
- Modify: `KGB/KGB/KGBApp.swift`

**Step 1: Delete SettingsView.swift**

```bash
rm KGB/KGB/Views/SettingsView.swift
```

**Step 2: Replace KGBApp.swift body**

The `Settings` scene is removed. SwiftUI `App` needs at least one scene for a menu-bar app using `NSApplicationDelegateAdaptor`. Use an empty `Settings` with no content:

```swift
import SwiftUI

@main
struct KGBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

This keeps the app as menu-bar-only with no visible settings window.

**Step 3: Build to verify**

Run: `xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 0 errors

**Step 4: Run all tests**

Run: `xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift`
Expected: 28 tests pass, 0 failures

**Step 5: Commit**

```
chore: delete SettingsView, remove Settings scene from KGBApp
```

---

### Open Item: User messaging around clean builds

**Status:** Needs discussion

The entitlements plist had `com.apple.security.app-sandbox = true` which overrode the build setting `ENABLE_APP_SANDBOX = NO`. This caused `NSHomeDirectory()` to return the sandbox container path, making DerivedData appear missing. Fixing required clearing the entitlements plist AND doing a clean build.

**Question:** When a user installs KGB or changes settings, should we message them about needing a clean build? Options:
- First-launch onboarding note
- Detection: if `NSHomeDirectory()` contains `/Library/Containers/`, warn the user
- README/docs only
- Nothing — this was a dev-time issue, not a user-facing one
