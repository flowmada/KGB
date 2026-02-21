# KGB (Known Good Build) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that watches DerivedData, reconstructs xcodebuild commands from .xcresult bundles, and presents them as one-click copyable items in a SwiftUI popover.

**Architecture:** FSEvents watches DerivedData for new .xcresult bundles. CommandExtractor runs xcresulttool and parses the output into BuildCommand models. CommandStore persists them to a JSON file. A SwiftUI popover anchored to an NSStatusItem displays the commands grouped by project.

**Tech Stack:** Swift, SwiftUI, AppKit (NSStatusItem, NSPopover), FSEvents, Process (for xcresulttool)

**Design doc:** `docs/plans/2026-02-21-xbcache-design.md`

---

## Phase 1: Project Setup

### Task 1: Create macOS App Project

**Step 1: Create new Xcode project**

Create a new macOS App project:
- Product name: `KGB`
- Organization identifier: pick your domain
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" (we'll add a test target manually for more control)

**Step 2: Configure as menu bar app**

In `Info.plist` (or target settings), set:
- `LSUIElement` = `YES` (hides dock icon)

**Step 3: Add unit test target**

Add a macOS Unit Testing Bundle target named `KGBTests`. Link it to the main `KGB` target.

**Step 4: Verify build**

Run: `xcodebuild build -project KGB.xcodeproj -scheme KGB -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
git init && git add -A && git commit -m "Initial KGB project — macOS menu bar app skeleton"
```

---

## Phase 2: Data Models & Command Extraction (TDD)

### Task 2: BuildCommand Model

**Files:**
- Create: `KGB/Models/BuildCommand.swift`
- Create: `KGBTests/BuildCommandTests.swift`

**Step 1: Write the test**

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KGB.xcodeproj -scheme KGB -destination 'platform=macOS'`
Expected: FAIL — `BuildCommand` not defined

**Step 3: Implement BuildCommand**

```swift
import Foundation

struct BuildCommand: Codable, Identifiable {
    let id: UUID
    let projectPath: String
    let projectType: ProjectType
    let scheme: String
    let action: BuildAction
    let platform: String
    let deviceName: String
    let osVersion: String
    let timestamp: Date
    var isFlaggedAsBug: Bool

    init(
        id: UUID = UUID(),
        projectPath: String,
        projectType: ProjectType,
        scheme: String,
        action: BuildAction,
        platform: String,
        deviceName: String,
        osVersion: String,
        timestamp: Date,
        isFlaggedAsBug: Bool = false
    ) {
        self.id = id
        self.projectPath = projectPath
        self.projectType = projectType
        self.scheme = scheme
        self.action = action
        self.platform = platform
        self.deviceName = deviceName
        self.osVersion = osVersion
        self.timestamp = timestamp
        self.isFlaggedAsBug = isFlaggedAsBug
    }

    var commandString: String {
        let projectFlag = projectType == .workspace ? "-workspace" : "-project"
        return """
            xcodebuild \(action.rawValue) \
            \(projectFlag) \(projectPath) \
            -scheme \(scheme) \
            -destination 'platform=\(platform),name=\(deviceName),OS=\(osVersion)'
            """
    }

    /// Project name derived from the project/workspace filename
    var projectName: String {
        URL(fileURLWithPath: projectPath)
            .deletingPathExtension()
            .lastPathComponent
    }

    enum ProjectType: String, Codable {
        case project
        case workspace
    }

