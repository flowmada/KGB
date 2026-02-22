import Foundation
import os

private let logger = Logger(subsystem: "com.kgb.app", category: "Scanner")

// MARK: - Protocol for testability

protocol DirectoryEnumerating: Sendable {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func contentsAtPath(_ path: String) -> Data?
    func enumeratorAtPath(_ path: String) -> [String]?
}

// MARK: - Production implementation

struct RealDirectoryEnumerator: DirectoryEnumerating {
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
    }

    func contentsAtPath(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    func enumeratorAtPath(_ path: String) -> [String]? {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return nil }
        return enumerator.allObjects as? [String]
    }
}

// MARK: - DerivedDataScanner

struct DerivedDataScanner {
    let enumerator: DirectoryEnumerating
    let extractor: CommandExtractor
    var currentDateStamp: @Sendable () -> String

    private static let xcresultLogDirs = ["Logs/Test", "Logs/Launch"]

    init(
        enumerator: DirectoryEnumerating = RealDirectoryEnumerator(),
        extractor: CommandExtractor = CommandExtractor(),
        currentDateStamp: @Sendable @escaping () -> String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            return formatter.string(from: Date())
        }
    ) {
        self.enumerator = enumerator
        self.extractor = extractor
        self.currentDateStamp = currentDateStamp
    }

    /// Finds today's .xcresult files across all project subdirectories in DerivedData.
    func findTodaysResults(in derivedDataPath: String) -> [String] {
        let derivedDataURL = URL(fileURLWithPath: derivedDataPath)
        let todayStamp = currentDateStamp()
        logger.info("Scanning \(derivedDataPath) for xcresults matching \(todayStamp)")

        guard let projectDirs = try? enumerator.contentsOfDirectory(at: derivedDataURL) else {
            logger.warning("Could not list contents of \(derivedDataPath)")
            return []
        }

        logger.info("Found \(projectDirs.count) project dirs")

        var results: [String] = []
        for projectDir in projectDirs {
            for logsDir in Self.xcresultLogDirs {
                let logsURL = projectDir.appendingPathComponent(logsDir)
                guard let contents = try? enumerator.contentsOfDirectory(at: logsURL) else {
                    continue
                }
                for item in contents where item.pathExtension == "xcresult" {
                    if item.lastPathComponent.contains(todayStamp) {
                        results.append(item.path)
                    }
                }
            }
        }
        logger.info("Found \(results.count) xcresult(s) for today")
        return results
    }

    /// Resolves the project source directory from a DerivedData xcresult path.
    func resolveProjectSourceDir(derivedDataPath: String, xcresultPath: String) -> String {
        let components = xcresultPath
            .replacingOccurrences(of: derivedDataPath + "/", with: "")
            .components(separatedBy: "/")
        guard let projectFolder = components.first else { return "" }

        let buildDataPath = "\(derivedDataPath)/\(projectFolder)/Build/Intermediates.noindex/XCBuildData"
        guard let files = enumerator.enumeratorAtPath(buildDataPath),
              let requestFile = files.first(where: { $0.hasSuffix("build-request.json") }),
              let data = enumerator.contentsAtPath("\(buildDataPath)/\(requestFile)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containerPath = json["containerPath"] as? String else {
            return ""
        }

        return URL(fileURLWithPath: containerPath).deletingLastPathComponent().path
    }

    /// Scans DerivedData for today's results and extracts build commands.
    func scanAndExtract(derivedDataPath: String) async -> [BuildCommand] {
        let paths = findTodaysResults(in: derivedDataPath)
        var commands: [BuildCommand] = []

        for path in paths {
            let projectSourceDir = resolveProjectSourceDir(
                derivedDataPath: derivedDataPath,
                xcresultPath: path
            )
            logger.info("Extracting: \(path) (projectDir: \(projectSourceDir))")
            do {
                let command = try await extractor.extract(
                    xcresultPath: path,
                    projectSourceDir: projectSourceDir
                )
                logger.info("Extracted: \(command.scheme) \(command.action.rawValue)")
                commands.append(command)
            } catch {
                logger.error("Skipped \(path): \(error)")
            }
        }
        logger.info("Scan complete: \(commands.count) command(s) extracted")
        return commands
    }
}
