import Foundation
import Testing
@testable import KGB

struct DerivedDataScannerTests {

    // MARK: - findTodaysResults

    @Test func findTodaysResults_findsTestAndLaunchResults() {
        let mock = MockDirectoryEnumerator(tree: [
            "/DerivedData": [
                URL(fileURLWithPath: "/DerivedData/MyApp-abc")
            ],
            "/DerivedData/MyApp-abc/Logs/Test": [
                URL(fileURLWithPath: "/DerivedData/MyApp-abc/Logs/Test/Test-MyApp-2026.02.21_14-24-35.xcresult")
            ],
            "/DerivedData/MyApp-abc/Logs/Launch": [
                URL(fileURLWithPath: "/DerivedData/MyApp-abc/Logs/Launch/Run-MyApp-2026.02.21_10-00-00.xcresult")
            ]
        ])

        let scanner = DerivedDataScanner(
            enumerator: mock,
            currentDateStamp: { "2026.02.21" }
        )

        let results = scanner.findTodaysResults(in: "/DerivedData")

        #expect(results.count == 2)
        #expect(results.contains { $0.contains("Logs/Test") })
        #expect(results.contains { $0.contains("Logs/Launch") })
    }

    @Test func findTodaysResults_ignoresYesterdaysResults() {
        let mock = MockDirectoryEnumerator(tree: [
            "/DerivedData": [
                URL(fileURLWithPath: "/DerivedData/MyApp-abc")
            ],
            "/DerivedData/MyApp-abc/Logs/Test": [
                URL(fileURLWithPath: "/DerivedData/MyApp-abc/Logs/Test/Test-MyApp-2026.02.20_14-24-35.xcresult")
            ],
            "/DerivedData/MyApp-abc/Logs/Launch": []
        ])

        let scanner = DerivedDataScanner(
            enumerator: mock,
            currentDateStamp: { "2026.02.21" }
        )

        let results = scanner.findTodaysResults(in: "/DerivedData")

        #expect(results.isEmpty)
    }

    @Test func findTodaysResults_returnsEmptyForMissingDerivedData() {
        let mock = MockDirectoryEnumerator(tree: [:])

        let scanner = DerivedDataScanner(
            enumerator: mock,
            currentDateStamp: { "2026.02.21" }
        )

        let results = scanner.findTodaysResults(in: "/nonexistent")

        #expect(results.isEmpty)
    }

    // MARK: - resolveProjectSourceDir

    @Test func resolveProjectSourceDir_extractsContainerPath() {
        let buildRequestJSON = """
        {"containerPath": "/Users/dev/MyApp/MyApp.xcodeproj"}
        """
        let mock = MockDirectoryEnumerator(
            tree: [:],
            enumeratorFiles: ["abc123/build-request.json"],
            fileContents: [
                "/DerivedData/MyApp-abc/Build/Intermediates.noindex/XCBuildData/abc123/build-request.json":
                    buildRequestJSON.data(using: .utf8)!
            ]
        )

        let scanner = DerivedDataScanner(enumerator: mock)

        let result = scanner.resolveProjectSourceDir(
            derivedDataPath: "/DerivedData",
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Test/Test-MyApp-2026.02.21.xcresult"
        )

        #expect(result == "/Users/dev/MyApp")
    }

    @Test func resolveProjectSourceDir_returnsEmptyWhenNoBuildRequest() {
        let mock = MockDirectoryEnumerator(
            tree: [:],
            enumeratorFiles: nil,
            fileContents: [:]
        )

        let scanner = DerivedDataScanner(enumerator: mock)

        let result = scanner.resolveProjectSourceDir(
            derivedDataPath: "/DerivedData",
            xcresultPath: "/DerivedData/MyApp-abc/Logs/Test/Test-MyApp-2026.02.21.xcresult"
        )

        #expect(result == "")
    }
}

// MARK: - Test doubles

struct MockDirectoryEnumerator: DirectoryEnumerating {
    let tree: [String: [URL]]
    var enumeratorFiles: [String]?
    var fileContents: [String: Data]

    init(
        tree: [String: [URL]],
        enumeratorFiles: [String]? = nil,
        fileContents: [String: Data] = [:]
    ) {
        self.tree = tree
        self.enumeratorFiles = enumeratorFiles
        self.fileContents = fileContents
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        guard let contents = tree[url.path] else {
            throw NSError(domain: "MockFS", code: 1)
        }
        return contents
    }

    func contentsAtPath(_ path: String) -> Data? {
        fileContents[path]
    }

    func enumeratorAtPath(_ path: String) -> [String]? {
        enumeratorFiles
    }
}