    enum BuildAction: String, Codable {
        case build
        case test
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project KGB.xcodeproj -scheme KGB -destination 'platform=macOS'`
Expected: All 3 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add BuildCommand model with command string generation"
```

---

### Task 3: XCResult Filename Parser

**Files:**
- Create: `KGB/Services/XCResultParser.swift`
- Create: `KGBTests/XCResultParserTests.swift`

**Step 1: Write the tests**

```swift
import Testing
@testable import KGB

struct XCResultParserTests {
    // MARK: - Filename parsing

    @Test func parseFilename_testAction() {
        let result = XCResultParser.parseFilename(
            "Test-PizzaCoach-2026.02.21_14-24-35--0800.xcresult"
        )
        #expect(result?.scheme == "PizzaCoach")
        #expect(result?.action == .test)
    }

    @Test func parseFilename_buildAction() {
        let result = XCResultParser.parseFilename(
            "Build-MyApp-2026.02.21_11-03-09--0800.xcresult"
        )
        #expect(result?.scheme == "MyApp")
        #expect(result?.action == .build)
    }

    @Test func parseFilename_runAction_mapsToBuild() {
        let result = XCResultParser.parseFilename(
            "Run-PizzaCoach-2026.02.21_11-03-09--0800.xcresult"
        )
        #expect(result?.scheme == "PizzaCoach")
        #expect(result?.action == .build)
    }

    @Test func parseFilename_schemeWithHyphens() {
        let result = XCResultParser.parseFilename(
            "Test-My-Cool-App-2026.02.21_14-24-35--0800.xcresult"
        )
        // Hyphenated scheme names are ambiguous — the parser splits on
        // the first hyphen after the action prefix. This test documents
        // the known limitation. We'll improve with actionTitle fallback.
        #expect(result != nil)
    }

    @Test func parseFilename_malformed() {
        let result = XCResultParser.parseFilename("garbage.xcresult")
        #expect(result == nil)
    }

    // MARK: - JSON parsing

    @Test func parseJSON_iOSSimulator() throws {
        let json = """
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
        let result = try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        #expect(result.deviceName == "iPhone 17 Pro")
        #expect(result.osVersion == "26.2")
        #expect(result.platform == "iOS Simulator")
    }

    @Test func parseJSON_watchOSSimulator() throws {
        let json = """
        {
          "destination": {
            "architecture": "arm64",
            "deviceId": "2317531A-BDE6-45CC-9B39-23C78BE00AC9",
            "deviceName": "Apple Watch Series 11 (46mm)",
            "modelName": "Apple Watch Series 11 (46mm)",
            "osBuildNumber": "23S303",
            "osVersion": "26.0",
            "platform": "watchOS Simulator"
          },
          "status": "succeeded"
        }
        """
        let result = try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        #expect(result.deviceName == "Apple Watch Series 11 (46mm)")
        #expect(result.platform == "watchOS Simulator")
    }

    @Test func parseJSON_missingDestination_throws() {
        let json = """
        { "status": "succeeded" }
        """
        #expect(throws: XCResultParser.ParseError.self) {
            try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `XCResultParser` not defined

**Step 3: Implement XCResultParser**

```swift
import Foundation

enum XCResultParser {

    struct FilenameResult {
        let scheme: String
        let action: BuildCommand.BuildAction
    }

    struct BuildResultsJSON: Decodable {
        let destination: Destination
        let actionTitle: String?

        struct Destination: Decodable {
            let deviceName: String
            let osVersion: String
            let platform: String
        }
    }

    struct DestinationInfo {
        let deviceName: String
        let osVersion: String
        let platform: String
    }

    enum ParseError: Error {
        case malformedFilename
        case missingDestination
        case invalidJSON(Error)
    }

    /// Parse scheme name and action from an .xcresult filename.
    /// Format: "Action-SchemeName-YYYY.MM.DD_HH-MM-SS-+ZZZZ.xcresult"
    static func parseFilename(_ filename: String) -> FilenameResult? {
        let name = filename.replacingOccurrences(of: ".xcresult", with: "")

        // Find the action prefix
        let actionMap: [(prefix: String, action: BuildCommand.BuildAction)] = [
            ("Test-", .test),
            ("Build-", .build),
            ("Run-", .build),  // Run maps to build
        ]

        for (prefix, action) in actionMap {
            guard name.hasPrefix(prefix) else { continue }
            let remainder = String(name.dropFirst(prefix.count))

            // Find the timestamp portion: starts with YYYY.MM.DD
            // Look for the pattern "-YYYY." where YYYY is 4 digits
            let pattern = #"-\d{4}\.\d{2}\.\d{2}_"#
            guard let range = remainder.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let scheme = String(remainder[remainder.startIndex..<range.lowerBound])
            guard !scheme.isEmpty else { continue }

            return FilenameResult(scheme: scheme, action: action)
        }

        return nil
    }

