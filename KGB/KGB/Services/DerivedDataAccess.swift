import AppKit
import Foundation
import Observation

@Observable
final class DerivedDataAccess {
    private(set) var hasAccess: Bool = false
    private(set) var resolvedURL: URL?

    private static let bookmarkKey = "derivedDataBookmark"
    private static let defaultDerivedDataPath = "/Library/Developer/Xcode/DerivedData"

    init() {
        restoreBookmark()
    }

    var derivedDataPath: String {
        resolvedURL?.path ?? (NSHomeDirectory() + Self.defaultDerivedDataPath)
    }

    /// Show NSOpenPanel pointed at DerivedData for user to grant access.
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to DerivedData"
        panel.message = "Select your DerivedData folder so KGB can watch for builds."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        // Point the panel at the parent of DerivedData so it's visible and selectable
        let derivedDataURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let parentURL = derivedDataURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parentURL.path) {
            panel.directoryURL = parentURL
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        // Create and store security-scoped bookmark
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
            startAccessing(url: url)
        } catch {
            print("KGB: Failed to create bookmark: \(error)")
        }
    }

    /// Restore a previously-saved security-scoped bookmark.
    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-create bookmark
                let newData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newData, forKey: Self.bookmarkKey)
            }

            startAccessing(url: url)
        } catch {
            print("KGB: Failed to restore bookmark: \(error)")
        }
    }

    private func startAccessing(url: URL) {
        if url.startAccessingSecurityScopedResource() {
            resolvedURL = url
            hasAccess = true
        }
    }
}
