import FermanCore

/// A run of folded words to look for in a fragment. A trailing `*` makes a word a stem
/// ("cekil*" matches "çekil", "çekilsin", "çekilin").
struct TemplatePhrase: Sendable, ExpressibleByStringLiteral {
    struct Word: Sendable {
        let text: String
        let isStem: Bool

        func matches(_ word: String, rejectingConditionalForms: Bool) -> Bool {
            guard isStem else {
                return word == text
            }
            guard word.hasPrefix(text) else {
                return false
            }
            return !rejectingConditionalForms
                || !TemplateLexicon.isConditionalEnding(String(word.dropFirst(text.count)))
        }
    }

    let words: [Word]

    init(stringLiteral pattern: String) {
        words = pattern.split(separator: " ").map { part in
            part.hasSuffix("*")
                ? Word(text: String(part.dropLast()), isStem: true)
                : Word(text: String(part), isStem: false)
        }
    }
}

/// The fixed Turkish and English vocabulary of `TemplateCompiler`, in folded form (no
/// diacritics, dotless i as "i"). Order matters wherever a list is scanned first-match-wins.
enum TemplateLexicon {
    // MARK: Actions

    /// Highest priority first: a fragment yields the first kind that matches. "komutanı koru"
    /// has to win over "koru", "kalkan duvarı" over the unit name, a flank over a plain advance.
    static let actions: [(ActionKind, [TemplatePhrase])] = [
        (
            .guardCommander,
            [
                "komutan* koru*", "komutan* kolla*", "komutan* savun*", "komutan* yanina*", "komutan* yaninda*",
                "guard* the commander", "guard* commander",
                "protect* the commander", "protect* commander", "defend* the commander", "defend* commander",
            ]
        ),
        (
            .useAbility,
            [
                "yetenek*", "yeteneg*", "kirpi*", "mizrak duvar*", "kalkan duvar*", "yaylim*", "ok yagmur*", "hucum*",
                "use* ability", "use* the ability", "ability", "special*", "spear wall*", "shield wall*", "volley*",
                "charge*",
            ]
        ),
        (
            .flankLeft,
            [
                "soldan kusat*", "soldan dolan*", "sola dolan*", "soldan sar*", "sol kanat*", "flank* left",
                "flank* from the left", "flank* to the left", "left flank*",
            ]
        ),
        (
            .flankRight,
            [
                "sagdan kusat*", "sagdan dolan*", "saga dolan*", "sagdan sar*", "sag kanat*", "flank* right",
                "flank* from the right", "flank* to the right", "right flank*",
            ]
        ),
        (.takeCover, ["siper*", "sigin*", "saklan*", "take cover", "cover", "hide", "shelter*"]),
        (
            .retreat,
            [
                "geri cekil*", "geri git*", "geri don*", "geri kac*", "cekil*", "uzaklas*", "kac", "kacin", "kacsin*",
                "retreat*", "fall back",
                "falls back", "pull back", "back off", "withdraw*", "run away",
            ]
        ),
        (
            .focusFire,
            [
                "yuklen*", "odaklan*", "hedef al*", "nisan al*", "ates et*", "ates ac*", "focus*", "target*",
                "concentrate*", "pick off", "fire at", "shoot*",
            ]
        ),
        (.regroup, ["toplan*", "bir araya gel*", "birles*", "regroup*", "rally", "gather*", "group up"]),
        (.scatter, ["dagil*", "yayil*", "scatter*", "disperse", "spread out"]),
        (
            .hold,
            [
                "yerinde kal*", "yerini koru*", "mevzi*", "sabit kal*", "bekle*", "dur", "durun", "dursun",
                "dursunlar", "hold*", "stay*", "stand*", "wait*", "keep position",
            ]
        ),
        (
            .advance,
            [
                "ilerle*", "ileri git*", "ileri", "saldir", "saldirin", "saldirsin*", "saldiriya gec*", "advance*",
                "attack", "push forward", "move forward", "go forward", "engage",
            ]
        ),
    ]

    /// "en zayıfa yüklen", "focus the weakest": `focusFire` with no unit type.
    static let weakest: [TemplatePhrase] = ["zayif*", "weakest", "weak"]

    /// Only these advance words take a target ("süvarilere saldır", "attack the cavalry"), and
    /// then the order is really `focusFire` on that type.
    static let attack: [TemplatePhrase] = ["saldir", "saldirin", "saldirsin*", "attack"]

    // MARK: Conditions

