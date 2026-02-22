import Foundation
import Testing
@testable import KGB

struct BuildLogParserTests {
    @Test func parse_extractsWorkspaceSchemeDestination() {
        let text = """
        SLF012#some-header-stuff
        Workspace PizzaCoach | Scheme PizzaCoachWatch | Destination Apple Watch Series 11 (46mm)
        Project PizzaCoach | Configuration Debug | Destination Apple Watch Series 11 (46mm) | SDK Simulator
        some other build log content here
        """

        let result = BuildLogParser.parse(text)

        #expect(result != nil)
        #expect(result?.scheme == "PizzaCoachWatch")
        #expect(result?.destination == "Apple Watch Series 11 (46mm)")
        #expect(result?.projectName == "PizzaCoach")
        #expect(result?.isWorkspace == true)
    }

    @Test func parse_extractsProjectSchemeDestination() {
        let text = """
        SLF012#header
        Project SkillSnitch | Configuration Debug | Destination My Mac | SDK macOS 26.2
        Workspace SkillSnitch | Scheme SkillSnitch | Destination My Mac
        more content
        """

        let result = BuildLogParser.parse(text)

        #expect(result != nil)
        #expect(result?.scheme == "SkillSnitch")
        #expect(result?.destination == "My Mac")
        #expect(result?.projectName == "SkillSnitch")
        #expect(result?.isWorkspace == true)
    }

    @Test func parse_returnsNilForUnrecognizedFormat() {
        let text = "this is not a valid xcactivitylog"

        let result = BuildLogParser.parse(text)

        #expect(result == nil)
    }

    @Test func parse_handlesProjectOnly() {
        let text = """
        SLF012#header
        Project MyLib | Scheme MyLib | Destination My Mac
        more content
        """

        let result = BuildLogParser.parse(text)

        #expect(result != nil)
        #expect(result?.scheme == "MyLib")
        #expect(result?.isWorkspace == false)
    }
}
