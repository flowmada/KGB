import Foundation
import Observation

@Observable
final class CommandStore {
    private(set) var allCommands: [BuildCommand] = []
    var isScanning: Bool = false
    private(set) var pendingExtractions: [PendingExtraction] = []
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

    // MARK: - Pending Extractions

    struct PendingExtraction: Identifiable {
        let id: UUID
        let scheme: String
        let destination: String?
        var xcresultPath: String?
        var state: State

        enum State {
            case waiting    // spinner, actively trying to extract xcresult
            case buildOnly  // have build info, no full command yet
            case failed     // couldn't parse xcactivitylog
        }

        init(id: UUID = UUID(), scheme: String, destination: String? = nil,
             xcresultPath: String? = nil, state: State = .buildOnly) {
            self.id = id
            self.scheme = scheme
            self.destination = destination
            self.xcresultPath = xcresultPath
            self.state = state
        }
    }

    @discardableResult
    func addPending(scheme: String, destination: String? = nil,
                    xcresultPath: String? = nil, state: PendingExtraction.State = .buildOnly) -> UUID {
        let pending = PendingExtraction(scheme: scheme, destination: destination,
                                         xcresultPath: xcresultPath, state: state)
        pendingExtractions.append(pending)
        return pending.id
    }

    func resolvePending(_ id: UUID, with command: BuildCommand) {
        pendingExtractions.removeAll { $0.id == id }
        add(command)
    }

    func updatePendingState(_ id: UUID, to state: PendingExtraction.State) {
        if let idx = pendingExtractions.firstIndex(where: { $0.id == id }) {
            pendingExtractions[idx].state = state
        }
    }

    func updatePendingXcresultPath(_ id: UUID, path: String) {
        if let idx = pendingExtractions.firstIndex(where: { $0.id == id }) {
            pendingExtractions[idx].xcresultPath = path
        }
    }

    func pendingForScheme(_ scheme: String) -> PendingExtraction? {
        pendingExtractions.first { $0.scheme == scheme && $0.state == .buildOnly }
    }

    func removePending(_ id: UUID) {
        pendingExtractions.removeAll { $0.id == id }
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