    static let commander: [TemplatePhrase] = ["komutan*", "commander*", "general*"]
    static let commanderLost: [TemplatePhrase] = [
        "dustu*", "duser*", "dusunce", "dusmus*", "oldu*", "olur*", "olmus*", "olunce", "yok*", "kaybed*", "dead",
        "died", "dies", "fall*", "fell", "killed", "down", "lost", "gone",
    ]
    static let otherwise: [TemplatePhrase] = [
        "baska durum*", "diger durum*", "aksi halde", "aksi takdirde", "aksi durum*", "yoksa", "her zaman",
        "varsayilan*", "otherwise", "always", "else", "by default", "default*",
    ]
    static let flanked: [TemplatePhrase] = [
        "kusatil*", "arkadan", "arkamdan", "flanked", "surrounded", "from behind", "from the rear",
    ]
    static let seconds: [TemplatePhrase] = ["saniye*", "sn", "second*", "sec", "secs"]
    static let minutes: [TemplatePhrase] = ["dakika*", "minute*", "min"]
    static let health: [TemplatePhrase] = [
        "can", "cani*", "canim*", "canin*", "canlari*", "sagli*", "hayat*", "hp", "health*", "hit point*", "life",
    ]
    static let morale: [TemplatePhrase] = ["moral*", "cesaret*"]
    static let range: [TemplatePhrase] = ["menzil*", "range"]
    static let nearest: [TemplatePhrase] = ["en yakin*", "nearest", "closest"]
    static let ally: [TemplatePhrase] = ["dost*", "muttefik*", "arkadas*", "ally", "allies", "friend*", "comrade*"]
    static let enemy: [TemplatePhrase] = ["dusman*", "rakip*", "enemy", "enemies", "foe*"]
    static let cells: [TemplatePhrase] = ["kare*", "hucre*", "cell*", "square*", "tile*"]
    static let near: [TemplatePhrase] = ["yakin*", "yaklas*", "within", "close*", "near*"]
    static let far: [TemplatePhrase] = ["uzak*", "far", "farther", "further", "beyond"]
    /// Every numeric condition except enemy density compares *below*; these words ask for the opposite.
    static let more: [TemplatePhrase] = [
        "fazla*", "cok*", "ust*", "yuksek*", "kalabalik*", "above", "over", "more", "higher", "greater",
    ]
    static let fewer: [TemplatePhrase] = ["az*", "fewer", "less", "below", "under"]

    /// Turkish terrain needs the locative ("ormanda", "tepedeysem"): "ormana sığın" is an action
    /// target, not a condition.
    static let turkishTerrain: [(Terrain, [String])] = [
        (.forest, ["ormanlik", "orman", "agaclik", "koruluk"]),
        (.hill, ["tepe", "yamac", "sirt"]),
        (.water, ["nehir", "dere", "irmak", "su"]),
        (.rubble, ["moloz", "enkaz", "harabe", "yikinti"]),
        (.open, ["acik", "ova", "duzluk", "arazi"]),
    ]
    static let locativeEndings = ["da", "de", "ta", "te", "nda", "nde"]
    static let ablativeEndings = ["dan", "den", "tan", "ten"]
    /// English terrain needs a preposition just before it ("in the forest", "on a hill").
    static let englishTerrain: [(Terrain, [TemplatePhrase])] = [
        (.forest, ["forest*", "wood*", "tree*"]),
        (.hill, ["hill*", "high ground"]),
        (.water, ["water", "river*", "stream*"]),
        (.rubble, ["rubble", "ruin*", "debris"]),
        (.open, ["open ground", "open field", "plain*", "open"]),
    ]
    static let englishPrepositions: Set<String> = ["in", "on", "at", "inside"]
    static let englishArticles: Set<String> = ["the", "a", "an"]

    // MARK: Units

    /// Stems of the four unit types (D19 ids), longest first so "kalkanlı" wins over "kalkan".
    static let unitStems: [(stem: String, unitType: UnitTypeID)] = [
        ("mizrakci", "mizrakci"), ("mizrakli", "mizrakci"), ("spearm", "mizrakci"), ("pikem", "mizrakci"),
        ("spear", "mizrakci"), ("pike", "mizrakci"), ("okcu", "okcu"), ("archer", "okcu"), ("bowm", "okcu"),
        ("kalkanli", "kalkan"), ("kalkan", "kalkan"), ("shield", "kalkan"), ("suvari", "suvari"), ("atli", "suvari"),
        ("cavalry", "suvari"), ("horse", "suvari"), ("rider", "suvari"), ("knight", "suvari"),
    ].sorted { $0.0.count > $1.0.count }

    /// Endings that make a unit name the target of a Turkish verb: "okçulara yüklen".
    static let dativeEndings: Set<String> = ["a", "e", "ya", "ye", "lara", "lere"]

    static func unit(in word: String) -> (unitType: UnitTypeID, ending: String)? {
        guard let entry = unitStems.first(where: { word.hasPrefix($0.stem) }) else {
            return nil
        }
        return (entry.unitType, String(word.dropFirst(entry.stem.count)))
    }

    // MARK: Numbers and markers

    private static let measures: [TemplatePhrase] = cells + seconds + minutes + ally + enemy + ["%", "percent"]

    static func isMeasure(_ word: String) -> Bool {
        measures.contains { $0.words.count == 1 && $0.words[0].matches(word, rejectingConditionalForms: false) }
    }

    static func isPercentMarker(_ word: String) -> Bool {
        word == "%" || word == "yuzde"
    }

    /// Turkish conditional and "when" endings: "yakla-şırsa", "kuşatıldı-ysam", "düş-ünce".
    private static let conditionalEndings = ["sa", "se", "sam", "sem", "sak", "sek", "ince", "inca", "unca", "unce"]

    static func isConditionalEnding(_ remainder: String) -> Bool {
        !remainder.isEmpty && conditionalEndings.contains { remainder.hasSuffix($0) }
    }

    static let conditionalWords: Set<String> = [
        "if", "when", "whenever", "while", "once", "unless", "eger", "sayet", "ise", "iken",
    ]
    /// English words that merely end like a Turkish conditional.
    static let englishLookalikes: Set<String> = [
        "these", "those", "else", "close", "because", "horse", "case", "base", "chase", "lose", "loose", "whose",
        "sense", "course", "purpose", "otherwise", "disperse", "rise", "raise", "release",
    ]

    static func isConditionalWord(_ word: String) -> Bool {
        if conditionalWords.contains(word) {
            return true
        }
        guard word.count >= 4, !englishLookalikes.contains(word) else {
            return false
        }
        return conditionalEndings.contains { word.hasSuffix($0) }
    }
}
