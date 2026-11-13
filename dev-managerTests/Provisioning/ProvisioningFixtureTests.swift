#if DEBUG
import Foundation
import Testing
@testable import dev_manager

@Suite("Provisioning fixture metadata")
struct ProvisioningFixtureTests {
    @Test("encodes escaped runtime paths and selectors as JSON")
    func escapedMetadata() throws {
        let context = ProvisioningRuntimeContext(
            nodeVersion: "24.21.0",
            nodeExecutableURL: URL(fileURLWithPath: "/tmp/node\"quoted\\runtime"),
            pnpmVersion: "12.6.0",
            pnpmExecutableURL: URL(fileURLWithPath: "/tmp/pnpm\"quoted\\bin/pnpm"),
            fnmExecutableURL: URL(fileURLWithPath: "/tmp/fnm\\quoted/fnm"),
            fnmSelector: "v24.21.0'\\selector",
            chosenFNMDirectoryURL: URL(fileURLWithPath: "/tmp/fnm\\quoted/root", isDirectory: true)
        )

        let json = try ProvisioningFixture.fixtureMetadataJSON(using: context)
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: String]
        #expect(value["nodePath"] == context.nodeExecutableURL.path)
        #expect(value["pnpmPath"] == context.pnpmExecutableURL?.path)
        #expect(value["fnmPath"] == context.fnmExecutableURL?.path)
        #expect(value["fnmDirectoryPath"] == context.chosenFNMDirectoryURL?.standardizedFileURL.path)
        #expect(value["fnmSelector"] == context.fnmSelector)
    }
}
#endif
