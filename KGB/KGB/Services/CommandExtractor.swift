import Foundation

// MARK: - Protocols for testability

protocol ShellExecuting: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> Data
}

protocol FileChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
}

// MARK: - Production implementations

struct ProcessShellExecutor: ShellExecuting {
    func run(_ command: String, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [command] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

struct RealFileChecker: FileChecking {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
}

// MARK: - CommandExtractor

struct CommandExtractor {
    let shell: ShellExecuting
    let fileChecker: FileChecking

    init(shell: ShellExecuting = ProcessShellExecutor(),
         fileChecker: FileChecking = RealFileChecker()) {
        self.shell = shell
        self.fileChecker = fileChecker
    }

    func extract(xcresultPath: String, projectSourceDir: String) async throws -> BuildCommand {
        let filename = URL(fileURLWithPath: xcresultPath).lastPathComponent

        // 1. Parse scheme + action from filename
        guard let filenameResult = XCResultParser.parseFilename(filename) else {
            throw ExtractionError.malformedFilename(filename)
        }

        // 2. Run xcresulttool
        let jsonData = try await shell.run("xcresulttool", arguments: [
            "get", "build-results",
            "--path", xcresultPath
        ])

        // 3. Parse destination from JSON
        let destination = try XCResultParser.parseBuildResultsJSON(jsonData)

        // 4. Detect workspace vs project
        let (projectPath, projectType) = try detectProjectType(in: projectSourceDir)

        return BuildCommand(
            projectPath: projectPath,
            projectType: projectType,
            scheme: filenameResult.scheme,
            action: filenameResult.action,
            platform: destination.platform,
            deviceName: destination.deviceName,
            osVersion: destination.osVersion,
            timestamp: Date()
        )
    }

    private func detectProjectType(in dir: String) throws -> (String, BuildCommand.ProjectType) {
        let contents = try fileChecker.contentsOfDirectory(atPath: dir)
        if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return ("\(dir)/\(ws)", .workspace)
        }
        if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return ("\(dir)/\(proj)", .project)
        }
        throw ExtractionError.noProjectFound(dir)
    }

    enum ExtractionError: Error {
        case malformedFilename(String)
        case noProjectFound(String)
    }
}