    /// Parse destination info from xcresulttool get build-results JSON output.
    static func parseBuildResultsJSON(_ data: Data) throws -> DestinationInfo {
        let result: BuildResultsJSON
        do {
            result = try JSONDecoder().decode(BuildResultsJSON.self, from: data)
        } catch {
            throw ParseError.invalidJSON(error)
        }

        return DestinationInfo(
            deviceName: result.destination.deviceName,
            osVersion: result.destination.osVersion,
            platform: result.destination.platform
        )
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 7 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add XCResultParser — filename and JSON parsing"
```

---

### Task 4: CommandExtractor — Orchestrates xcresulttool

**Files:**
- Create: `KGB/Services/CommandExtractor.swift`
- Create: `KGBTests/CommandExtractorTests.swift`

This component shells out to `xcrun xcresulttool` and combines all parsed data into a `BuildCommand`. It also detects workspace vs project.

**Step 1: Write the tests**

Use a protocol to mock the shell command so tests don't need real xcresulttool:

```swift
import Testing
@testable import KGB

struct CommandExtractorTests {
    @Test func extract_buildsCommandFromFixtures() async throws {
        let mockShell = MockShellExecutor(output: fixtureJSON_iOS)
        let extractor = CommandExtractor(shell: mockShell)

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
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Build/Build-MyApp-2026.02.21.xcresult",
            projectSourceDir: "/Users/dev/MyApp"
        )

        #expect(cmd.projectType == .workspace)
    }

    @Test func extract_defaultsToProject() async throws {
        let mockShell = MockShellExecutor(output: fixtureJSON_iOS)
        let mockFS = MockFileChecker(workspaceExists: false)
        let extractor = CommandExtractor(shell: mockShell, fileChecker: mockFS)

        let cmd = try await extractor.extract(
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Build/Build-MyApp-2026.02.21.xcresult",
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
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — protocols and `CommandExtractor` not defined

**Step 3: Implement protocols and CommandExtractor**

```swift
import Foundation

// MARK: - Protocols for testability

protocol ShellExecuting: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> Data
}

protocol FileChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
}

// MARK: - Production implementations

struct ProcessShellExecutor: ShellExecuting {
    func run(_ command: String, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [command] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

struct RealFileChecker: FileChecking {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
}

// MARK: - CommandExtractor

struct CommandExtractor {
    let shell: ShellExecuting
    let fileChecker: FileChecking

    init(shell: ShellExecuting = ProcessShellExecutor(),
         fileChecker: FileChecking = RealFileChecker()) {
        self.shell = shell
        self.fileChecker = fileChecker
    }

    func extract(xcresultPath: String, projectSourceDir: String) async throws -> BuildCommand {
        let filename = URL(fileURLWithPath: xcresultPath).lastPathComponent

        // 1. Parse scheme + action from filename
        guard let filenameResult = XCResultParser.parseFilename(filename) else {
            throw ExtractionError.malformedFilename(filename)
        }

        // 2. Run xcresulttool
        let jsonData = try await shell.run("xcresulttool", arguments: [
            "get", "build-results",
            "--path", xcresultPath,
            "--format", "json"
        ])

        // 3. Parse destination from JSON
        let destination = try XCResultParser.parseBuildResultsJSON(jsonData)

        // 4. Detect workspace vs project
        let (projectPath, projectType) = try detectProjectType(in: projectSourceDir)

        return BuildCommand(
            projectPath: projectPath,
            projectType: projectType,
            scheme: filenameResult.scheme,
            action: filenameResult.action,
            platform: destination.platform,
            deviceName: destination.deviceName,
            osVersion: destination.osVersion,
            timestamp: Date()
        )
    }

    private func detectProjectType(in dir: String) throws -> (String, BuildCommand.ProjectType) {
        let contents = try fileChecker.contentsOfDirectory(atPath: dir)
        if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return ("\(dir)/\(ws)", .workspace)
        }
        if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return ("\(dir)/\(proj)", .project)
        }
        throw ExtractionError.noProjectFound(dir)
    }

    enum ExtractionError: Error {
        case malformedFilename(String)
        case noProjectFound(String)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 3 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add CommandExtractor with shell/file protocols for testability"
```

---

## Phase 3: Persistence

### Task 5: CommandStore

**Files:**
- Create: `KGB/Services/CommandStore.swift`
- Create: `KGBTests/CommandStoreTests.swift`

**Step 1: Write the tests**

```swift
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
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `CommandStore` not defined

**Step 3: Implement CommandStore**

```swift
import Foundation
import Observation

@Observable
final class CommandStore {
    private(set) var allCommands: [BuildCommand] = []
    private let persistenceURL: URL?

    struct ProjectGroup: Identifiable {
        let projectName: String
        let commands: [BuildCommand]
        var id: String { projectName }
    }

    init(persistenceURL: URL?) {
        self.persistenceURL = persistenceURL
        if persistenceURL != nil { load() }
    }

    var groupedByProject: [ProjectGroup] {
        let grouped = Dictionary(grouping: allCommands, by: \.projectName)
        return grouped.map { ProjectGroup(projectName: $0.key, commands: $0.value) }
            .sorted { group1, group2 in
                let latest1 = group1.commands.map(\.timestamp).max() ?? .distantPast
                let latest2 = group2.commands.map(\.timestamp).max() ?? .distantPast
                return latest1 > latest2
            }
    }

    func add(_ command: BuildCommand) {
        // Replace existing command for same scheme+action+project, or append
        if let idx = allCommands.firstIndex(where: {
            $0.scheme == command.scheme &&
            $0.action == command.action &&
            $0.projectName == command.projectName
        }) {
            allCommands[idx] = command
        } else {
            allCommands.append(command)
        }
        save()
    }

    func save() {
        guard let url = persistenceURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try? JSONEncoder().encode(allCommands)
        try? data?.write(to: url, options: .atomic)
    }

    func load() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let commands = try? JSONDecoder().decode([BuildCommand].self, from: data) else {
            return
        }
        allCommands = commands
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 4 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add CommandStore with grouping, sorting, and JSON persistence"
```

---

## Phase 4: File Watching

### Task 6: DerivedDataWatcher

**Files:**
- Create: `KGB/Services/DerivedDataWatcher.swift`

This wraps FSEvents. It's thin by design — hard to unit test, so we keep logic minimal and rely on integration testing.

**Step 1: Implement DerivedDataWatcher**

```swift
import Foundation

final class DerivedDataWatcher {
    private var stream: FSEventStreamRef?
    private let callback: (String) -> Void
    private let watchPath: String

    /// - Parameters:
    ///   - path: DerivedData directory to watch
    ///   - callback: Called with the full path to each new .xcresult bundle
    init(path: String, callback: @escaping (String) -> Void) {
        self.watchPath = path
        self.callback = callback
    }

    func start() {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(self).toOpaque()

        let paths = [watchPath] as CFArray
        stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info else { return }
                let watcher = Unmanaged<DerivedDataWatcher>.fromOpaque(info)
                    .takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths)
                    .takeUnretainedValue() as! [String]
                for i in 0..<numEvents {
                    let path = paths[i]
                    if path.hasSuffix(".xcresult") || path.hasSuffix(".xcresult/") {
                        watcher.callback(path.hasSuffix("/")
                            ? String(path.dropLast())
                            : path)
                    }
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 second latency
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
```

**Step 2: Manual integration test**

Build and run the app. Trigger a build in Xcode on any project. Verify (via a print statement or breakpoint) that the callback fires with the .xcresult path.

**Step 3: Commit**

```
git add -A && git commit -m "Add DerivedDataWatcher — FSEvents listener for .xcresult bundles"
```

---

## Phase 5: Menu Bar UI

### Task 7: Menu Bar + Popover Skeleton

**Files:**
- Create: `KGB/App/AppDelegate.swift`
- Modify: `KGB/KGBApp.swift`

**Step 1: Implement AppDelegate with NSStatusItem + NSPopover**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    let commandStore = CommandStore(
        persistenceURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KGB/commands.json")
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "KGB")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: commandStore)
        )
        popover.behavior = .transient
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

Update `KGBApp.swift`:

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

**Step 2: Create placeholder PopoverView**

Create `KGB/Views/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    let store: CommandStore

    var body: some View {
        VStack {
            Text("KGB — Known Good Build")
                .font(.headline)
            Text("No commands yet")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 300)
    }
}
```

**Step 3: Build and verify**

Build, run, verify: menu bar icon appears, clicking shows popover with placeholder text, clicking outside dismisses.

**Step 4: Commit**

```
git add -A && git commit -m "Add menu bar icon and popover skeleton"
```

---

### Task 8: PopoverView — Command List

**Files:**
- Modify: `KGB/Views/PopoverView.swift`
- Create: `KGB/Views/CommandRowView.swift`

**Step 1: Implement the views**

`CommandRowView.swift`:

```swift
import SwiftUI

struct CommandRowView: View {
    let command: BuildCommand
    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command.commandString, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(command.scheme)
                            .font(.system(.body, weight: .medium))
                        Text(command.action.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(command.action == .test
                                ? Color.orange.opacity(0.2)
                                : Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                        Spacer()
                        if showCopied {
                            Text("Copied!")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text(command.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(command.commandString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

Update `PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    let store: CommandStore

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

            if store.groupedByProject.isEmpty {
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
                                    CommandRowView(command: cmd)
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
        }
        .frame(width: 480, height: 360)
    }
}
```

**Step 2: Add preview with sample data for development**

Add to `PopoverView.swift`:

```swift
#Preview {
    PopoverView(store: {
        let store = CommandStore(persistenceURL: nil)
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .build,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        ))
        store.add(BuildCommand(
            projectPath: "/Users/dev/MyApp/MyApp.xcodeproj",
            projectType: .project, scheme: "MyApp", action: .test,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date().addingTimeInterval(-600)
        ))
        return store
    }())
}
```

**Step 3: Build and verify in preview + running app**

**Step 4: Commit**

```
git add -A && git commit -m "Add PopoverView with grouped command list and copy-to-clipboard"
```

---

## Phase 6: Wire It All Together

### Task 9: Connect Watcher → Extractor → Store

**Files:**
- Modify: `KGB/App/AppDelegate.swift`

**Step 1: Wire the pipeline in AppDelegate**

```swift
// Add to AppDelegate:
private var watcher: DerivedDataWatcher?
private let extractor = CommandExtractor()

func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing statusItem/popover setup ...

    let derivedDataPath = UserDefaults.standard.string(forKey: "derivedDataPath")
        ?? NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"

    watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] xcresultPath in
        guard let self else { return }
        Task {
            do {
                // Derive project source dir from DerivedData structure
                let projectSourceDir = self.resolveProjectSourceDir(
                    derivedDataPath: derivedDataPath,
                    xcresultPath: xcresultPath
                )

                let command = try await self.extractor.extract(
                    xcresultPath: xcresultPath,
                    projectSourceDir: projectSourceDir
                )

                await MainActor.run {
                    self.commandStore.add(command)
                }
            } catch {
                // Silently skip — better to show nothing than a wrong command
                print("KGB: Skipped \(xcresultPath): \(error)")
            }
        }
    }
    watcher?.start()
}

/// Resolve the project source directory from DerivedData paths.
/// DerivedData structure: DerivedData/ProjectName-hash/Logs/Build/xxx.xcresult
/// The project source dir is stored in build-request.json's containerPath.
private func resolveProjectSourceDir(derivedDataPath: String, xcresultPath: String) -> String {
    // Extract the project DerivedData folder (e.g., "MyApp-blpcojcwterdrbhiylukgpcjuvcc")
    let components = xcresultPath
        .replacingOccurrences(of: derivedDataPath + "/", with: "")
        .components(separatedBy: "/")
    guard let projectFolder = components.first else { return "" }

    // Look for build-request.json to get containerPath
    let buildDataPath = "\(derivedDataPath)/\(projectFolder)/Build/Intermediates.noindex/XCBuildData"
    if let enumerator = FileManager.default.enumerator(atPath: buildDataPath),
       let files = enumerator.allObjects as? [String],
       let requestFile = files.first(where: { $0.hasSuffix("build-request.json") }),
       let data = FileManager.default.contents(atPath: "\(buildDataPath)/\(requestFile)"),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let containerPath = json["containerPath"] as? String {
        // containerPath is e.g. "/Users/dev/MyApp/MyApp.xcodeproj"
        return URL(fileURLWithPath: containerPath).deletingLastPathComponent().path
    }

    return ""
}
```

**Step 2: Build, run, trigger a build in Xcode, verify command appears in popover**

**Step 3: Commit**

```
git add -A && git commit -m "Wire watcher → extractor → store pipeline"
```

---

## Phase 7: Bug Reporting

### Task 10: Flag & Match Logic

**Files:**
- Modify: `KGB/Services/CommandStore.swift`
- Create: `KGBTests/BugReportMatchingTests.swift`

**Step 1: Write the tests**

```swift
import Testing
@testable import KGB

struct BugReportMatchingTests {
    @Test func flagCommand_setsFlag() {
        let store = CommandStore(persistenceURL: nil)
        var cmd = makeCommand(scheme: "MyApp")
        store.add(cmd)

        store.flagAsBug(cmd.id)

        #expect(store.allCommands.first?.isFlaggedAsBug == true)
    }

    @Test func addCommand_matchesFlaggedBug() {
        let store = CommandStore(persistenceURL: nil)
        let broken = makeCommand(scheme: "MyApp", action: .build)
        store.add(broken)
        store.flagAsBug(broken.id)

        // Simulate a new successful build for the same scheme
        let working = makeCommand(scheme: "MyApp", action: .build)
        store.add(working)

        #expect(store.pendingBugReport != nil)
        #expect(store.pendingBugReport?.brokenCommand.id == broken.id)
        #expect(store.pendingBugReport?.workingCommand.id == working.id)
    }

    @Test func noMatch_differentScheme() {
        let store = CommandStore(persistenceURL: nil)
        let broken = makeCommand(scheme: "AppA")
        store.add(broken)
        store.flagAsBug(broken.id)

        let working = makeCommand(scheme: "AppB")
        store.add(working)

        #expect(store.pendingBugReport == nil)
    }

    private func makeCommand(
        scheme: String,
        action: BuildCommand.BuildAction = .build
    ) -> BuildCommand {
        BuildCommand(
            projectPath: "/path/MyApp.xcodeproj",
            projectType: .project, scheme: scheme, action: action,
            platform: "iOS Simulator", deviceName: "iPhone 17 Pro",
            osVersion: "26.2", timestamp: Date()
        )
    }
}
```

**Step 2: Run tests to verify they fail**

**Step 3: Add bug reporting to CommandStore**

Add to `CommandStore`:

```swift
struct BugReport {
    let brokenCommand: BuildCommand
    let workingCommand: BuildCommand
}

/// Currently pending bug report (broken flagged + matching fix detected)
var pendingBugReport: BugReport? {
    guard let flagged = allCommands.first(where: { $0.isFlaggedAsBug }),
          let match = allCommands.first(where: {
              !$0.isFlaggedAsBug &&
              $0.scheme == flagged.scheme &&
              $0.projectName == flagged.projectName &&
              $0.action == flagged.action &&
              $0.timestamp > flagged.timestamp
          }) else {
        return nil
    }
    return BugReport(brokenCommand: flagged, workingCommand: match)
}

func flagAsBug(_ id: UUID) {
    if let idx = allCommands.firstIndex(where: { $0.id == id }) {
        allCommands[idx].isFlaggedAsBug = true
        save()
    }
}

func clearBugFlag(_ id: UUID) {
    if let idx = allCommands.firstIndex(where: { $0.id == id }) {
        allCommands[idx].isFlaggedAsBug = false
        save()
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 3 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add bug flag/match logic to CommandStore"
```

---

### Task 11: Bug Report Email Composition

**Files:**
- Create: `KGB/Services/BugReportComposer.swift`
- Create: `KGBTests/BugReportComposerTests.swift`

**Step 1: Write the tests**

```swift
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
```

**Step 2: Run tests to verify they fail**

**Step 3: Implement BugReportComposer**

```swift
import AppKit
import Foundation

enum BugReportComposer {
    static let emailAddress = "kgb-bugs@yourdomain.com" // TODO: set real address

    static func redactHomePath(_ string: String) -> String {
        let home = NSHomeDirectory()
        let username = home.components(separatedBy: "/").last ?? ""
        return string.replacingOccurrences(
            of: "/Users/\(username)",
            with: "/Users/<redacted>"
        )
    }

    static func composeBody(_ report: CommandStore.BugReport) -> String {
        let broken = report.brokenCommand
        let working = report.workingCommand

        return redactHomePath("""
        KGB Bug Report
        ==============

        --- BROKEN COMMAND ---
        \(broken.commandString)

        Scheme: \(broken.scheme)
        Action: \(broken.action.rawValue)
        Platform: \(broken.platform)
        Device: \(broken.deviceName)
        OS: \(broken.osVersion)
        Project: \(broken.projectPath)

        --- WORKING COMMAND ---
        \(working.commandString)

        Scheme: \(working.scheme)
        Action: \(working.action.rawValue)
        Platform: \(working.platform)
        Device: \(working.deviceName)
        OS: \(working.osVersion)
        Project: \(working.projectPath)
        """)
    }

    static func openMailto(_ report: CommandStore.BugReport) {
        let body = composeBody(report)
        let subject = "KGB Bug: \(report.brokenCommand.scheme) \(report.brokenCommand.action.rawValue)"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All 2 tests PASS

**Step 5: Commit**

```
git add -A && git commit -m "Add BugReportComposer with path redaction and mailto"
```

---

### Task 12: Bug Report UI in Popover

**Files:**
- Modify: `KGB/Views/CommandRowView.swift`
- Modify: `KGB/Views/PopoverView.swift`

**Step 1: Add bug icon to CommandRowView**

Add a bug icon button to the row's HStack (trailing side). On click, call `store.flagAsBug(command.id)`.

**Step 2: Add bug report banner to PopoverView**

When `store.pendingBugReport` is non-nil, show a prominent banner at the top of the popover:
- "We found a fix! Send a bug report to help improve KGB."
- "Send Report" button → calls `BugReportComposer.openMailto(report)` then `store.clearBugFlag(report.brokenCommand.id)`

**Step 3: Build, run, verify flow manually:**
1. Copy a command
2. Click the bug icon on it → flag appears
3. Trigger a new build in Xcode for the same scheme
4. Banner appears in popover
5. Click "Send Report" → email client opens with pre-filled content

**Step 4: Commit**

```
git add -A && git commit -m "Add bug report UI — flag icon and send banner"
```

---

## Phase 8: Settings & Polish

### Task 13: Settings — Custom DerivedData Path

**Files:**
- Create: `KGB/Views/SettingsView.swift`
- Modify: `KGB/Views/PopoverView.swift` (add gear icon)
- Modify: `KGB/KGBApp.swift` (add Settings scene)

**Step 1: Implement SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("derivedDataPath") var derivedDataPath: String = ""

    var body: some View {
        Form {
            Section("DerivedData Location") {
                TextField(
                    "Default: ~/Library/Developer/Xcode/DerivedData",
                    text: $derivedDataPath
                )
                Text("Leave blank to use the default location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 150)
    }
}
```

Update `KGBApp.swift` to include Settings scene:
```swift
var body: some Scene {
    Settings { SettingsView() }
}
```

Add gear icon to PopoverView header that opens Settings:
```swift
Button {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
} label: {
    Image(systemName: "gear")
}
.buttonStyle(.plain)
```

**Step 2: Build and verify settings window opens**

**Step 3: Commit**

```
git add -A && git commit -m "Add settings view for custom DerivedData path"
```

---

### Task 14: App Icon & Final Polish

**Step 1:** Design a simple app icon (or use SF Symbols placeholder for now).

**Step 2:** Verify the full flow end-to-end:
1. Launch KGB
2. Build a project in Xcode
3. Command appears in popover
4. Click to copy
5. Paste into terminal → verify it works
6. Flag as bug → trigger new build → banner appears → send report

**Step 3: Commit**

```
git add -A && git commit -m "Final polish and end-to-end verification"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 — Setup | 1 | Xcode project, menu bar skeleton |
| 2 — Extraction | 2-4 | BuildCommand model, filename/JSON parsers, CommandExtractor |
| 3 — Persistence | 5 | CommandStore with grouping + JSON persistence |
| 4 — Watching | 6 | DerivedDataWatcher (FSEvents) |
| 5 — UI | 7-8 | Popover with command list, copy-to-clipboard |
| 6 — Wiring | 9 | Full pipeline: watch → extract → store → display |
| 7 — Bug Reports | 10-12 | Flag, match, compose, send |
| 8 — Polish | 13-14 | Settings, icon, end-to-end verification |
