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
        hasAccess = FileManager.default.isReadableFile(atPath: derivedDataPath)
    }
}
