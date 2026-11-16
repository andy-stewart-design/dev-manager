#if DEBUG
import Foundation
import Testing
@testable import dev_manager

@Suite("Provisioning fixture metadata")
struct ProvisioningFixtureTests {
    @Test("encodes escaped runtime paths and selectors as JSON")
    func escapedMetadata() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fnm\"quoted\\root-\(UUID().uuidString)", isDirectory: true)
        let expected = root.appendingPathComponent("node-versions/v24.21.0/installation/bin/node")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: expected.path, contents: Data()))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: expected.path)

        let validated = ProvisioningManagedNode.validated(
            reportedVersion: "v24.21.0",
            actualExecutablePath: expected.path,
            selector: "v24.21.0",
            expectedExecutableURL: expected,
            root: root,
            executableAvailable: { FileManager.default.isExecutableFile(atPath: $0.path) }
        )
        let node = try #require(validated.node)
        let context = ProvisioningRuntimeContext(
            node: node,
            pnpm: ProvisioningPnpmTool(version: "12.6.0", executableURL: URL(fileURLWithPath: "/tmp/pnpm\"quoted\\bin/pnpm")),
            fnmExecutableURL: URL(fileURLWithPath: "/tmp/fnm\"quoted\\bin/fnm"),
            fnmSelector: "v24.21.0",
            chosenFNMDirectoryURL: root
        )

        let json = try ProvisioningFixture.fixtureMetadataJSON(using: context)
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: String]
        #expect(value["nodePath"] == context.node.executableURL.path)
        #expect(value["pnpmPath"] == context.pnpm?.executableURL.path)
        #expect(value["fnmPath"] == context.fnmExecutableURL.path)
        #expect(value["fnmDirectoryPath"] == context.chosenFNMDirectoryURL.standardizedFileURL.path)
        #expect(value["fnmSelector"] == context.fnmSelector)
    }
}
#endif
