import Foundation

nonisolated struct GitHubHostname: Equatable, Sendable {
    let value: String

    private struct ValidationError: LocalizedError {
        var errorDescription: String? { "Enter a valid hostname or HTTPS root URL without credentials, a port, query, or fragment." }
    }

    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw ValidationError() }
        let host: String
        if text.lowercased().hasPrefix("https://") {
            let remainder = String(text.dropFirst(8))
            guard !remainder.contains("?"), !remainder.contains("#"), !remainder.contains("@"), !remainder.contains(":") else { throw ValidationError() }
            if remainder.hasSuffix("/") {
                host = String(remainder.dropLast())
            } else {
                host = remainder
            }
        } else {
            host = text
        }
        let normalized = host.lowercased()
        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard normalized.utf8.count <= 253, !labels.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" && label.utf8.allSatisfy {
                (97...122).contains($0) || (48...57).contains($0) || $0 == 45
            }
        }) else { throw ValidationError() }
        value = normalized
    }

    func validatesDeviceURL(_ url: URL) -> Bool {
        // Inspect the original authority too: URLComponents can hide an empty port or userinfo.
        let raw = url.absoluteString
        guard raw.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              raw.lowercased().hasPrefix("https://") else { return false }
        let rest = raw.dropFirst(8)
        guard let slash = rest.firstIndex(of: "/") else { return false }
        let authority = rest[..<slash]
        guard !authority.contains("@"), !authority.contains(":"),
              authority.lowercased() == value,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath == "/login/device" || components.percentEncodedPath == "/login/device/" else { return false }
        return true
    }
}
