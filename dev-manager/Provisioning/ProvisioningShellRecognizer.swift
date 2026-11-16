import Foundation

/// Pure shell text generation, marker validation, and conservative fnm
/// initializer recognition. This type never reads files or executes shell code.
enum ProvisioningShellRecognizer {
    private static let startMarker = "# >>> Dev Manager managed fnm initialization >>>"
    private static let endMarker = "# <<< Dev Manager managed fnm initialization <<<"

    static func countOccurrences(of value: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: value, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    static func makeManagedBlock(fnmPath: String, nodeVersion: String, fnmDirectoryURL: URL?) -> String {
        let fnmDirectory = URL(fileURLWithPath: fnmPath).deletingLastPathComponent().path
        let rootLine = fnmDirectoryURL.map { "export FNM_DIR=\(shellQuote($0.standardizedFileURL.path))\n" } ?? ""
        return "\(startMarker)\n\(rootLine)export PATH=\(shellQuote(fnmDirectory)):$PATH\neval \"$(\(shellQuote(fnmPath)) env --use-on-cd --shell zsh)\"\n# Dev Manager selects the pinned runtime for this shell; no install or network action is requested.\nif command -v fnm >/dev/null 2>&1; then\n  fnm use \(shellQuote(nodeVersion)) >/dev/null 2>&1\nfi\n\(endMarker)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isCanonicalManagedBlock(_ block: String) -> Bool {
        let lines = block.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hasRoot = lines.count == 9
        let oldShape = lines.count == 8
        guard hasRoot || oldShape else { return false }
        let pathIndex = hasRoot ? 2 : 1
        let evalIndex = hasRoot ? 3 : 2
        let commentIndex = hasRoot ? 4 : 3
        let ifIndex = hasRoot ? 5 : 4
        let useIndex = hasRoot ? 6 : 5
        let fiIndex = hasRoot ? 7 : 6
        let endIndex = hasRoot ? 8 : 7
        guard lines[0] == startMarker,
              lines[pathIndex].hasPrefix("export PATH='") && lines[pathIndex].hasSuffix("':$PATH"),
              lines[evalIndex].hasPrefix("eval \"$('"),
              lines[evalIndex].hasSuffix("' env --use-on-cd --shell zsh)\""),
              lines[commentIndex] == "# Dev Manager selects the pinned runtime for this shell; no install or network action is requested.",
              lines[ifIndex] == "if command -v fnm >/dev/null 2>&1; then",
              lines[useIndex].hasPrefix("  fnm use '") && lines[useIndex].hasSuffix("' >/dev/null 2>&1"),
              lines[fiIndex] == "fi",
              lines[endIndex] == endMarker else { return false }
        if hasRoot {
            let rootPrefix = "export FNM_DIR='"
            guard lines[1].hasPrefix(rootPrefix), lines[1].hasSuffix("'") else { return false }
            let root = String(lines[1].dropFirst(rootPrefix.count).dropLast())
            guard root.hasPrefix("/"), !root.contains("\n") else { return false }
        }
        let pathPrefix = "export PATH='"
        let pathSuffix = "':$PATH"
        let path = String(lines[pathIndex].dropFirst(pathPrefix.count).dropLast(pathSuffix.count))
        guard path.hasPrefix("/"), !path.contains("\n") else { return false }
        let evalPrefix = "eval \"$('"
        let evalSuffix = "' env --use-on-cd --shell zsh)\""
        guard lines[evalIndex].hasPrefix(evalPrefix), lines[evalIndex].hasSuffix(evalSuffix) else { return false }
        let evalPath = String(lines[evalIndex].dropFirst(evalPrefix.count).dropLast(evalSuffix.count))
        return evalPath.hasPrefix("/") && !evalPath.contains("\n")
    }

    static func managedBlock(from text: String) throws -> String {
        guard countOccurrences(of: startMarker, in: text) == 1,
              countOccurrences(of: endMarker, in: text) == 1,
              let start = text.range(of: startMarker),
              let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex) else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the app-owned fnm block is missing or malformed")
        }

