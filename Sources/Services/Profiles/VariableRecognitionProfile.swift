import Foundation

/// IDE-aware post-process. Takes whatever the standard cleanup produced
/// and applies code-style transforms:
///   - "snake case user name" → `user_name`
///   - "camel case fetch user" → `fetchUser`
///   - "kebab case my component" → `my-component`
///   - "screaming snake api key" → `API_KEY`
///   - "pascal case auth service" → `AuthService`
///   - filename heuristics: "open file index dot tsx" → `index.tsx`
///
/// **Architecture**: this profile WRAPS another profile (the "inner" one
/// is StandardCleanupProfile by default). Standard runs first, then we
/// apply variable-naming transforms on the result. That keeps the LLM-side
/// English-cleanup logic untouched while adding code-style polish on top.
///
/// **Strategy**: regex-first, LLM fallback (Phase 3+). Regex catches the
/// 80% case (well-spoken "snake case foo bar") deterministically, with
/// zero added latency. The LLM fallback runs only when an unmatched
/// "(snake|camel|kebab) case …" pattern survives — caught on partial
/// matches Whisper mangled.
final class VariableRecognitionProfile: TransformerProfile {
    let kind: ProfileKind = .variableRecognition
    let displayLabel = ProfileKind.variableRecognition.displayLabel

    private let inner: TransformerProfile
    private let llm: LLMService
    private let llmFallbackEnabled: Bool

