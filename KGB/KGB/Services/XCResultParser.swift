import Foundation

enum XCResultParser {

    struct FilenameResult {
        let scheme: String
        let action: BuildCommand.BuildAction
    }

    struct BuildResultsJSON: Decodable {
        let destination: Destination
        let actionTitle: String?

        struct Destination: Decodable {
            let deviceName: String
            let osVersion: String
            let platform: String
        }
    }

    struct DestinationInfo {
        let deviceName: String
        let osVersion: String
        let platform: String
    }

    enum ParseError: Error {
        case malformedFilename
        case missingDestination
        case invalidJSON(Error)
    }

    /// Parse scheme name and action from an .xcresult filename.
    /// Format: "Action-SchemeName-YYYY.MM.DD_HH-MM-SS-+ZZZZ.xcresult"
    static func parseFilename(_ filename: String) -> FilenameResult? {
        let name = filename.replacingOccurrences(of: ".xcresult", with: "")

        // Find the action prefix
        let actionMap: [(prefix: String, action: BuildCommand.BuildAction)] = [
            ("Test-", .test),
            ("Build-", .build),
            ("Run-", .build),  // Run maps to build
        ]

        for (prefix, action) in actionMap {
            guard name.hasPrefix(prefix) else { continue }
            let remainder = String(name.dropFirst(prefix.count))

            // Find the timestamp portion: starts with YYYY.MM.DD
            // Look for the pattern "-YYYY." where YYYY is 4 digits
            let pattern = #"-\d{4}\.\d{2}\.\d{2}_"#
            guard let range = remainder.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let scheme = String(remainder[remainder.startIndex..<range.lowerBound])
            guard !scheme.isEmpty else { continue }

            return FilenameResult(scheme: scheme, action: action)
        }

        return nil
    }

    /// Parse destination info from xcresulttool get build-results JSON output.
    static func parseBuildResultsJSON(_ data: Data) throws -> DestinationInfo {
        let result: BuildResultsJSON
        do {
            result = try JSONDecoder().decode(BuildResultsJSON.self, from: data)
        } catch {
            throw ParseError.invalidJSON(error)
        }

        return DestinationInfo(
            deviceName: result.destination.deviceName,
            osVersion: result.destination.osVersion,
            platform: result.destination.platform
        )
    }
}
