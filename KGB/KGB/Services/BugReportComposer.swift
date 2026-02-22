import AppKit
import Foundation

enum BugReportComposer {
    static func redactHomePath(_ string: String) -> String {
        let username = NSUserName()
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
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
