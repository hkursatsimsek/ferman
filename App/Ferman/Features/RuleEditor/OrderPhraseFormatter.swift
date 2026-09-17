import FermanCore
import Foundation

/// Turns a `Condition`/`Action` into the Turkish text on an order card. The only place FermanCore's
/// enums become words — the core itself stays silent on language (D21).
nonisolated enum OrderPhraseFormatter {
    static func condition(_ condition: Condition) -> String {
        switch condition {
        case .enemyWithin(let cells):
            String(localized: "düşman \(cells) kareden yakınsa")
        case .healthBelow(let percent):
            String(localized: "canım %\(TurkishNumberSuffix.genitive(percent)) altındaysa")
        case .allyCountBelow(let count):
            String(localized: "yanımda \(TurkishNumberSuffix.ablative(count)) az dost varsa")
        case .isFlanked:
            String(localized: "kuşatıldıysam")
        case .targetInRange(let unitType):
            String(localized: "menzilimde \(unitTypeName(unitType)) varsa")
        case .timeAfter(let seconds):
            String(localized: "\(seconds). saniyeden sonra")
        case .nearestEnemyType(let unitType):
            String(localized: "en yakın düşman \(unitTypeName(unitType)) ise")
        case .moraleBelow(let percent):
            String(localized: "moralim %\(TurkishNumberSuffix.genitive(percent)) altındaysa")
        case .terrainIs(let terrain):
            terrainPhrase(terrain)
        case .commanderDead:
            String(localized: "komutan düştüyse")
        case .enemyDensityAbove(let count):
            String(localized: "yakınımda \(TurkishNumberSuffix.ablative(count)) fazla düşman varsa")
        case .always:
            String(localized: "başka durumda")
        }
    }

    /// `ability` is only read for `.useAbility`; pass the acting unit type's `UnitType.ability`.
    static func action(_ action: Action, ability: Ability?) -> String {
        switch action {
        case .advance:
            String(localized: "İLERLE")
        case .retreat:
            String(localized: "GERİ ÇEKİL")
        case .hold:
            String(localized: "YERİNDE KAL")
        case .focusFire(let unitType):
            if let unitType {
                String(localized: "\(unitTypeName(unitType).uppercased()) YÜKLEN")
            } else {
                String(localized: "YÜKLEN")
            }
        case .flankLeft:
            String(localized: "SOLDAN KUŞAT")
        case .flankRight:
            String(localized: "SAĞDAN KUŞAT")
        case .regroup:
            String(localized: "TOPLAN")
        case .useAbility:
            abilityPhrase(ability)
        case .takeCover:
            String(localized: "SİPER AL")
        case .guardCommander:
            String(localized: "KOMUTANI KORU")
        case .scatter:
            String(localized: "DAĞIL")
        }
    }

    private static func terrainPhrase(_ terrain: Terrain) -> String {
        switch terrain {
        case .open: String(localized: "açık arazideysem")
        case .forest: String(localized: "ormandaysam")
        case .hill: String(localized: "tepedeysem")
        case .water: String(localized: "sudaysam")
        case .rubble: String(localized: "molozdaysam")
        }
    }

    private static func abilityPhrase(_ ability: Ability?) -> String {
        switch ability {
        case .spearWall: String(localized: "MIZRAK DUVARI")
        case .volley: String(localized: "YAYLIM")
        case .charge: String(localized: "HÜCUM")
        case .shieldWall: String(localized: "KALKAN DUVARI")
        case nil: String(localized: "YETENEĞİNİ KULLAN")
        }
    }

    /// `unit.<id>` (D19) — the unit's display name is never in FermanCore, only its identifier.
    ///
    /// `String(localized: String.LocalizationValue(interpolatedKey))` doesn't do a plain key lookup:
    /// interpolated segments become substitution placeholders in the *key itself* (it's built for
    /// "%d elmam var" style templates, not for selecting between unrelated keys). A genuinely
    /// dynamic key needs the older `Bundle.localizedString(forKey:value:table:)`, which still reads
    /// a String Catalog's compiled table.
    static func unitTypeName(_ unitType: UnitTypeID) -> String {
        let key = "unit.\(unitType.rawValue)"
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// `unit.<id>.pluralPossessiveGenitive` (design brief §4.6 — "Okçularının %70'i ..."): plural +
    /// 3rd-person possessive + genitive, e.g. "Okçu" → "Okçularının" (of the/your/their archers).
    /// Turkish's 2nd- and 3rd-person possessive-genitive chains converge on this same surface form,
    /// so `DebriefInsightFormatter` reuses it both for the player's own army (implicit "your") and,
    /// prefixed with "Düşman ", for the enemy's ("of the enemy's archers").
    static func pluralPossessiveGenitiveUnitName(_ unitType: UnitTypeID) -> String {
        let key = "unit.\(unitType.rawValue).pluralPossessiveGenitive"
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
