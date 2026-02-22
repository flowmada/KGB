import AppKit
import Observation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var watcher: DerivedDataWatcher?
    private let extractor = CommandExtractor()
    private var accessObservation: (any Sendable)?
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

        accessObservation = withObservationTracking {
            _ = self.derivedDataAccess.hasAccess
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.onAccessChanged()
            }
        }
    }

    private func onAccessChanged() {
        if derivedDataAccess.hasAccess && watcher == nil {
            startWatching()
            scanExistingResults()
        }

        accessObservation = withObservationTracking {
            _ = self.derivedDataAccess.hasAccess
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.onAccessChanged()
            }
        }
    }

    // MARK: - Watching

    private func startWatching() {
        let derivedDataPath = derivedDataAccess.derivedDataPath

        watcher = DerivedDataWatcher(path: derivedDataPath) { [weak self] xcresultPath in
            self?.processXCResult(at: xcresultPath, derivedDataPath: derivedDataPath)
        }
        watcher?.start()
    }

    // MARK: - Scan existing results

    /// Find all .xcresult bundles from today and process them.
    private func scanExistingResults() {
        let derivedDataPath = derivedDataAccess.derivedDataPath
        let todayStamp = todayDateStamp()

        Task.detached { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let derivedDataURL = URL(fileURLWithPath: derivedDataPath)

            guard let projectDirs = try? fm.contentsOfDirectory(
                at: derivedDataURL,
                includingPropertiesForKeys: nil
            ) else { return }

            for projectDir in projectDirs {
                // Check Logs/Build/ and Logs/Test/ for .xcresult bundles
                let logsDirs = ["Logs/Build", "Logs/Test"]
                for logsDir in logsDirs {
                    let logsURL = projectDir.appendingPathComponent(logsDir)
                    guard let contents = try? fm.contentsOfDirectory(
                        at: logsURL,
                        includingPropertiesForKeys: nil
                    ) else { continue }

                    for item in contents where item.pathExtension == "xcresult" {
                        let filename = item.lastPathComponent
                        // Filter to today's results by checking the date stamp in the filename
                        if filename.contains(todayStamp) {
                            self.processXCResult(at: item.path, derivedDataPath: derivedDataPath)
                        }
                    }
                }
            }
        }
    }

    /// Returns today's date as "YYYY.MM.DD" to match xcresult filename format.
    private func todayDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date())
    }

    // MARK: - Processing

    private func processXCResult(at xcresultPath: String, derivedDataPath: String) {
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

    /// Resolve the project source directory from DerivedData paths.
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
