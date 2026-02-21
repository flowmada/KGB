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
