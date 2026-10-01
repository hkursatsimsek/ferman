import Testing

@testable import FermanAI

struct TemplateTokenizerTests {
    @Test(
        arguments: [
            ("DÜŞMAN", "dusman"), ("çekİl", "cekil"), ("IŞIK", "isik"), ("ağaçlık", "agaclik"),
            ("u\u{0308}c\u{0327}", "uc"),  // decomposed "üç"
            ("I\u{0307}LERLE", "ilerle"),  // decomposed "İLERLE"
        ])
    func foldsTurkishLetters(input: String, expected: String) {
        #expect(TemplateTokenizer.fold(input) == expected)
    }

    @Test(
        arguments: [
            ("3", 3), ("3'ten", 3), ("3ten", 3), ("40'ın", 40), ("üçten", 3), ("üçüncü", 3), ("dördüncü", 4),
            ("kırk beş", 45), ("forty-five", 45), ("altmışın", 60), ("yarıya", 50), ("on beş", 15), ("ondan", 10),
            ("onuncu", 10),
        ])
    func readsNumbers(input: String, expected: Int) {
        let numbers = TemplateTokenizer.fragments(of: input).flatMap { $0 }.compactMap(\.number)

        #expect(numbers == [expected])
    }

    @Test func belowIsNotTheNumberSix() {
        let tokens = TemplateTokenizer.fragments(of: "%40'ın altındaysa").flatMap { $0 }

        #expect(tokens.compactMap(\.number) == [40])
        #expect(tokens.map(\.word) == ["%", "40in", "altindaysa"])
    }

    @Test func englishOnIsAPrepositionUnlessCounted() {
        let preposition = TemplateTokenizer.fragments(of: "focus fire on archers").flatMap { $0 }
        let ten = TemplateTokenizer.fragments(of: "on saniye").flatMap { $0 }

        #expect(preposition.compactMap(\.number).isEmpty)
        #expect(ten.compactMap(\.number) == [10])
    }

    @Test func percentWordIsNotAHundred() {
        let tokens = TemplateTokenizer.fragments(of: "yüzde kırk").flatMap { $0 }

        #expect(tokens.compactMap(\.number) == [40])
    }

    @Test func ordinalDotDoesNotEndTheSentence() {
        #expect(TemplateTokenizer.fragments(of: "10. saniyeden sonra ilerle").count == 1)
        #expect(TemplateTokenizer.fragments(of: "ilerle. geri çekil").count == 2)
    }

    @Test func connectorsSplitFragments() {
        #expect(TemplateTokenizer.fragments(of: "fall back and regroup").count == 2)
        #expect(TemplateTokenizer.fragments(of: "geri çekil ve toplan").count == 2)
    }

    @Test func articleOneIsWeak() {
        let tokens = TemplateTokenizer.fragments(of: "bir düşman").flatMap { $0 }

        #expect(tokens.first?.isWeakNumber == true)
    }
}
