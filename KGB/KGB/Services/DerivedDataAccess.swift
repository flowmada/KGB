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

    init() {
        checkAccess()
    }

    func checkAccess() {
        var isDir: ObjCBool = false
        hasAccess = FileManager.default.fileExists(atPath: derivedDataPath, isDirectory: &isDir) && isDir.boolValue
    }
}
