import Combine
import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    static let schemaVersion = 1

    @Published private(set) var projects: [Project] = []
    @Published private(set) var errorMessage: String?

    let settingsURL: URL
    private(set) var isReadOnly = false

    private struct Settings: Codable {
        let schemaVersion: Int
        let projects: [Project]
    }

    init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? Self.defaultSettingsURL()
        load()
    }

    static func defaultSettingsURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Dev Manager", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }

    func addProject(folderURL: URL, command: String = Project.defaultCommand) throws -> Project {
        guard !isReadOnly else {
            throw ProjectStoreError.readOnly
        }

        let project = try Project(folderURL: folderURL, command: command)
        var updatedProjects = projects
        updatedProjects.append(project)
        try save(updatedProjects)
        projects = updatedProjects
        errorMessage = nil
        return project
    }

    func updateCommand(for projectID: UUID, command: String) throws {
        guard !isReadOnly else {
            throw ProjectStoreError.readOnly
        }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.emptyCommand
        }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectStoreError.projectNotFound
        }

        var updatedProjects = projects
        updatedProjects[index].command = command
        try save(updatedProjects)
        projects = updatedProjects
        errorMessage = nil
    }

    func removeProject(id projectID: UUID) throws {
        guard !isReadOnly else {
            throw ProjectStoreError.readOnly
        }
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectStoreError.projectNotFound
        }

        var updatedProjects = projects
        updatedProjects.remove(at: index)
        try save(updatedProjects)
        projects = updatedProjects
        errorMessage = nil
    }

    func report(error: Error) {
        errorMessage = error.localizedDescription
    }

    func clearError() {
        errorMessage = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            guard settings.schemaVersion == Self.schemaVersion else {
                throw ProjectStoreError.unsupportedSchema(settings.schemaVersion)
            }
            projects = settings.projects
        } catch {
            isReadOnly = true
            errorMessage = ProjectStoreError.unreadableSettings(underlying: error).localizedDescription
        }
    }

    private func save(_ projects: [Project]) throws {
        do {
            let settings = Settings(schemaVersion: Self.schemaVersion, projects: projects)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            let storeError = ProjectStoreError.writeFailed(underlying: error)
            errorMessage = storeError.localizedDescription
            throw storeError
        }
    }
}

enum ProjectStoreError: LocalizedError, Equatable, Sendable {
    case readOnly
    case projectNotFound
    case unsupportedSchema(Int)
    case unreadableSettings(underlying: Error)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .readOnly:
            return "Settings could not be changed because the saved settings are unreadable. The original file was left untouched. Fix or remove it deliberately, then relaunch."
        case .projectNotFound:
            return "That project is no longer available in the saved project list."
        case let .unsupportedSchema(version):
            return "Unsupported settings schema version \(version)."
        case let .unreadableSettings(underlying):
            return "Settings could not be read, so they were not replaced: \(underlying.localizedDescription)"
        case let .writeFailed(underlying):
            return "Settings could not be saved. Existing saved settings were left untouched: \(underlying.localizedDescription)"
        }
    }

    static func == (lhs: ProjectStoreError, rhs: ProjectStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.readOnly, .readOnly), (.projectNotFound, .projectNotFound):
            return true
        case let (.unsupportedSchema(left), .unsupportedSchema(right)):
            return left == right
        case (.unreadableSettings, .unreadableSettings), (.writeFailed, .writeFailed):
            return true
        default:
            return false
        }
    }
}
