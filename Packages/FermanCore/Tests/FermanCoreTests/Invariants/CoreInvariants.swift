import Foundation

struct InvariantViolation: Hashable, Sendable, CustomStringConvertible {
    let file: String
    let line: Int
    let message: String

    var description: String { "\(file):\(line): \(message)" }
}

/// The determinism contract of CLAUDE.md rules 1–2 and D2, expressed as token rules over FermanCore sources.
enum CoreInvariants {
    static let allowedImports: Set<String> = ["Foundation"]

    private static let floatingPoint = "floating point is banned in FermanCore; use Fixed (D2)"
    private static let clock = "clocks are banned in FermanCore; use the tick counter"
    private static let randomness = "system randomness is banned in FermanCore; use DeterministicRNG"
    private static let hashing = "hash values are seeded per process; order by explicit keys"
    private static let identity = "UUID is banned in FermanCore; use a deterministic ID counter"
    private static let concurrency = "concurrency is banned inside the simulation; a run is single-threaded"
    private static let referenceType = "reference types are banned in FermanCore; use struct or enum"
    private static let unsafeCode = "unsafe code is banned in FermanCore; use Span, MutableSpan or InlineArray"
    private static let transcendental = "platform math is banned in FermanCore; use FixedMath tables and isqrt"

    static let bannedIdentifiers: [String: String] = {
        var rules: [String: String] = [:]
        for name in [
            "Float", "Double", "Float16", "Float32", "Float64", "Float80", "CGFloat", "Decimal", "NSDecimalNumber",
            "NSNumber", "FloatingPoint", "BinaryFloatingPoint",
        ] {
            rules[name] = floatingPoint
        }
        for name in [
            "Date", "NSDate", "DispatchTime", "DispatchWallTime", "ContinuousClock", "SuspendingClock",
            "CFAbsoluteTimeGetCurrent", "clock_gettime", "mach_absolute_time", "ProcessInfo",
        ] {
            rules[name] = clock
        }
        for name in [
            "SystemRandomNumberGenerator", "RandomNumberGenerator", "arc4random", "arc4random_uniform", "drand48",
            "random", "randomElement", "shuffle", "shuffled",
        ] {
            rules[name] = randomness
        }
        for name in ["Hasher", "hashValue"] {
            rules[name] = hashing
        }
        for name in ["UUID", "NSUUID"] {
            rules[name] = identity
        }
        for name in [
            "Task", "TaskGroup", "ThrowingTaskGroup", "DiscardingTaskGroup", "ThrowingDiscardingTaskGroup",
            "withTaskGroup", "withThrowingTaskGroup", "withDiscardingTaskGroup", "withThrowingDiscardingTaskGroup",
            "async", "await", "actor", "Thread", "DispatchQueue", "DispatchGroup", "OperationQueue", "Mutex",
            "Atomic",
        ] {
            rules[name] = concurrency
        }
        rules["class"] = referenceType
        rules["unsafe"] = unsafeCode
        return rules
    }()

    static let bannedIdentifierPrefixes: [(prefix: String, message: String)] = [
        ("SIMD", "SIMD is banned in FermanCore; use FixedVector2 (D2)"),
        ("simd", "SIMD is banned in FermanCore; use FixedVector2 (D2)"),
        ("Unsafe", unsafeCode),
    ]

    static let bannedFreeFunctions: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh", "sqrt", "cbrt", "pow", "exp",
        "exp2", "log", "log2", "log10", "hypot", "fmod", "remainder", "floor", "ceil", "round", "trunc",
    ]

    static let bannedAttributes: [String: String] = [
        "unchecked": "@unchecked Sendable is banned; make the type a Sendable value instead"
    ]

    private static let importKinds: Set<String> = [
        "typealias", "struct", "class", "enum", "protocol", "let", "var", "func",
    ]

    static func violations(in source: String, file: String) -> [InvariantViolation] {
        let tokens = SwiftLexer.tokens(in: source)
        var violations: [InvariantViolation] = []

        func report(_ token: SourceToken, _ message: String) {
            violations.append(InvariantViolation(file: file, line: token.line, message: message))
        }

        for (index, token) in tokens.enumerated() {
            let previous = index > 0 ? tokens[index - 1] : nil
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil

            switch token.kind {
            case .attribute:
                if let message = bannedAttributes[token.text] {
                    report(token, message)
                }
            case .identifier:
                if token.text == "import", previous?.text != "." {
                    var moduleIndex = index + 1
                    if moduleIndex < tokens.count, importKinds.contains(tokens[moduleIndex].text) {
                        moduleIndex += 1
                    }
                    if moduleIndex < tokens.count, !allowedImports.contains(tokens[moduleIndex].text) {
                        report(
                            token, "import \(tokens[moduleIndex].text) is banned; FermanCore imports only Foundation")
                    }
                }
                if let message = bannedIdentifiers[token.text] {
                    report(token, message)
                }
                if let rule = bannedIdentifierPrefixes.first(where: { token.text.hasPrefix($0.prefix) }) {
                    report(token, rule.message)
                }
                let isCall = next?.text == "("
                let isMemberOrDeclaration = previous?.text == "." || previous?.text == "func"
                if isCall, !isMemberOrDeclaration, bannedFreeFunctions.contains(token.text) {
                    report(token, transcendental)
                }
            case .escapedIdentifier, .number, .punctuation:
                break
            }
        }
        return violations
    }
}

struct SourceFile: Sendable {
    let relativePath: String
    let contents: String
}

enum CoreSources {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func load() throws -> [SourceFile] {
        let sourcesRoot = packageRoot.appendingPathComponent("Sources/FermanCore", isDirectory: true)
        let rootPath = sourcesRoot.standardizedFileURL.path
        guard
            let enumerator = FileManager.default.enumerator(
                at: sourcesRoot,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }
        var files: [SourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let path = url.standardizedFileURL.path
            let relativePath = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count + 1)) : path
            files.append(SourceFile(relativePath: relativePath, contents: try String(contentsOf: url, encoding: .utf8)))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
}
