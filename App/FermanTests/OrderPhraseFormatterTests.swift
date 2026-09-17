import FermanCore
import Testing

@testable import Ferman

struct OrderPhraseFormatterTests {
    @Test
    func numericConditionsEmbedTheirSuffixedNumber() {
        #expect(OrderPhraseFormatter.condition(.enemyWithin(cells: 3)) == "düşman 3 kareden yakınsa")
        #expect(OrderPhraseFormatter.condition(.healthBelow(percent: 35)) == "canım %35'in altındaysa")
        #expect(OrderPhraseFormatter.condition(.moraleBelow(percent: 40)) == "moralim %40'ın altındaysa")
        #expect(OrderPhraseFormatter.condition(.allyCountBelow(count: 2)) == "yanımda 2'den az dost varsa")
        #expect(
            OrderPhraseFormatter.condition(.enemyDensityAbove(count: 4)) == "yakınımda 4'ten fazla düşman varsa")
        #expect(OrderPhraseFormatter.condition(.timeAfter(seconds: 20)) == "20. saniyeden sonra")
    }

    @Test
    func parameterlessConditionsMatchTheDesignBrief() {
        #expect(OrderPhraseFormatter.condition(.isFlanked) == "kuşatıldıysam")
        #expect(OrderPhraseFormatter.condition(.commanderDead) == "komutan düştüyse")
        #expect(OrderPhraseFormatter.condition(.always) == "başka durumda")
    }

    @Test
    func unitTypeConditionsLookUpTheCatalogDisplayName() {
        #expect(OrderPhraseFormatter.condition(.targetInRange("okcu")) == "menzilimde Okçu varsa")
        #expect(OrderPhraseFormatter.condition(.nearestEnemyType("suvari")) == "en yakın düşman Süvari ise")
    }

    @Test
    func actionsMatchTheDesignBriefsAllCaps() {
        #expect(OrderPhraseFormatter.action(.advance, ability: nil) == "İLERLE")
        #expect(OrderPhraseFormatter.action(.retreat, ability: nil) == "GERİ ÇEKİL")
        #expect(OrderPhraseFormatter.action(.takeCover, ability: nil) == "SİPER AL")
        #expect(OrderPhraseFormatter.action(.guardCommander, ability: nil) == "KOMUTANI KORU")
    }

    @Test
    func focusFireNamesItsTargetOnlyWhenGivenOne() {
        #expect(OrderPhraseFormatter.action(.focusFire(nil), ability: nil) == "YÜKLEN")
        #expect(OrderPhraseFormatter.action(.focusFire("okcu"), ability: nil) == "OKÇU YÜKLEN")
    }

    @Test
    func useAbilityNamesTheActingUnitsOwnAbility() {
        #expect(OrderPhraseFormatter.action(.useAbility, ability: .spearWall) == "MIZRAK DUVARI")
        #expect(OrderPhraseFormatter.action(.useAbility, ability: .volley) == "YAYLIM")
        #expect(OrderPhraseFormatter.action(.useAbility, ability: .charge) == "HÜCUM")
        #expect(OrderPhraseFormatter.action(.useAbility, ability: .shieldWall) == "KALKAN DUVARI")
    }
}
