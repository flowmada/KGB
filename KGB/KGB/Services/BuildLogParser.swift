import Foundation

enum BuildLogParser {

    struct BuildLogInfo {
        let scheme: String
        let destination: String
        let projectName: String
        let isWorkspace: Bool
    }

    /// Parse scheme + destination from decompressed xcactivitylog text.
    /// Looks for line matching: "Workspace X | Scheme Y | Destination Z"
    /// or: "Project X | Scheme Y | Destination Z"
    static func parse(_ text: String) -> BuildLogInfo? {
        let pattern = #"(Workspace|Project) ([^|]+)\| Scheme ([^|]+)\| Destination ([^\n-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 5 else {
            return nil
        }

        func group(_ i: Int) -> String {
            let range = Range(match.range(at: i), in: text)!
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }

        let type = group(1)
        let projectName = group(2)
        let scheme = group(3)
        let destination = group(4)

        return BuildLogInfo(
            scheme: scheme,
            destination: destination,
            projectName: projectName,
            isWorkspace: type == "Workspace"
        )
    }

    /// Read and decompress an xcactivitylog file, then parse it.
    static func parseFile(at path: String) -> BuildLogInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
