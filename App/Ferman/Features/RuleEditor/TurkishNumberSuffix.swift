/// Genitive and ablative suffixes for a number written as a digit string (D21 — Foundation's
/// Automatic Grammar Agreement doesn't cover Turkish). Suffix choice depends on how the number is
/// *spoken*, not how it's written: "%35'in" (otuz beş → beş → front, unrounded), "%40'ın" (kırk →
/// back, unrounded). For 0–100 that spoken form is fully determined by the last digit (or the tens
/// word for a round ten, or "yüz" for 100) — no full number-to-words conversion is needed.
nonisolated enum TurkishNumberSuffix {
    private enum Vowel {
        case frontUnrounded, frontRounded, backUnrounded, backRounded
    }

    private struct Terminal {
        let vowel: Vowel
        let endsInVowel: Bool
        let endsInVoicelessConsonant: Bool
    }

    // sıfır, bir, iki, üç, dört, beş, altı, yedi, sekiz, dokuz
    private static let units: [Terminal] = [
        Terminal(vowel: .backUnrounded, endsInVowel: false, endsInVoicelessConsonant: false),
        Terminal(vowel: .frontUnrounded, endsInVowel: false, endsInVoicelessConsonant: false),
        Terminal(vowel: .frontUnrounded, endsInVowel: true, endsInVoicelessConsonant: false),
        Terminal(vowel: .frontRounded, endsInVowel: false, endsInVoicelessConsonant: true),
        Terminal(vowel: .frontRounded, endsInVowel: false, endsInVoicelessConsonant: true),
        Terminal(vowel: .frontUnrounded, endsInVowel: false, endsInVoicelessConsonant: true),
        Terminal(vowel: .backUnrounded, endsInVowel: true, endsInVoicelessConsonant: false),
        Terminal(vowel: .frontUnrounded, endsInVowel: true, endsInVoicelessConsonant: false),
        Terminal(vowel: .frontUnrounded, endsInVowel: false, endsInVoicelessConsonant: false),
        Terminal(vowel: .backRounded, endsInVowel: false, endsInVoicelessConsonant: false),
    ]

    // on, yirmi, otuz, kırk, elli, altmış, yetmiş, seksen, doksan
    private static let tens: [Int: Terminal] = [
        10: Terminal(vowel: .backRounded, endsInVowel: false, endsInVoicelessConsonant: false),
        20: Terminal(vowel: .frontUnrounded, endsInVowel: true, endsInVoicelessConsonant: false),
        30: Terminal(vowel: .backRounded, endsInVowel: false, endsInVoicelessConsonant: false),
        40: Terminal(vowel: .backUnrounded, endsInVowel: false, endsInVoicelessConsonant: true),
        50: Terminal(vowel: .frontUnrounded, endsInVowel: true, endsInVoicelessConsonant: false),
        60: Terminal(vowel: .backUnrounded, endsInVowel: false, endsInVoicelessConsonant: true),
        70: Terminal(vowel: .frontUnrounded, endsInVowel: false, endsInVoicelessConsonant: true),
        80: Terminal(vowel: .frontUnrounded, endsInVowel: false, endsInVoicelessConsonant: false),
        90: Terminal(vowel: .backUnrounded, endsInVowel: false, endsInVoicelessConsonant: false),
    ]

    // yüz
    private static let hundred = Terminal(vowel: .frontRounded, endsInVowel: false, endsInVoicelessConsonant: false)

    private static func terminal(for n: Int) -> Terminal {
        precondition((0...100).contains(n), "TurkishNumberSuffix only covers 0...100")
        if n == 0 { return units[0] }
        if n == 100 { return hundred }
        let remainder = n % 10
        if remainder == 0 {
            return tens[n] ?? units[0]
        }
        return units[remainder]
    }

    /// "35" → "35'in", "40" → "40'ın", "2" → "2'nin" (a vowel-final word needs a buffer "n").
    static func genitive(_ n: Int) -> String {
        let terminal = terminal(for: n)
        let buffer = terminal.endsInVowel ? "n" : ""
        let vowel =
            switch terminal.vowel {
            case .frontUnrounded: "i"
            case .frontRounded: "ü"
            case .backUnrounded: "ı"
            case .backRounded: "u"
            }
        return "\(n)'\(buffer)\(vowel)n"
    }

    /// "5" → "5'ten" (beş ends voiceless, devoices d→t), "8" → "8'den" (sekiz ends voiced).
    static func ablative(_ n: Int) -> String {
        let terminal = terminal(for: n)
        let consonant = terminal.endsInVoicelessConsonant ? "t" : "d"
        let vowel =
            switch terminal.vowel {
            case .frontUnrounded, .frontRounded: "e"
            case .backUnrounded, .backRounded: "a"
            }
        return "\(n)'\(consonant)\(vowel)n"
    }

    /// The 3rd-person possessive used for "N percent of it/them" (design brief §4.6 — "%70'i"):
    /// "70" → "70'i", "2" → "2'si" (a vowel-final word needs a buffer "s", not genitive's "n").
    static func possessive(_ n: Int) -> String {
        let terminal = terminal(for: n)
        let buffer = terminal.endsInVowel ? "s" : ""
        let vowel =
            switch terminal.vowel {
            case .frontUnrounded: "i"
            case .frontRounded: "ü"
            case .backUnrounded: "ı"
            case .backRounded: "u"
            }
        return "\(n)'\(buffer)\(vowel)"
    }
}
