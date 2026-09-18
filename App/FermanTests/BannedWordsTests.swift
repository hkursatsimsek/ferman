import Foundation
import Testing

/// CLAUDE.md rule 7's word ban, enforced against the actual literals the app shows a player — not
/// against `Localizable.xcstrings`, whose auto-extraction only happens inside Xcode's own indexing
/// build, never a headless `xcodebuild`/CI one, so the catalog can't be trusted as complete.
/// `AppSources.userVisibleStringLiterals(in:)` pulls every literal handed to `Text(`,
/// `String(localized:`, `Button(` or `Label(` across `App/Ferman`; this test scans all of them.
@Suite("Banned words")
struct BannedWordsTests {
    /// Stems checked as a *prefix* of each lowercased word, so a Turkish suffix (`derleme`,
    /// `programlamak`) still gets caught without also catching `çalışmadı` under `çalıştır` — see
    /// `allowsRealGameText` below, which covers exactly the case CLAUDE.md calls out by name.
    static let deniedStems = [
        "kod", "derle", "fonksiyon", "debug", "script", "algoritma", "programla", "çalıştır",
    ]
    /// Checked as an exact whole word: substrings would false-positive on ordinary Turkish words
    /// (`hafif` contains "if", `iftar` starts with it).
    static let deniedWholeWords = ["if", "else"]
    static let deniedPhrase = "kural motoru"

    @Test func noSourceStringContainsABannedWord() throws {
        let sources = try AppSources.load()
        var violations: [String] = []
        for file in sources {
            for literal in AppSources.userVisibleStringLiterals(in: file.contents) {
                if let denied = Self.deniedWord(in: literal) {
                    violations.append("\(file.relativePath): \"\(literal)\" contains \"\(denied)\"")
                }
            }
        }
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }

    @Test(
        arguments: [
            "kuralın kodu bozuk", "askerleri programla", "bu bir fonksiyon", "algoritma yanlış",
            "kuralı derle", "debug modu", "script çalıştı", "kural motoru devrede",
            "if düşman yakınsa", "else geri çekil", "emri çalıştır",
        ])
    func deniesKnownBadPhrases(phrase: String) {
        #expect(Self.deniedWord(in: phrase) != nil)
    }

    @Test(
        arguments: [
            "Bu emir hiç çalışmadı.", "düşman 3 kareden yakınsa", "Hazır emir setlerini gör",
            "Cephe Yarıldı", "hafif zırhlı süvari", "iftar vakti",
        ])
    func allowsRealGameText(phrase: String) {
        #expect(Self.deniedWord(in: phrase) == nil)
    }

    static func deniedWord(in text: String) -> String? {
        let lowered = text.lowercased(with: Locale(identifier: "tr"))
        if lowered.contains(Self.deniedPhrase) {
            return Self.deniedPhrase
        }
        for word in lowered.split(whereSeparator: { !$0.isLetter }) {
            let word = String(word)
            if Self.deniedWholeWords.contains(word) {
                return word
            }
            if let stem = Self.deniedStems.first(where: word.hasPrefix) {
                return stem
            }
        }
        return nil
    }
}

/// Reads `App/Ferman`'s own sources from disk (`#filePath`-relative, same technique as
/// `FermanCoreTests.CoreSources`) so this test always checks what's actually on disk, not a stale
/// build product.
enum AppSources {
    struct SourceFile: Sendable {
        let relativePath: String
        let contents: String
    }

    static var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Ferman", isDirectory: true)
    }

    static func load() throws -> [SourceFile] {
        let rootPath = appRoot.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [SourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let path = url.standardizedFileURL.path
            let relativePath = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count + 1)) : path
            files.append(SourceFile(relativePath: relativePath, contents: try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    // Computed, not a stored `static let`: `Regex` isn't `Sendable`, so a stored global would trip
    // strict concurrency's shared-mutable-state check. Recompiling this small pattern per call is
    // cheap next to the file I/O `load()` already does.
    private static var literalArgument: Regex<(Substring, Substring)> {
        #/(?:Text\(|String\(localized:\s*|Button\(\s*|Label\(\s*)"((?:[^"\\]|\\.)*)"/#
    }

    /// Every literal passed straight to `Text(`, `String(localized:`, `Button(` or `Label(` in
    /// `source`. Interpolated arguments (`Text(title)`) aren't literals and are invisible here — the
    /// literal that produced `title` gets scanned wherever it was actually written.
    static func userVisibleStringLiterals(in source: String) -> [String] {
        source.matches(of: Self.literalArgument).map { String($0.output.1) }
    }
}
