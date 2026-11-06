import Foundation

struct Project: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let defaultCommand = "pnpm dev"

    let id: UUID
    let folderPath: String
    var command: String

    init(id: UUID = UUID(), folderURL: URL, command: String = Project.defaultCommand) throws {
        self.id = id
        self.folderPath = folderURL.standardizedFileURL.path
        self.command = command
        try Self.validate(folderURL: folderURL, command: command)
    }

    init(id: UUID, folderPath: String, command: String) {
        self.id = id
        self.folderPath = folderPath
        self.command = command
    }

    var folderURL: URL {
        URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    var name: String {
        let lastComponent = folderURL.lastPathComponent
        return lastComponent.isEmpty ? folderPath : lastComponent
    }

    var validationError: ProjectValidationError? {
        do {
            try Self.validate(folderURL: folderURL, command: command)
            return nil
        } catch let error as ProjectValidationError {
            return error
        } catch {
            return .directoryUnavailable(folderPath)
        }
    }

    static func validate(folderURL: URL, command: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) else {
            throw ProjectValidationError.directoryMissing(folderURL.path)
        }
        guard isDirectory.boolValue else {
            throw ProjectValidationError.notDirectory(folderURL.path)
        }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.emptyCommand
        }
    }
}

enum ProjectValidationError: LocalizedError, Equatable, Sendable {
    case directoryMissing(String)
    case notDirectory(String)
    case directoryUnavailable(String)
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case let .directoryMissing(path):
            return "The project folder does not exist: \(path)"
        case let .notDirectory(path):
            return "The selected path is not a directory: \(path)"
        case let .directoryUnavailable(path):
            return "The project folder is not currently available: \(path)"
        case .emptyCommand:
            return "The development command cannot be blank."
        }
    }
}
