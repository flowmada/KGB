import Foundation
import Observation

@Observable
final class CommandStore {
    private(set) var allCommands: [BuildCommand] = []
    private let persistenceURL: URL?

    struct ProjectGroup: Identifiable {
        let projectName: String
        let commands: [BuildCommand]
        var id: String { projectName }
    }

    init(persistenceURL: URL?) {
        self.persistenceURL = persistenceURL
        if persistenceURL != nil { load() }
    }

    var groupedByProject: [ProjectGroup] {
        let grouped = Dictionary(grouping: allCommands, by: \.projectName)
        return grouped.map { ProjectGroup(projectName: $0.key, commands: $0.value) }
            .sorted { group1, group2 in
                let latest1 = group1.commands.map(\.timestamp).max() ?? .distantPast
                let latest2 = group2.commands.map(\.timestamp).max() ?? .distantPast
                return latest1 > latest2
            }
    }

    func add(_ command: BuildCommand) {
        // Replace existing command for same scheme+action+project, unless flagged as bug
        if let idx = allCommands.firstIndex(where: {
            $0.scheme == command.scheme &&
            $0.action == command.action &&
            $0.projectName == command.projectName &&
            !$0.isFlaggedAsBug
        }) {
            allCommands[idx] = command
        } else {
            allCommands.append(command)
        }
        save()
    }

    // MARK: - Bug Reporting

    struct BugReport {
        let brokenCommand: BuildCommand
        let workingCommand: BuildCommand
    }

    /// Currently pending bug report (broken flagged + matching fix detected)
    var pendingBugReport: BugReport? {
        guard let flagged = allCommands.first(where: { $0.isFlaggedAsBug }),
              let match = allCommands.first(where: {
                  !$0.isFlaggedAsBug &&
                  $0.scheme == flagged.scheme &&
                  $0.projectName == flagged.projectName &&
                  $0.action == flagged.action &&
                  $0.timestamp > flagged.timestamp
              }) else {
            return nil
        }
        return BugReport(brokenCommand: flagged, workingCommand: match)
    }

    func flagAsBug(_ id: UUID) {
        if let idx = allCommands.firstIndex(where: { $0.id == id }) {
            allCommands[idx].isFlaggedAsBug = true
            save()
        }
    }

    func clearBugFlag(_ id: UUID) {
        if let idx = allCommands.firstIndex(where: { $0.id == id }) {
            allCommands[idx].isFlaggedAsBug = false
            save()
        }
    }

    // MARK: - Persistence

    func save() {
        guard let url = persistenceURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try? JSONEncoder().encode(allCommands)
        try? data?.write(to: url, options: .atomic)
    }

    func load() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let commands = try? JSONDecoder().decode([BuildCommand].self, from: data) else {
            return
        }
        allCommands = commands
    }
}
