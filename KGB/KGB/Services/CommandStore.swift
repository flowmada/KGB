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
        // Replace existing command for same scheme+action+project, or append
        if let idx = allCommands.firstIndex(where: {
            $0.scheme == command.scheme &&
            $0.action == command.action &&
            $0.projectName == command.projectName
        }) {
            allCommands[idx] = command
        } else {
            allCommands.append(command)
        }
        save()
    }

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
