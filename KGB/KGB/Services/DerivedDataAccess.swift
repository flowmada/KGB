import AppKit
import Foundation
import Observation

@Observable
final class DerivedDataAccess {
    private(set) var hasAccess: Bool = false

    private static let defaultRelativePath = "Library/Developer/Xcode/DerivedData"

    var derivedDataPath: String {
        let custom = UserDefaults.standard.string(forKey: "derivedDataPath") ?? ""
        if !custom.isEmpty { return custom }
        return NSHomeDirectory() + "/" + Self.defaultRelativePath
    }

    var tildeAbbreviatedPath: String {
        let home = NSHomeDirectory()
        if derivedDataPath.hasPrefix(home) {
            return "~" + derivedDataPath.dropFirst(home.count)
        }
        return derivedDataPath
    }

    init() {
        checkAccess()
    }

    func checkAccess() {
        var isDir: ObjCBool = false
        hasAccess = FileManager.default.fileExists(atPath: derivedDataPath, isDirectory: &isDir) && isDir.boolValue
    }

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
}
