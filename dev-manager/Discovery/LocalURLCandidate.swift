import Foundation

/// A URL announced by a managed run which is eligible for later ownership and
/// readiness checks. This type does not imply that a server is listening.
nonisolated struct LocalURLCandidate: Hashable, Sendable {
    let url: URL

    var absoluteString: String { url.absoluteString }
    var scheme: String { url.scheme ?? "" }
    var host: String { url.host ?? "" }
    var port: Int? { url.port }

    nonisolated init?(url: URL) {
        guard let normalized = Self.normalize(url: url) else { return nil }
        self.url = normalized
    }

    nonisolated init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }

    private nonisolated static func normalize(url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme,
              let rawHost = components.host else { return nil }

        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        guard components.user == nil && components.password == nil else { return nil }

        let rawNormalizedHost = rawHost.lowercased()
        let host = rawNormalizedHost.hasPrefix("[") && rawNormalizedHost.hasSuffix("]")
            ? String(rawNormalizedHost.dropFirst().dropLast()) : rawNormalizedHost
        guard host == "localhost" || host == "127.0.0.1" || host == "::1" else { return nil }
        if let port = components.port, !(1...65_535).contains(port) { return nil }
        if let explicitPort = Self.explicitPort(in: url.absoluteString) {
            guard let port = Int(explicitPort), (1...65_535).contains(port) else { return nil }
        }

        components.scheme = scheme
        components.host = host == "::1" ? "[::1]" : host
        if components.path.isEmpty { components.path = "/" }
        guard let normalizedURL = components.url else { return nil }
        return normalizedURL
    }

    private nonisolated static func explicitPort(in absoluteString: String) -> String? {
        guard let schemeEnd = absoluteString.range(of: "://") else { return nil }
        let authorityStart = schemeEnd.upperBound
        let authorityEnd = absoluteString[authorityStart...].firstIndex(where: { "/?#".contains($0) }) ?? absoluteString.endIndex
        let authority = String(absoluteString[authorityStart..<authorityEnd])
        guard !authority.isEmpty else { return nil }
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            let tail = authority[authority.index(after: close)...]
            guard tail.hasPrefix(":") else { return nil }
            return String(tail.dropFirst())
        }
        guard authority.filter({ $0 == ":" }).count == 1,
              let colon = authority.lastIndex(of: ":") else { return nil }
        return String(authority[authority.index(after: colon)...])
    }
}
