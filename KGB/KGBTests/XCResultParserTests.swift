import Foundation
import Testing
@testable import KGB

struct XCResultParserTests {
    // MARK: - Filename parsing

    @Test func parseFilename_testAction() {
        let result = XCResultParser.parseFilename(
            "Test-PizzaCoach-2026.02.21_14-24-35--0800.xcresult"
        )
        #expect(result?.scheme == "PizzaCoach")
        #expect(result?.action == .test)
    }

    @Test func parseFilename_buildAction() {
        let result = XCResultParser.parseFilename(
            "Build-MyApp-2026.02.21_11-03-09--0800.xcresult"
        )
        #expect(result?.scheme == "MyApp")
        #expect(result?.action == .build)
    }

    @Test func parseFilename_runAction_mapsToBuild() {
        let result = XCResultParser.parseFilename(
            "Run-PizzaCoach-2026.02.21_11-03-09--0800.xcresult"
        )
        #expect(result?.scheme == "PizzaCoach")
        #expect(result?.action == .build)
    }

    @Test func parseFilename_schemeWithHyphens() {
        let result = XCResultParser.parseFilename(
            "Test-My-Cool-App-2026.02.21_14-24-35--0800.xcresult"
        )
        // Hyphenated scheme names are ambiguous — the parser splits on
        // the first hyphen after the action prefix. This test documents
        // the known limitation. We'll improve with actionTitle fallback.
        #expect(result != nil)
    }

    @Test func parseFilename_malformed() {
        let result = XCResultParser.parseFilename("garbage.xcresult")
        #expect(result == nil)
    }

    // MARK: - JSON parsing

    @Test func parseJSON_iOSSimulator() throws {
        let json = """
        {
          "destination": {
            "architecture": "arm64",
            "deviceId": "883F39DE-9EA1-41DD-A061-630197BB02B5",
            "deviceName": "iPhone 17 Pro",
            "modelName": "iPhone 17 Pro",
            "osBuildNumber": "23C54",
            "osVersion": "26.2",
            "platform": "iOS Simulator"
          },
          "status": "succeeded"
        }
        """
        let result = try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        #expect(result.deviceName == "iPhone 17 Pro")
        #expect(result.osVersion == "26.2")
        #expect(result.platform == "iOS Simulator")
    }

    @Test func parseJSON_watchOSSimulator() throws {
        let json = """
        {
          "destination": {
            "architecture": "arm64",
            "deviceId": "2317531A-BDE6-45CC-9B39-23C78BE00AC9",
            "deviceName": "Apple Watch Series 11 (46mm)",
            "modelName": "Apple Watch Series 11 (46mm)",
            "osBuildNumber": "23S303",
            "osVersion": "26.0",
            "platform": "watchOS Simulator"
          },
          "status": "succeeded"
        }
        """
        let result = try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        #expect(result.deviceName == "Apple Watch Series 11 (46mm)")
        #expect(result.platform == "watchOS Simulator")
    }

    @Test func parseJSON_missingDestination_throws() {
        let json = """
        { "status": "succeeded" }
        """
        #expect(throws: XCResultParser.ParseError.self) {
            try XCResultParser.parseBuildResultsJSON(json.data(using: .utf8)!)
        }
    }
}
