import AppKit
import Observation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var watcher: DerivedDataWatcher?
    private let scanner = DerivedDataScanner()
    let commandStore = CommandStore(
        persistenceURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KGB/commands.json")
    )
    let derivedDataAccess = DerivedDataAccess()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "KGB")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: commandStore, derivedDataAccess: derivedDataAccess)
        )
        popover.behavior = .transient

        if derivedDataAccess.hasAccess {
            startWatching()
            scanExistingResults()
        }
    }

    // MARK: - Watching

    private func startWatching() {
        let derivedDataPath = derivedDataAccess.derivedDataPath

        watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] xcresultPath in
            guard let self else { return }
            Task {
                let projectSourceDir = self.scanner.resolveProjectSourceDir(
                    derivedDataPath: derivedDataPath,
                    xcresultPath: xcresultPath
                )
                do {
                    let command = try await self.scanner.extractor.extract(
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

    // MARK: - Scan existing results

    private func scanExistingResults() {
        let derivedDataPath = derivedDataAccess.derivedDataPath
        commandStore.isScanning = true

        Task.detached { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.commandStore.isScanning = false
                }
            }

            let commands = await self.scanner.scanAndExtract(derivedDataPath: derivedDataPath)
            for command in commands {
                await MainActor.run {
                    self.commandStore.add(command)
                }
            }
        }
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
