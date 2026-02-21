import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var watcher: DerivedDataWatcher?
    private let extractor = CommandExtractor()
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

        startWatching()
    }

    private func startWatching() {
        let derivedDataPath = UserDefaults.standard.string(forKey: "derivedDataPath")
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"

        watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] xcresultPath in
            guard let self else { return }
            Task {
                do {
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
        let components = xcresultPath
            .replacingOccurrences(of: derivedDataPath + "/", with: "")
            .components(separatedBy: "/")
        guard let projectFolder = components.first else { return "" }

        let buildDataPath = "\(derivedDataPath)/\(projectFolder)/Build/Intermediates.noindex/XCBuildData"
        if let enumerator = FileManager.default.enumerator(atPath: buildDataPath),
           let files = enumerator.allObjects as? [String],
           let requestFile = files.first(where: { $0.hasSuffix("build-request.json") }),
           let data = FileManager.default.contents(atPath: "\(buildDataPath)/\(requestFile)"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containerPath = json["containerPath"] as? String {
            return URL(fileURLWithPath: containerPath).deletingLastPathComponent().path
        }

        return ""
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
