# KGB (Known Good Build)

Free Mac menu bar app that watches DerivedData and gives you one-click copyable `xcodebuild` commands.

## Problem

AI coding tools (Claude Code, Cursor, Copilot, Windsurf) can't reliably build Xcode projects. The user builds successfully in Xcode, but the AI doesn't know what command Xcode used. The user watches the AI spiral on failed builds, wasting time and tokens.

Xcode doesn't use `xcodebuild` internally. It talks to `XCBBuildService` via MessagePack — it never writes a human-readable build command anywhere. There is no command to copy.

## Value Proposition

XBCache reconstructs the exact `xcodebuild` command from DerivedData and puts it one click away. The user builds in Xcode, clicks a command in the menu bar, pastes it into their AI tool. Done.

**Target audience:** Any iOS/macOS developer using AI coding tools. Not tool-specific.

**Distribution:** Free. Attention and credibility are the payoff.

## Technical Foundation

The reconstruction pipeline is built on `xcrun xcresulttool get build-results --format json`, which returns structured data from `.xcresult` bundles:

```json
{
  "destination": {
    "deviceName": "iPhone 17 Pro",
    "osVersion": "26.2",
    "platform": "iOS Simulator"
  }
}
```

All fields are human-readable. No UUID mapping, no model ID translation.

| Source | Data |
|--------|------|
| `.xcresult` filename | Scheme name, action (Build/Test) |
| `xcresulttool get build-results` | `deviceName`, `osVersion`, `platform` |
| `containerPath` in build-request.json | Project path |
| File system check | `.xcworkspace` vs `.xcodeproj` |

These combine into:
```
xcodebuild test -project Path/To/Project.xcodeproj \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
```

**Confidence: 95%.** Verified across iOS and watchOS targets on a real project.

## Approach: FSEvents

FSEvents watches `~/Library/Developer/Xcode/DerivedData/` for new `.xcresult` bundles. Sub-second detection, battery-friendly, no polling.

Alternatives considered and rejected:
- **Polling:** Strictly worse than FSEvents. Delayed, wastes CPU.
- **Xcode post-build scripts:** Requires per-project setup, breaks the zero-config promise.

## UX

**Menu bar app with popover panel.** No dock icon, no main window.

- Click menu bar icon → SwiftUI popover drops down, anchored to the icon (Fantastical-style, not NSMenu)
- Projects listed as sections, most recently built first
- Each command is a row: scheme name, action badge (Build/Test), relative timestamp
- Click a row → command copied to clipboard, brief "Copied" feedback
- Full `xcodebuild` command shown in monospaced text
- Settings via gear icon in the popover (custom DerivedData path)

**Onboarding:** First launch requests DerivedData folder access. That's it.

## Architecture

```
FSEvents (DerivedData watcher)
    → Detects new .xcresult bundle
    → xcrun xcresulttool get build-results --format json
    → Parse: scheme (from filename), destination (from JSON), project path
    → Store in CommandStore
    → Update popover UI
```

**Components:**

1. **DerivedDataWatcher** — FSEvents listener on DerivedData. Filters for new `.xcresult` bundles in `Logs/Build/`, `Logs/Test/`, `Logs/Launch/`.

2. **CommandExtractor** — Takes an `.xcresult` path, runs `xcresulttool`, parses the JSON, extracts scheme from filename, constructs the full `xcodebuild` command string.

3. **CommandStore** — Persisted list of extracted commands (JSON file in Application Support), grouped by project. Most recent first. FSEvents keeps it updated while running. On launch, loads from cache.

4. **PopoverView** — SwiftUI view showing grouped commands. Handles copy-to-clipboard.

5. **MenuBarManager** — Status item setup, popover lifecycle.

**Persistence:** Commands cached to a JSON file in Application Support. No database. First launch does a one-time scan of existing DerivedData (scan depth TBD — needs a spike). After that, FSEvents handles updates.

## Edge Cases & Error Handling

**Workspace vs project:** Check for `.xcworkspace` in the source directory. If present → `-workspace`, otherwise → `-project`. Handles CocoaPods projects.

**Custom DerivedData path:** Settings lets user point to a custom path. Stored in UserDefaults. Default: `~/Library/Developer/Xcode/DerivedData/`.

**xcresulttool failures:** If xcresulttool returns an error or missing fields, silently skip that result. Better to show nothing than a wrong command.

**Missing scheme in filename:** Filename format is `Action-SchemeName-Timestamp.xcresult`. If parsing fails, fall back to `actionTitle` (present in some results), otherwise skip.

**Permissions denied:** Show a clear message in the popover with a button to open System Settings.

## Bug Reporting

One-click, zero-effort bug reports that produce complete test cases. Bug reporting is a first-class feature.

**Flow:**
1. User copies a command → it fails to build.
2. User clicks the bug icon on that command row → app flags it internally. No email sent yet.
3. User continues working. Eventually they fix the issue and build successfully in Xcode.
4. FSEvents detects the successful build. App matches it to the flagged command (same scheme + same project).
5. The flagged row in the popover is replaced with a "Send Bug Report" banner.
6. User clicks it → pre-filled email opens with everything needed.

**Email contents (auto-filled):**
- The broken command + its xcresulttool JSON + xcresult filename
- The working command + its xcresulttool JSON + xcresult filename
- Home directory paths auto-redacted (`/Users/<redacted>/...`)

**What this gives us:** A complete before/after test fixture. The broken input shows where reconstruction failed. The working input shows what the correct output should have been. Drops straight into the test suite.

**If the user never fixes it:** The flag quietly expires. No nagging.

**Delivery:** `mailto:` link. No backend, no accounts. The user's email client is the send mechanism and the final review step.

## Testing Strategy

**CommandExtractor** — Core logic, pure input/output:
- Give it xcresulttool JSON + filename → get back a structured command
- Test with fixture JSON blobs and various filename formats
- Bug reports feed directly into the fixture corpus

**DerivedDataWatcher** — Thin FSEvents wrapper:
- Integration test: temp directory, drop a file, verify callback

**CommandStore** — Collection logic:
- Grouping by project, sorting by recency, persistence round-trip

**PopoverView** — Preview-driven development for v1.

## Deferred (Post-v1)

- **Global hotkey:** Keyboard shortcut to copy the most recent command without opening the popover
- **Scan depth heuristic:** Spike on first-launch scan strategy (last 24h, most recent per scheme, etc.)
- **v2 integration:** Write commands to a JSON file on disk that AI tools can read automatically — zero human copy-paste