        let startsAtLineBoundary = start.lowerBound == text.startIndex
            || text[..<start.lowerBound].utf8.last == 0x0A
        // Inspect bytes because Swift treats CRLF as a single Character.
        let followingBytes = text[end.upperBound...].utf8
        let endsAtLineBoundary = followingBytes.isEmpty
            || followingBytes.first == 0x0A
            || followingBytes.starts(with: [0x0D, 0x0A])
        guard startsAtLineBoundary, endsAtLineBoundary else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the app-owned fnm block is missing or malformed")
        }

        let block = String(text[start.lowerBound..<end.upperBound])
        guard !text[start.upperBound...].contains(startMarker), !text[..<start.lowerBound].contains(endMarker) else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("managed fnm markers are duplicated or out of order")
        }
        return block
    }

    static func validateOwnedBlock(in text: String, expected: String) throws {
        guard let found = try? managedBlock(from: text) else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the app-owned fnm block is missing or malformed; it will not be rewritten")
        }
        guard found == expected else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the app-owned fnm block was changed; it will not be rewritten")
        }
        guard countOccurrences(of: found, in: text) == 1 else {
            throw ProvisioningShellConfiguration.ConfigurationError.conflict("the app-owned fnm block is duplicated; it will not be rewritten")
        }
    }

    static func containsAnyMarker(in text: String) -> Bool {
        text.contains(startMarker) || text.contains(endMarker)
    }

    /// Classifies only a small, standalone subset of fnm's documented shell
    /// initializer. This is intentionally not a shell parser: no command,
    /// substitution, profile, or sourced file is evaluated. The small amount
    /// of block tracking here prevents a valid top-level initializer from
    /// being hidden by an unrelated function later in the file.
    static func classifyExternalInitialization(_ text: String) -> ProvisioningShellConfiguration.ExternalInitializationClassification {
        var sawUnknown = false
        var sawRecognized = false
        var functionBraceDepth = 0
        var conditionalDepth = 0
        var pendingFunctionBody = false

        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let withoutComment = removingShellComment(from: line)
            guard !withoutComment.isEmpty else { continue }

            let functionDeclaration = isFunctionDeclarationLine(withoutComment)
            let startsFunctionBodyOnNextLine = pendingFunctionBody && withoutComment.first == "{"
            let insideFunction = functionBraceDepth > 0 || pendingFunctionBody
            let insideConditional = conditionalDepth > 0
            let hasControlWrapper = insideConditional || isShellWrapperLine(withoutComment)
            let initializerCandidates = knownInitializerCandidates(in: withoutComment)

            // A candidate embedded in a declaration or control statement is
            // deliberately unknown. A candidate on an ordinary top-level
            // command line is the only form that can be recognized.
            if !initializerCandidates.isEmpty {
                if insideFunction || insideConditional || functionDeclaration || hasControlWrapper {
                    sawUnknown = true
                } else {
                    sawRecognized = true
                }
            }

            // Ignore fnm-managed paths and prose. Only command-like fnm setup
            // (including source/indirection) is ambiguous and should prevent a
            // green result.
            let isStandaloneInitializer = initializerCandidates.count == 1 &&
                withoutComment.trimmingCharacters(in: .whitespaces) == initializerCandidates[0]
            if isAmbiguousFNMSetupLine(withoutComment),
               !isStandaloneInitializer || insideFunction || insideConditional || hasControlWrapper {
                sawUnknown = true
            }

            if functionDeclaration {
                if hasOpeningBrace(withoutComment) {
                    functionBraceDepth += braceDelta(in: withoutComment)
                } else {
                    pendingFunctionBody = true
                }
            } else if startsFunctionBodyOnNextLine {
                pendingFunctionBody = false
                functionBraceDepth += 1 + braceDelta(in: withoutComment, excludingFirstOpeningBrace: true)
            } else if functionBraceDepth > 0 {
                functionBraceDepth = max(0, functionBraceDepth + braceDelta(in: withoutComment))
            }

            conditionalDepth += conditionalOpenCount(in: withoutComment)
            conditionalDepth = max(0, conditionalDepth - conditionalCloseCount(in: withoutComment))
        }

        if sawUnknown { return .unknown }
        return sawRecognized ? .recognized : .none
    }

    private static func isShellWrapperLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let firstWord = shellWords(line)?.first?.lowercased()
        return lower.hasPrefix("if ") || lower.hasPrefix("if\t") ||
            lower.hasPrefix("for ") || lower.hasPrefix("for\t") ||
            lower.hasPrefix("while ") || lower.hasPrefix("while\t") ||
            lower.hasPrefix("case ") || lower.hasPrefix("case\t") ||
            lower.hasPrefix("function ") || isFunctionDeclarationLine(line) ||
            firstWord == "then" || firstWord == "fi" || firstWord == "done" || firstWord == "esac" ||
            containsShellToken("then", in: line) || containsShellToken("fi", in: line) ||
            containsShellToken("done", in: line) || containsShellToken("esac", in: line)
    }

    /// Recognizes only the declaration shape needed to keep a wrapped fnm
    /// initializer unverified. The declaration may put its opening brace on
    /// the next line; this is deliberately not a shell grammar.
    private static func isFunctionDeclarationLine(_ line: String) -> Bool {
        if line.lowercased().hasPrefix("function ") { return true }

        var index = line.startIndex
        func skipWhitespace() {
            while index < line.endIndex, line[index].isWhitespace {
                index = line.index(after: index)
            }
        }
        func isNameStart(_ character: Character) -> Bool {
            character == "_" || character.isLetter
        }
        func isNameCharacter(_ character: Character) -> Bool {
            isNameStart(character) || character.isNumber
        }

        skipWhitespace()
        guard index < line.endIndex, isNameStart(line[index]) else { return false }
        index = line.index(after: index)
        while index < line.endIndex, isNameCharacter(line[index]) {
            index = line.index(after: index)
        }
        skipWhitespace()
        guard index < line.endIndex, line[index] == "(" else { return false }
        index = line.index(after: index)
        skipWhitespace()
        guard index < line.endIndex, line[index] == ")" else { return false }
        index = line.index(after: index)
        skipWhitespace()
        guard index == line.endIndex || line[index] == "{" else { return false }
        return true
    }

    private static func knownInitializerCandidates(in line: String) -> [String] {
        let prefix = "eval \"$("
        let suffix = ")\""
        if line.hasPrefix(prefix), (line.hasSuffix(suffix) || line.hasSuffix(")")) {
            if isKnownExternalInitializer(line) { return [line] }
        }
        var candidates = [String]()
        var searchStart = line.startIndex
        while let start = line.range(of: prefix, range: searchStart..<line.endIndex) {
            let end = line.range(of: suffix, range: start.upperBound..<line.endIndex)
                ?? line.range(of: ")", range: start.upperBound..<line.endIndex)
            guard let end else { break }
            let candidate = String(line[start.lowerBound..<end.upperBound])
            if isKnownExternalInitializer(candidate) {
                candidates.append(candidate)
            }
            searchStart = end.upperBound
        }
        return candidates
    }

    private static func isAmbiguousFNMSetupLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.contains("fnm") else { return false }
        // An eval/source line is setup-shaped even when its executable is
        // indirect. Keep this conservative rather than treating every FNM_*
        // reference in an assignment or path as an invocation.
        if lower.hasPrefix("source ") || lower.hasPrefix("source\t") ||
            lower.hasPrefix(". ") || lower.hasPrefix(".\t") {
            return true
        }
        if lower.contains("eval ") {
            return true
        }
        if containsFNMVariableInExecutablePosition(in: line) {
            return true
        }

        for statement in line.split(separator: ";", omittingEmptySubsequences: true).map(String.init) {
            var words = shellWords(statement.trimmingCharacters(in: .whitespaces)) ?? []
            while words.first?.lowercased() == "then" {
                words.removeFirst()
            }
            guard let command = words.first?.lowercased() else { continue }
            let invokesFNM = command == "fnm" ||
                (command.hasSuffix("/fnm") && command.hasPrefix("/")) ||
                (command == "command" && words.dropFirst().first?.lowercased() == "fnm")
            guard invokesFNM else { continue }
            // `fnm env`, `fnm use`, and similar commands are setup. A path
            // containing `fnm` never becomes the command word here.
            return words.count > 1
        }
        return false
    }

    /// FNM_* expansions are ambiguous only when they can be the command being
    /// invoked. In particular, `${FNM_DIR:-...}` in `local`/`export` values
    /// and ordinary managed paths are data references, not fnm setup.
    private static func containsFNMVariableInExecutablePosition(in line: String) -> Bool {
        for statement in line.split(separator: ";", omittingEmptySubsequences: true).map(String.init) {
            var words = shellWords(statement.trimmingCharacters(in: .whitespaces)) ?? []
            while let first = words.first?.lowercased(),
                  ["if", "while", "until", "then", "!"].contains(first) {
                words.removeFirst()
            }
            while let first = words.first, isShellAssignmentWord(first) {
                words.removeFirst()
            }
            guard let command = words.first else { continue }
            if isFNMVariableExecutable(command) {
                return true
            }
            if command.lowercased() == "command",
               let executable = words.dropFirst().first,
               isFNMVariableExecutable(executable) {
                return true
            }
        }
        return false
    }

    private static func isShellAssignmentWord(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "=") else { return false }
        let name = word[..<equals]
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber } &&
            !name.first!.isNumber
    }

    private static func isFNMVariableExecutable(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard lower.first == "$" else { return false }
        if lower.hasPrefix("${") {
            guard let close = lower.firstIndex(of: "}") else { return false }
            let contents = lower[lower.index(after: lower.startIndex)..<close]
            let name = contents.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return name.contains("fnm")
        }
        var name = ""
        for character in lower.dropFirst() {
            guard character == "_" || character.isLetter || character.isNumber else { break }
            name.append(character)
        }
        return name.contains("fnm")
    }

    private static func removingShellComment(from line: String) -> String {
        var activeQuote: Character?
        for index in line.indices {
            let character = line[index]
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == "#" && (index == line.startIndex || line[line.index(before: index)].isWhitespace) {
                return String(line[..<index]).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }

    private static func containsShellToken(_ token: String, in line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: ";", with: " ")
        return (shellWords(normalized) ?? []).contains { $0.lowercased() == token }
    }

    private static func hasOpeningBrace(_ line: String) -> Bool {
        line.contains("{")
    }

    private static func braceDelta(in line: String, excludingFirstOpeningBrace: Bool = false) -> Int {
        var activeQuote: Character?
        var opens = 0
        var closes = 0
        var skippedOpening = !excludingFirstOpeningBrace
        for character in line {
            if let quote = activeQuote {
                if character == quote { activeQuote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                activeQuote = character
            } else if character == "{" {
                if skippedOpening { opens += 1 } else { skippedOpening = true }
            } else if character == "}" {
                closes += 1
            }
        }
        return opens - closes
    }

    private static func conditionalOpenCount(in line: String) -> Int {
        let lower = line.lowercased()
        return (lower.hasPrefix("if ") || lower.hasPrefix("if\t") ||
                lower.hasPrefix("for ") || lower.hasPrefix("for\t") ||
                lower.hasPrefix("while ") || lower.hasPrefix("while\t") ||
                lower.hasPrefix("case ") || lower.hasPrefix("case\t")) ? 1 : 0
    }

    private static func conditionalCloseCount(in line: String) -> Int {
        ["fi", "done", "esac"].reduce(into: 0) { count, token in
            if containsShellToken(token, in: line) { count += 1 }
        }
    }

    static func hasRecognizedFNMInitialization(in text: String) -> Bool {
        classifyExternalInitialization(text) == .recognized
    }

    private static func isKnownExternalInitializer(_ line: String) -> Bool {
        guard line.hasPrefix("eval \"$("), (line.hasSuffix(")\"") || line.hasSuffix(")")) else { return false }
        let bodyStart = line.index(line.startIndex, offsetBy: 8)
        let bodyEnd = line.index(line.endIndex, offsetBy: line.hasSuffix(")\"") ? -2 : -1)
        guard bodyStart < bodyEnd else { return false }
        let body = String(line[bodyStart..<bodyEnd])
        guard let words = shellWords(body), words.count >= 4,
              words[1] == "env" else { return false }
        let executable = words[0]
        guard executable == "fnm" || (executable.hasPrefix("/") && executable.hasSuffix("/fnm") && !executable.contains("$")) else {
            return false
        }

        var index = 2
        var hasShell = false
        while index < words.count {
            switch words[index] {
            case "--use-on-cd":
                index += 1
            case "--shell":
                guard index + 1 < words.count, words[index + 1] == "zsh", !hasShell else { return false }
                hasShell = true
                index += 2
            default:
                return false
            }
        }
        return hasShell
    }

    private static func shellWords(_ text: String) -> [String]? {
        var words = [String]()
        var word = ""
        var activeQuote: Character?
        var hasWord = false
        for character in text {
            if let quoted = activeQuote {
                if character == quoted {
                    activeQuote = nil
                } else {
                    word.append(character)
                }
                continue
            }
            if character == "'" || character == "\"" {
                activeQuote = character
                hasWord = true
            } else if character == "\\" {
                return nil
            } else if character.isWhitespace {
                if hasWord {
                    words.append(word)
                    word = ""
                    hasWord = false
                }
            } else {
                word.append(character)
                hasWord = true
            }
        }
        guard activeQuote == nil else { return nil }
        if hasWord { words.append(word) }
        return words
    }

    static func hasEquivalentFNMInitialization(in text: String) -> Bool {
        let nonCommentLines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }
        // Joining lines conservatively catches split references such as `f\\` / `nm`.
        let joined = nonCommentLines.joined()
        return joined.lowercased().contains("fnm")
    }
}