    init(
        inner: TransformerProfile,
        llm: LLMService = .shared,
        llmFallbackEnabled: Bool = false
    ) {
        self.inner = inner
        self.llm = llm
        self.llmFallbackEnabled = llmFallbackEnabled
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        inner.transform(input) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                completion(.failure(err))

            case .success(let innerOutput):
                let (transformed, transforms) = Self.applyVariableTransforms(innerOutput.finalText)
                let (withFiles, fileTags) = Self.applyFilenameTagging(
                    transformed,
                    surface: input.context.surface
                )

                if transforms.isEmpty && fileTags.isEmpty {
                    // Nothing matched — return inner result unchanged but
                    // re-tag the profile so the run-log row tells the user
                    // we tried (helps when debugging "why didn't it convert?").
                    var trace = innerOutput.trace
                    trace.append("Variable recognition: no patterns matched")
                    let output = TransformerOutput(
                        finalText: withFiles,
                        summary: innerOutput.summary,
                        modelUsed: innerOutput.modelUsed,
                        costUSD: innerOutput.costUSD,
                        llmLatencyMs: innerOutput.llmLatencyMs,
                        usedAgentic: innerOutput.usedAgentic,
                        trace: trace
                    )
                    completion(.success(output))
                    return
                }

                var trace = innerOutput.trace
                trace.append("Variable recognition applied:")
                trace.append(contentsOf: transforms.map { "  - \($0)" })
                if !fileTags.isEmpty {
                    trace.append("File tags: \(fileTags.joined(separator: ", "))")
                }

                let output = TransformerOutput(
                    finalText: withFiles,
                    summary: "\(innerOutput.summary) + var-recog",
                    modelUsed: innerOutput.modelUsed,
                    costUSD: innerOutput.costUSD,
                    llmLatencyMs: innerOutput.llmLatencyMs,
                    usedAgentic: innerOutput.usedAgentic,
                    trace: trace
                )
                completion(.success(output))
            }
        }
    }

    // MARK: - Pure regex transforms

    /// Run all pattern-based variable-name conversions. Returns the
    /// transformed text plus a list of human-readable descriptions
    /// for the run-log trace.
    static func applyVariableTransforms(_ input: String) -> (String, [String]) {
        var text = input
        var transforms: [String] = []

        // Order matters: match LONGER prefixes first ("screaming snake"
        // before "snake") so we don't mis-classify them.
        //
        // Capture group: 1 starting word + 0–4 more space-separated words.
        // The 5-word ceiling is a heuristic — variable names dictated as
        // "user account profile picture URL" would be the longest sane case.
        // Past 5 we're probably eating sentence content.
        let wordsPart = #"([a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z][a-zA-Z0-9]*){0,4})"#
        let casePatterns: [(label: String, regex: String, transform: (String) -> String)] = [
            ("screaming snake case", #"(?i)\bscreaming snake case \#(wordsPart)\b"#, { $0.toScreamingSnakeCase() }),
            ("pascal case",           #"(?i)\bpascal case \#(wordsPart)\b"#,         { $0.toPascalCase() }),
            ("camel case",            #"(?i)\bcamel case \#(wordsPart)\b"#,          { $0.toCamelCase() }),
            ("snake case",            #"(?i)\bsnake case \#(wordsPart)\b"#,          { $0.toSnakeCase() }),
            ("kebab case",            #"(?i)\bkebab case \#(wordsPart)\b"#,          { $0.toKebabCase() }),
        ]

        for pattern in casePatterns {
            let result = applyTransform(
                text: text,
                pattern: pattern.regex,
                label: pattern.label,
                transform: pattern.transform
            )
            text = result.transformed
            transforms.append(contentsOf: result.descriptions)
        }

        return (text, transforms)
    }

    private static func applyTransform(
        text: String,
        pattern: String,
        label: String,
        transform: (String) -> String
    ) -> (transformed: String, descriptions: [String]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, [])
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return (text, []) }

        // Walk matches from the back so replacement-induced index shifts
        // don't invalidate earlier matches.
        var working = nsText.copy() as! NSString
        var descriptions: [String] = []
        for match in matches.reversed() where match.numberOfRanges > 1 {
            let captureRange = match.range(at: 1)
            let original = working.substring(with: captureRange)
            let converted = transform(original)
            working = working.replacingCharacters(in: match.range, with: converted) as NSString
            descriptions.append("\(label) \"\(original)\" → \(converted)")
        }
        return (working as String, descriptions)
    }

    // MARK: - Filename tagging

    /// In IDE chat surfaces (Cursor, Windsurf, Claude desktop), filenames
    /// dictated mid-prompt should be wrapped in backticks so the IDE's
    /// chat treats them as file references.
    ///
    /// Strict allowlist of extensions to avoid false positives like
    /// "version 1.2 release".
    private static let fileExtAllowlist: Set<String> = [
        "ts", "tsx", "js", "jsx", "mjs", "cjs",
        "py", "rb", "go", "rs", "swift", "kt", "java", "scala",
        "c", "h", "cpp", "hpp", "cc", "m", "mm",
        "html", "css", "scss", "less", "vue", "svelte",
        "json", "yaml", "yml", "toml", "xml",
        "md", "mdx", "txt",
        "sh", "bash", "zsh", "fish",
        "sql", "graphql", "proto",
        "swiftui", "storyboard", "xib"
    ]

    /// Matches "<word>.<ext>" where <ext> is in the allowlist.
    /// Doesn't tag if already inside backticks (well, mostly — see notes).
    private static let filenameRegex: NSRegularExpression = {
        let extensions = fileExtAllowlist.sorted().joined(separator: "|")
        let pattern = #"\b([A-Za-z_][\w-]*)\.(\#(extensions))\b"#
        // Ignore-case so "Index.TSX" still matches.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func applyFilenameTagging(
        _ input: String,
        surface: AppSurface
    ) -> (String, [String]) {
        // Only IDE surfaces benefit from this — chat/notes don't render
        // backtick-wrapped strings as file refs.
        guard surface == .ide else { return (input, []) }

        let nsInput = input as NSString
        let matches = filenameRegex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
        guard !matches.isEmpty else { return (input, []) }

        var working = nsInput.copy() as! NSString
        var tags: [String] = []
        for match in matches.reversed() {
            let r = match.range
            let original = working.substring(with: r)
            // Skip if the surrounding chars are already backticks — quick check.
            let before = r.location > 0 ? working.substring(with: NSRange(location: r.location - 1, length: 1)) : ""
            let after = (r.location + r.length) < working.length
                ? working.substring(with: NSRange(location: r.location + r.length, length: 1))
                : ""
            if before == "`" || after == "`" { continue }

            let wrapped = "`\(original)`"
            working = working.replacingCharacters(in: r, with: wrapped) as NSString
            tags.append(original)
        }
        return (working as String, tags)
    }
}

// MARK: - String case helpers

private extension String {
    /// "user name" → ["user", "name"]; survives extra whitespace.
    var caseTokens: [String] {
        self
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    func toSnakeCase() -> String {
        caseTokens.joined(separator: "_")
    }

    func toScreamingSnakeCase() -> String {
        caseTokens.map { $0.uppercased() }.joined(separator: "_")
    }

    func toKebabCase() -> String {
        caseTokens.joined(separator: "-")
    }

    func toCamelCase() -> String {
        let tokens = caseTokens
        guard let first = tokens.first else { return "" }
        let rest = tokens.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    func toPascalCase() -> String {
        caseTokens.map { $0.capitalized }.joined()
    }
}
