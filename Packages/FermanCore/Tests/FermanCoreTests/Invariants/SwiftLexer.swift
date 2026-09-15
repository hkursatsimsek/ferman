struct SourceToken: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case identifier
        case escapedIdentifier
        case attribute
        case number
        case punctuation
    }

    let kind: Kind
    let text: String
    let line: Int
}

/// Tokenizes Swift source well enough for invariant scanning.
///
/// Comments and string literal contents are dropped so that prose such as "no Float here" never trips a rule,
/// while code inside string interpolations is still tokenized because it executes.
struct SwiftLexer {
    private let scalars: [Unicode.Scalar]
    private var position = 0
    private var line = 1
    private var tokens: [SourceToken] = []

    static func tokens(in source: String) -> [SourceToken] {
        var lexer = SwiftLexer(scalars: Array(source.unicodeScalars))
        lexer.lexCode(stopsAtUnbalancedClosingParenthesis: false)
        return lexer.tokens
    }

    private init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private func scalar(at offset: Int) -> Unicode.Scalar? {
        let index = position + offset
        return index < scalars.count ? scalars[index] : nil
    }

    private mutating func advance(by count: Int = 1) {
        for _ in 0..<count where position < scalars.count {
            if scalars[position] == "\n" {
                line += 1
            }
            position += 1
        }
    }

    private mutating func append(_ kind: SourceToken.Kind, _ text: String, line tokenLine: Int) {
        tokens.append(SourceToken(kind: kind, text: text, line: tokenLine))
    }

    private mutating func lexCode(stopsAtUnbalancedClosingParenthesis: Bool) {
        var parenthesisDepth = 0
        while let current = scalar(at: 0) {
            switch current {
            case "/" where scalar(at: 1) == "/":
                skipLineComment()
            case "/" where scalar(at: 1) == "*":
                skipBlockComment()
            case "\"":
                lexStringLiteral(hashCount: 0)
            case "#":
                if let hashCount = rawStringHashCount() {
                    lexStringLiteral(hashCount: hashCount)
                } else {
                    append(.punctuation, "#", line: line)
                    advance()
                }
            case "`":
                lexEscapedIdentifier()
            case "@":
                let tokenLine = line
                advance()
                append(.attribute, readIdentifier(), line: tokenLine)
            case "(":
                parenthesisDepth += 1
                append(.punctuation, "(", line: line)
                advance()
            case ")":
                if stopsAtUnbalancedClosingParenthesis && parenthesisDepth == 0 {
                    advance()
                    return
                }
                parenthesisDepth -= 1
                append(.punctuation, ")", line: line)
                advance()
            default:
                if Self.isIdentifierHead(current) {
                    let tokenLine = line
                    append(.identifier, readIdentifier(), line: tokenLine)
                } else if Self.isDigit(current) {
                    lexNumber()
                } else if current.properties.isWhitespace {
                    advance()
                } else {
                    append(.punctuation, String(current), line: line)
                    advance()
                }
            }
        }
    }

    private mutating func skipLineComment() {
        while let current = scalar(at: 0), current != "\n" {
            advance()
        }
    }

    private mutating func skipBlockComment() {
        var depth = 0
        while scalar(at: 0) != nil {
            if scalar(at: 0) == "/" && scalar(at: 1) == "*" {
                depth += 1
                advance(by: 2)
            } else if scalar(at: 0) == "*" && scalar(at: 1) == "/" {
                depth -= 1
                advance(by: 2)
                if depth == 0 {
                    return
                }
            } else {
                advance()
            }
        }
    }

    private func rawStringHashCount() -> Int? {
        var count = 0
        while scalar(at: count) == "#" {
            count += 1
        }
        return scalar(at: count) == "\"" ? count : nil
    }

    private func matchesHashes(from offset: Int, count: Int) -> Bool {
        (0..<count).allSatisfy { scalar(at: offset + $0) == "#" }
    }

    private mutating func lexStringLiteral(hashCount: Int) {
        advance(by: hashCount)
        let isMultiline = scalar(at: 0) == "\"" && scalar(at: 1) == "\"" && scalar(at: 2) == "\""
        let quoteCount = isMultiline ? 3 : 1
        advance(by: quoteCount)

        while let current = scalar(at: 0) {
            if current == "\\" && matchesHashes(from: 1, count: hashCount) {
                advance(by: 1 + hashCount)
                if scalar(at: 0) == "(" {
                    advance()
                    lexCode(stopsAtUnbalancedClosingParenthesis: true)
                } else {
                    advance()
                }
                continue
            }
            if current == "\"" {
                let closesQuotes = (0..<quoteCount).allSatisfy { scalar(at: $0) == "\"" }
                if closesQuotes && matchesHashes(from: quoteCount, count: hashCount) {
                    advance(by: quoteCount + hashCount)
                    return
                }
            }
            advance()
        }
    }

    private mutating func lexEscapedIdentifier() {
        let tokenLine = line
        advance()
        var text = ""
        while let current = scalar(at: 0), current != "`", current != "\n" {
            text.unicodeScalars.append(current)
            advance()
        }
        advance()
        append(.escapedIdentifier, text, line: tokenLine)
    }

    private mutating func readIdentifier() -> String {
        var text = ""
        while let current = scalar(at: 0), Self.isIdentifierBody(current) {
            text.unicodeScalars.append(current)
            advance()
        }
        return text
    }

    private mutating func lexNumber() {
        let tokenLine = line
        var text = ""
        while let current = scalar(at: 0) {
            let continuesFraction = current == "." && scalar(at: 1).map(Self.isDigit) == true
            guard Self.isIdentifierBody(current) || continuesFraction else {
                break
            }
            text.unicodeScalars.append(current)
            advance()
        }
        append(.number, text, line: tokenLine)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func isIdentifierHead(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "$" || scalar.properties.isAlphabetic
    }

    private static func isIdentifierBody(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierHead(scalar) || isDigit(scalar)
    }
}
