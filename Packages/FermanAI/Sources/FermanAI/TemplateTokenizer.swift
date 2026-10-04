/// One word of a typed order after folding ("Düşman'a" → "dusmana"), with its value when it spells
/// a number: "3'ten", "üçten", "kırk beş", "forty-five".
struct TemplateToken: Sendable, Equatable {
    var word: String
    var number: Int?
    /// "bir" doubles as the indefinite article ("bir düşman yaklaşırsa"); it only counts as a number
    /// when nothing else in the fragment does.
    var isWeakNumber = false
    var isTens = false
    var isSingleDigit = false

    init(word: String, number: Int? = nil) {
        self.word = word
        self.number = number
    }
}

/// Splits a typed order into fragments of folded tokens. Fragments end at sentence punctuation,
/// commas and the connectors "ve" / "and" / "ama" / "but"; `TemplateCompiler` pairs a condition
/// fragment with the action fragment next to it.
enum TemplateTokenizer {
    static func fragments(of text: String) -> [[TemplateToken]] {
        var fragments: [[TemplateToken]] = []
        var current: [TemplateToken] = []
        var word = ""

        func endWord() {
            guard !word.isEmpty else {
                return
            }
            if connectors.contains(word) {
                endFragment()
            } else if fragmentOpeners.contains(word) {
                // "…then retreat else advance": the default order starts a fragment of its own.
                endFragment()
                current.append(TemplateToken(word: word))
            } else {
                current.append(contentsOf: tokens(for: word))
            }
            word = ""
        }

        func endFragment() {
            if !current.isEmpty {
                fragments.append(resolvingNumbers(in: current))
            }
            current = []
        }

        let characters = Array(fold(text))
        for (index, character) in characters.enumerated() {
            if character.isLetter || isDigit(character) {
                word.append(character)
                continue
            }
            switch character {
            case "'":
                // "3'ten", "Okçu'lara": the suffix stays glued to its word.
                continue
            case "%":
                endWord()
                current.append(TemplateToken(word: "%"))
            case "." where isOrdinal(word, dotAt: index, in: characters):
                // "10. saniyeden sonra": an ordinal, not the end of a sentence.
                endWord()
            case ".", ";", ",", ":", "!", "?", "\n", "\r":
                endWord()
                endFragment()
            default:
                endWord()
            }
        }
        endWord()
        endFragment()
        return fragments
    }

