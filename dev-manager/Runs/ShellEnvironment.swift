import Foundation

struct ShellEnvironment: Sendable {
    let shellURL: URL
    let environment: [String: String]

    static func currentZsh(homeDirectory: URL? = nil, zdotdir: URL? = nil) throws -> ShellEnvironment {
        let shellURL = URL(fileURLWithPath: "/bin/zsh")
        guard FileManager.default.isExecutableFile(atPath: shellURL.path) else {
            throw ShellEnvironmentError.unsupportedShell("/bin/zsh is not available on this Mac.")
        }

        var values = ProcessInfo.processInfo.environment
        let home = homeDirectory?.path ?? values["HOME"] ?? NSHomeDirectory()
        guard !home.isEmpty else {
            throw ShellEnvironmentError.missingHome
        }
        values["HOME"] = home
        values["SHELL"] = shellURL.path
        values["TERM"] = values["TERM"] ?? "dumb"
        values["USER"] = values["USER"] ?? NSUserName()
        values["LOGNAME"] = values["LOGNAME"] ?? NSUserName()
        if let zdotdir {
            values["ZDOTDIR"] = zdotdir.path
        }
        // A GUI launch may have an empty or stale PATH. Keep a safe system baseline;
        // .zprofile/.zshrc are then allowed to add Homebrew and fnm as usual.
        let baseline = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        values["PATH"] = baseline
        return ShellEnvironment(shellURL: shellURL, environment: values)
    }
}

enum ShellEnvironmentError: LocalizedError, Equatable, Sendable {
    case unsupportedShell(String)
    case missingHome

    var errorDescription: String? {
        switch self {
        case let .unsupportedShell(message):
            return "Unsupported shell environment: \(message) Dev Manager currently supports the owner's zsh login/interactive setup only."
        case .missingHome:
            return "Could not determine the user's home directory for zsh startup files."
        }
    }
}
