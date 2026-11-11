#if DEBUG
import AppKit
import Foundation

nonisolated enum HomebrewProvisioningError: LocalizedError, Sendable {
    case invalidReleaseAPI
    case releaseAPI(status: Int)
    case assetNotFound
    case invalidDownloadURL
    case packageDownload(status: Int)
    case insecurePackageDownload
    case emptyPackage
    case couldNotOpenInstaller

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidReleaseAPI:
            return "The official Homebrew release API URL was invalid."
        case let .releaseAPI(status):
            return "The official Homebrew release API returned HTTP status \(status)."
        case .assetNotFound:
            return "The latest official Homebrew release did not contain the exact Homebrew.pkg asset."
        case .invalidDownloadURL:
            return "The release asset did not provide a valid official HTTPS Homebrew download URL."
        case let .packageDownload(status):
            return "The official Homebrew package download returned HTTP status \(status)."
        case .insecurePackageDownload:
            return "The final Homebrew package response was not HTTPS."
        case .emptyPackage:
            return "The downloaded Homebrew.pkg was empty."
        case .couldNotOpenInstaller:
            return "macOS could not open Homebrew.pkg through Launch Services."
        }
    }
}

nonisolated enum HomebrewPackageInstaller {
    @MainActor static func openPackage(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    nonisolated static func downloadPackage(onDownloadReady: @escaping @Sendable @MainActor () -> Void) async throws -> URL {
        guard let apiURL = URL(string: ProvisioningConfiguration.homebrewReleaseAPIURL) else {
            throw HomebrewProvisioningError.invalidReleaseAPI
        }

        var apiRequest = URLRequest(url: apiURL)
        apiRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        apiRequest.setValue("DevManager/0.1 provisioning-spike", forHTTPHeaderField: "User-Agent")
        apiRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let session = urlSession()
        let (data, response) = try await session.data(for: apiRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw HomebrewProvisioningError.releaseAPI(status: status)
        }

        let release = try JSONDecoder().decode(HomebrewRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == ProvisioningConfiguration.homebrewPackageName }) else {
            throw HomebrewProvisioningError.assetNotFound
        }
        guard let downloadURL = URL(string: asset.browserDownloadURL),
              isOfficialDownloadURL(downloadURL) else {
            throw HomebrewProvisioningError.invalidDownloadURL
        }

        await onDownloadReady()
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("DevManager/0.1 provisioning-spike", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, downloadResponse) = try await session.download(for: downloadRequest)
        guard let downloadHTTPResponse = downloadResponse as? HTTPURLResponse,
              (200..<300).contains(downloadHTTPResponse.statusCode) else {
            let status = (downloadResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw HomebrewProvisioningError.packageDownload(status: status)
        }
        guard downloadHTTPResponse.url?.scheme?.lowercased() == "https" else {
            throw HomebrewProvisioningError.insecurePackageDownload
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevManager-Homebrew-\(UUID().uuidString).pkg")
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        guard let byteCount = attributes[.size] as? NSNumber, byteCount.int64Value > 0 else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw HomebrewProvisioningError.emptyPackage
        }
        return destinationURL
    }

    private nonisolated static func urlSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration)
    }

    private nonisolated static func isOfficialDownloadURL(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix(ProvisioningConfiguration.officialHomebrewReleasePrefix) &&
            url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == "github.com" &&
            url.pathComponents.last == ProvisioningConfiguration.homebrewPackageName
    }
}

nonisolated private struct HomebrewRelease: Decodable, Sendable {
    let assets: [HomebrewReleaseAsset]
}

nonisolated private struct HomebrewReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
#endif