    /// Lowercases and strips Turkish and other diacritics so that "ÇEKİL", "çekil" and a
    /// keyboard-less "cekil" all read the same. The dotted and dotless i fold together, which
    /// also sidesteps the locale-dependent "I" → "ı" lowercasing.
    static func fold(_ text: String) -> String {
        var folded = ""
        folded.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "ç", "Ç": folded.append("c")
            case "ğ", "Ğ": folded.append("g")
            case "ı", "I", "İ", "î", "Î": folded.append("i")
            case "ö", "Ö": folded.append("o")
            case "ş", "Ş": folded.append("s")
            case "ü", "Ü", "û", "Û": folded.append("u")
            case "â", "Â": folded.append("a")
            case "’", "‘", "`", "´": folded.append("'")
            case "\u{0300}"..."\u{036F}":
                // Combining marks of decomposed input ("u" + U+0308): the base letter is enough.
                continue
            default: folded.append(contentsOf: String(scalar).lowercased())
            }
        }
        return folded
    }

    private static let connectors: Set<String> = ["ve", "and", "ama", "but"]
    /// "başka durumda", "aksi halde" too: dictation (F2.5) drops the comma before them.
    private static let fragmentOpeners: Set<String> = ["else", "otherwise", "yoksa", "baska", "aksi"]

    private static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    private static func isOrdinal(_ word: String, dotAt index: Int, in characters: [Character]) -> Bool {
        guard !word.isEmpty, word.allSatisfy(isDigit) else {
            return false
        }
        let rest = characters[(index + 1)...]
        guard let next = rest.first(where: { $0 != " " && $0 != "\t" }) else {
            return false
        }
        return next.isLetter
    }

    private static func tokens(for word: String) -> [TemplateToken] {
        if let first = word.first, isDigit(first) {
            let digits = word.prefix(while: isDigit)
            let rest = String(word.dropFirst(digits.count))
            guard let value = Int(digits) else {
                return [TemplateToken(word: word)]
            }
            if rest.isEmpty || numberSuffixes.contains(rest) {
                return [TemplateToken(word: word, number: value)]
            }
            // "10sn", "3cells": the number and the measure it is glued to.
            return [TemplateToken(word: String(digits), number: value), TemplateToken(word: rest)]
        }
        return [spelledNumber(word) ?? TemplateToken(word: word)]
    }

    private struct SpelledNumber {
        let word: String
        let value: Int
        let isTens: Bool
        /// Turkish stems that only appear with a suffix: "dörd-üncü".
        let requiresSuffix: Bool
    }

    /// Longest first, so "altmış" is not read as "altı" + "mış" and "one" not as "on" + "e".
    private static let spelledNumbers: [SpelledNumber] = {
        var entries: [SpelledNumber] = []
        func add(_ word: String, _ value: Int, tens: Bool = false, requiresSuffix: Bool = false) {
            entries.append(SpelledNumber(word: word, value: value, isTens: tens, requiresSuffix: requiresSuffix))
        }
        for (word, value) in [
            ("bir", 1), ("iki", 2), ("uc", 3), ("dort", 4), ("bes", 5), ("alti", 6), ("yedi", 7), ("sekiz", 8),
            ("dokuz", 9), ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6), ("seven", 7),
            ("eight", 8), ("nine", 9),
        ] {
            add(word, value)
        }
        add("dord", 4, requiresSuffix: true)
        for (word, value) in [
            ("on", 10), ("yirmi", 20), ("otuz", 30), ("kirk", 40), ("elli", 50), ("altmis", 60), ("yetmis", 70),
            ("seksen", 80), ("doksan", 90), ("ten", 10), ("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50),
            ("sixty", 60), ("seventy", 70), ("eighty", 80), ("ninety", 90),
        ] {
            add(word, value, tens: true)
        }
        for (word, value) in [
            ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14), ("fifteen", 15), ("sixteen", 16),
            ("seventeen", 17), ("eighteen", 18), ("nineteen", 19), ("yuz", 100), ("hundred", 100), ("yari", 50),
            ("half", 50), ("ceyrek", 25), ("quarter", 25),
        ] {
            add(word, value)
        }
        return entries.sorted { $0.word.count > $1.word.count }
    }()

    /// Case and ordinal endings a Turkish number can carry, after the apostrophe is dropped and
    /// letters folded: "3'ten" → "3ten", "40'ın" → "40in", "üçüncü" → "uc" + "uncu".
    /// Deliberately missing "nda"/"nde", so "altında" ("below") is not read as "altı" + "nda".
    private static let numberSuffixes: Set<String> = [
        "", "a", "e", "ya", "ye", "i", "u", "yi", "yu", "in", "un", "nin", "nun", "da", "de", "ta", "te", "dan", "den",
        "tan", "ten", "inci", "nci", "uncu", "ncu", "si", "sina", "sinin", "sindan", "sini",
    ]

    private static func spelledNumber(_ word: String) -> TemplateToken? {
        // "yüzde kırk" is "forty percent", not "at a hundred".
        guard word != "yuzde" else {
            return nil
        }
        for entry in spelledNumbers where word.hasPrefix(entry.word) {
            let suffix = String(word.dropFirst(entry.word.count))
            guard numberSuffixes.contains(suffix), !(entry.requiresSuffix && suffix.isEmpty) else {
                continue
            }
            var token = TemplateToken(word: word, number: entry.value)
            token.isTens = entry.isTens && suffix.isEmpty
            token.isSingleDigit = (1...9).contains(entry.value) && entry.word != "yari"
            token.isWeakNumber = entry.word == "bir"
            return token
        }
        return nil
    }

    /// Turkish "on" is ten; English "on" is a preposition ("focus fire on archers"). A bare "on"
    /// only counts when a unit word or measure follows it ("on beş", "on saniye") or a percent
    /// sign precedes it. Then "kırk beş" / "forty-five" merge into one number.
    private static func resolvingNumbers(in tokens: [TemplateToken]) -> [TemplateToken] {
        var resolved = tokens
        for index in resolved.indices where resolved[index].word == "on" {
            let next = index + 1 < resolved.count ? resolved[index + 1] : nil
            let previous = index > 0 ? resolved[index - 1] : nil
            let isNumber =
                next?.isSingleDigit == true
                || next.map { TemplateLexicon.isMeasure($0.word) } == true
                || previous.map { TemplateLexicon.isPercentMarker($0.word) } == true
            if !isNumber {
                resolved[index] = TemplateToken(word: "on")
            }
        }

        var merged: [TemplateToken] = []
        for token in resolved {
            if token.isSingleDigit, let last = merged.last, last.isTens, let tens = last.number,
                let unit = token.number
            {
                merged[merged.count - 1] = TemplateToken(word: token.word, number: tens + unit)
            } else {
                merged.append(token)
            }
        }
        return merged
    }
}
