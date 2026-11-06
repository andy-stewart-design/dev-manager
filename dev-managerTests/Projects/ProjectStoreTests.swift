import Foundation
import Testing
@testable import dev_manager

@Test("project folders and commands persist with stable identity")
@MainActor
func projectSettingsRoundTrip() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let projectFolder = root.appendingPathComponent("sample-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let settingsURL = root.appendingPathComponent("settings.json")

    let store = ProjectStore(settingsURL: settingsURL)
    let project = try store.addProject(folderURL: projectFolder)
    try store.updateCommand(for: project.id, command: "npm run dev")

    let restoredStore = ProjectStore(settingsURL: settingsURL)
    #expect(restoredStore.projects.count == 1)
    #expect(restoredStore.projects[0].id == project.id)
    #expect(restoredStore.projects[0].folderPath == projectFolder.standardizedFileURL.path)
    #expect(restoredStore.projects[0].command == "npm run dev")
}

@Test("folder and command validation rejects missing, non-directory, and blank inputs")
@MainActor
func projectInputValidation() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("not-a-folder")
    try Data("fixture".utf8).write(to: fileURL)
    let missingURL = root.appendingPathComponent("missing", isDirectory: true)
    let folderURL = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

    do {
        _ = try Project(folderURL: missingURL)
        Issue.record("A missing folder was accepted")
    } catch let error as ProjectValidationError {
        #expect(error == .directoryMissing(missingURL.path))
    }

    do {
        _ = try Project(folderURL: fileURL)
        Issue.record("A regular file was accepted as a project folder")
    } catch let error as ProjectValidationError {
        #expect(error == .notDirectory(fileURL.path))
    }

    do {
        _ = try Project(folderURL: folderURL, command: "   ")
        Issue.record("A blank command was accepted")
    } catch let error as ProjectValidationError {
        #expect(error == .emptyCommand)
    }
}

@Test("corrupt settings are retained and block destructive replacement")
@MainActor
func corruptSettingsAreRecoverable() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let settingsURL = root.appendingPathComponent("settings.json")
    let originalBytes = Data("this is not settings".utf8)
    try originalBytes.write(to: settingsURL)
    let projectFolder = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)

    let store = ProjectStore(settingsURL: settingsURL)
    #expect(store.isReadOnly)
    #expect(store.projects.isEmpty)
    #expect(store.errorMessage != nil)

    do {
        _ = try store.addProject(folderURL: projectFolder)
        Issue.record("A corrupt settings file was replaced")
    } catch let error as ProjectStoreError {
        #expect(error == .readOnly)
    }
    #expect(try Data(contentsOf: settingsURL) == originalBytes)
}

@Test("removing a project persists while leaving its folder and files untouched")
@MainActor
func projectRemovalPersistsWithoutTouchingDisk() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let projectFolder = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let projectFile = projectFolder.appendingPathComponent("keep.txt")
    let originalBytes = Data("project data".utf8)
    try originalBytes.write(to: projectFile)
    let settingsURL = root.appendingPathComponent("settings.json")

    let store = ProjectStore(settingsURL: settingsURL)
    let project = try store.addProject(folderURL: projectFolder)
    try store.removeProject(id: project.id)

    #expect(store.projects.isEmpty)
    #expect(FileManager.default.fileExists(atPath: projectFolder.path))
    #expect(try Data(contentsOf: projectFile) == originalBytes)
    #expect(ProjectStore(settingsURL: settingsURL).projects.isEmpty)
}

@Test("failed project removal retains the in-memory entry and reports the save error")
@MainActor
func projectRemovalWriteFailureRetainsEntry() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let settingsDirectory = root.appendingPathComponent("settings", isDirectory: true)
    let settingsURL = settingsDirectory.appendingPathComponent("projects.json")
    let projectFolder = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)

    let store = ProjectStore(settingsURL: settingsURL)
    let project = try store.addProject(folderURL: projectFolder)
    try FileManager.default.removeItem(at: settingsURL)
    try FileManager.default.removeItem(at: settingsDirectory)
    let preservedPathBytes = Data("keep this path".utf8)
    try preservedPathBytes.write(to: settingsDirectory)

    do {
        try store.removeProject(id: project.id)
        Issue.record("A failed removal was reported as successful")
    } catch let error as ProjectStoreError {
        if case .writeFailed = error {
            // Expected.
        } else {
            Issue.record("Unexpected store error: \(error.localizedDescription)")
        }
    }

    #expect(store.projects == [project])
    #expect(store.errorMessage?.contains("could not be saved") == true)
    #expect(try Data(contentsOf: settingsDirectory) == preservedPathBytes)
}

@Test("removing an unknown project is safe and does not rewrite settings")
@MainActor
func unknownProjectRemovalIsSafe() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let projectFolder = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)
    let settingsURL = root.appendingPathComponent("settings.json")
    let store = ProjectStore(settingsURL: settingsURL)
    let project = try store.addProject(folderURL: projectFolder)
    let originalSettings = try Data(contentsOf: settingsURL)

    do {
        try store.removeProject(id: UUID())
        Issue.record("An unknown project removal was accepted")
    } catch let error as ProjectStoreError {
        #expect(error == .projectNotFound)
    }

    #expect(store.projects == [project])
    #expect(try Data(contentsOf: settingsURL) == originalSettings)
}

@Test("settings write failures are visible without changing the in-memory list")
@MainActor
func settingsWriteFailureIsVisible() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let parentFile = root.appendingPathComponent("not-a-directory")
    let originalBytes = Data("keep this file".utf8)
    try originalBytes.write(to: parentFile)
    let settingsURL = parentFile.appendingPathComponent("settings.json")
    let projectFolder = root.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: false)

    let store = ProjectStore(settingsURL: settingsURL)
    do {
        _ = try store.addProject(folderURL: projectFolder)
        Issue.record("A write failure was not reported")
    } catch let error as ProjectStoreError {
        if case .writeFailed = error {
            // Expected.
        } else {
            Issue.record("Unexpected store error: \(error.localizedDescription)")
        }
    }
    #expect(store.projects.isEmpty)
    #expect(store.errorMessage?.contains("could not be saved") == true)
    #expect(try Data(contentsOf: parentFile) == originalBytes)
}

@MainActor
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dev-manager-step1-1-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
