import AppKit
import Observation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.kgb.app", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var watcher: DerivedDataWatcher?
    private let scanner = DerivedDataScanner()
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
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
            rootView: PopoverView(store: commandStore, derivedDataAccess: derivedDataAccess) { [weak self] pendingId in
                guard let self,
                      let pending = commandStore.pendingExtractions.first(where: { $0.id == pendingId }),
                      let xcresultPath = pending.xcresultPath else { return }
                // Cancel existing retry task
                retryTasks[pendingId]?.cancel()
                retryTasks.removeValue(forKey: pendingId)
                // Reset to waiting so spinner shows again
                commandStore.updatePendingState(pendingId, to: .waiting)
                // Restart extraction immediately
                attemptExtraction(pendingId: pendingId, xcresultPath: xcresultPath)
            }
        )
        popover.behavior = .transient

        if derivedDataAccess.hasAccess {
            logger.info("DerivedData access OK, starting watcher and scan")
            startWatching()
            scanExistingResults()
        } else {
            logger.warning("No DerivedData access at \(self.derivedDataAccess.derivedDataPath)")
        }
    }

    // MARK: - Watching

    private func startWatching() {
        let derivedDataPath = derivedDataAccess.derivedDataPath

        watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] path in
            guard let self else { return }

            if path.hasSuffix(".xcactivitylog") {
                logger.info("Watcher detected build log: \(path)")
                let info = BuildLogParser.parseFile(at: path)
                Task { @MainActor in
                    guard let info else { return }
                    logger.info("Build log detected: \(info.scheme) → \(info.destination)")
                    self.commandStore.addPending(scheme: info.scheme, destination: info.destination)
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

    // MARK: - Retry extraction

    private func attemptExtraction(pendingId: UUID, xcresultPath: String) {
        let maxAttempts = 12
        let delaySeconds: UInt64 = 5
        let derivedDataPath = derivedDataAccess.derivedDataPath

        let task = Task {
            var currentAttempt = 1
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
                        self.commandStore.resolvePending(pendingId, with: command)
                        self.retryTasks.removeValue(forKey: pendingId)
                    }
                    if currentAttempt > 1 {
                        logger.info("Extracted \(command.scheme) after \(currentAttempt) attempts")
                    }
                    return
                } catch let error as XCResultParser.ParseError where self.isRetryable(error) {
                    logger.debug("Retry \(currentAttempt)/\(maxAttempts) for \(xcresultPath), waiting \(delaySeconds)s")
                    currentAttempt += 1
                    if currentAttempt <= maxAttempts {
                        try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                    }
                } catch {
                    // Non-retryable error — fail immediately
                    logger.warning("Watcher failed \(xcresultPath): \(error)")
                    await MainActor.run {
                        self.commandStore.updatePendingState(pendingId, to: .buildOnly)
                        self.retryTasks.removeValue(forKey: pendingId)
                    }
                    return
                }
            }

            // Exhausted all retries
            logger.warning("Failed to extract \(xcresultPath) after \(maxAttempts) attempts")
            await MainActor.run {
                self.commandStore.updatePendingState(pendingId, to: .buildOnly)
                self.retryTasks.removeValue(forKey: pendingId)
            }
        }

        retryTasks[pendingId] = task
    }

    private func isRetryable(_ error: XCResultParser.ParseError) -> Bool {
        if case .invalidJSON = error { return true }
        return false
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
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
