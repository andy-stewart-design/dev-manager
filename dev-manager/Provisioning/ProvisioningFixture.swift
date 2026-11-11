#if DEBUG
import Darwin
import Foundation

nonisolated struct ProvisioningFixtureResult: Sendable {
    let folder: URL
    let command: String
}

nonisolated enum ProvisioningFixture {
    nonisolated static func materialize(using fnm: URL) throws -> ProvisioningFixtureResult {
        let fileManager = FileManager.default
        let folder = ProvisioningConfiguration.fixtureFolderURL
        let container = folder.deletingLastPathComponent()
        let applicationSupport = container.deletingLastPathComponent()

        guard try fixturePathKind(at: applicationSupport) == .directory else {
            throw FixtureProvisioningError.conflictingPath(applicationSupport.path)
        }
        let containerKind = try fixturePathKind(at: container)
        guard containerKind == .missing || containerKind == .directory else {
            throw FixtureProvisioningError.conflictingPath(container.path)
        }
        let folderKind = try fixturePathKind(at: folder)
        switch folderKind {
        case .directory:
            try validateExistingFixture(at: folder)
            return result(folder: folder, fnm: fnm)
        case .missing:
            break
        case .symlink, .regular, .other:
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }

        if containerKind == .missing {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: false)
        }
        guard try fixturePathKind(at: container) == .directory,
              try fixturePathKind(at: folder) == .missing else {
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }

        let stage = container.appendingPathComponent(".Provisioning Fixture.\(UUID().uuidString).tmp", isDirectory: true)
        guard try fixturePathKind(at: stage) == .missing else {
            throw FixtureProvisioningError.conflictingPath(stage.path)
        }
        var stageExists = false
        defer {
            if stageExists { try? fileManager.removeItem(at: stage) }
        }

        try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
        stageExists = true
        for (name, contents) in ProvisioningConfiguration.fixtureFiles {
            let file = stage.appendingPathComponent(name)
            guard try fixturePathKind(at: file) == .missing else {
                throw FixtureProvisioningError.conflictingPath(file.path)
            }
            try writeNewFixtureFile(contents, at: file)
        }

        guard try fixturePathKind(at: folder) == .missing else {
            throw FixtureProvisioningError.conflictingPath(folder.path)
        }
        try fileManager.moveItem(at: stage, to: folder)
        stageExists = false
        return result(folder: folder, fnm: fnm)
    }

    private nonisolated static func result(folder: URL, fnm: URL) -> ProvisioningFixtureResult {
        ProvisioningFixtureResult(
            folder: folder,
            command: "FNM_COREPACK_ENABLED=false \(shellQuote(fnm.path)) exec --using \(ProvisioningConfiguration.nodeVersion) pnpm dev"
        )
    }

    private nonisolated static func validateExistingFixture(at folder: URL) throws {
        let fileManager = FileManager.default
        let expected = Set(ProvisioningConfiguration.fixtureFiles.map { $0.name })
        let actual = Set(try fileManager.contentsOfDirectory(atPath: folder.path))
        guard actual == expected else {
            throw FixtureProvisioningError.unexpectedContents(folder.path)
        }
        for (name, contents) in ProvisioningConfiguration.fixtureFiles {
            let file = folder.appendingPathComponent(name)
            guard try fixturePathKind(at: file) == .regular else {
                throw FixtureProvisioningError.conflictingPath(file.path)
            }
            let existing = try String(contentsOf: file, encoding: .utf8)
            guard existing == contents else {
                throw FixtureProvisioningError.unexpectedContents(file.path)
            }
        }
    }

    private nonisolated static func fixturePathKind(at url: URL) throws -> FixturePathKind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            guard errno == ENOENT else {
                throw FixtureProvisioningError.pathInspectionFailed(url.path, String(cString: strerror(errno)))
            }
            return .missing
        }
        let type = info.st_mode & S_IFMT
        if type == S_IFLNK { return .symlink }
        if type == S_IFDIR { return .directory }
        if type == S_IFREG { return .regular }
        return .other
    }

    private nonisolated static func writeNewFixtureFile(_ contents: String, at url: URL) throws {
        guard let data = contents.data(using: .utf8) else {
            throw FixtureProvisioningError.writeFailed(url.path, "fixture contents are not UTF-8")
        }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw FixtureProvisioningError.writeFailed(url.path, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return 0 }
            return Darwin.write(descriptor, baseAddress, bytes.count)
        }
        guard written == data.count else {
            throw FixtureProvisioningError.writeFailed(url.path, String(cString: strerror(errno)))
        }
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

nonisolated private enum FixturePathKind: Equatable, Sendable {
    case missing
    case directory
    case regular
    case symlink
    case other
}

nonisolated private enum FixtureProvisioningError: LocalizedError, Sendable {
    case conflictingPath(String)
    case unexpectedContents(String)
    case pathInspectionFailed(String, String)
    case writeFailed(String, String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .conflictingPath(path):
            return "The fixture path conflicts with an existing non-owned path and was left unchanged: \(path)"
        case let .unexpectedContents(path):
            return "An existing fixture path has unexpected contents and was left unchanged: \(path)"
        case let .pathInspectionFailed(path, detail):
            return "The fixture path could not be safely inspected and was left unchanged: \(path): \(detail)"
        case let .writeFailed(path, detail):
            return "The fixture file could not be created: \(path): \(detail)"
        }
    }
}
#endif
