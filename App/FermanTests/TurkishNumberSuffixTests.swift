import Testing

@testable import Ferman

/// The Turkish suffix a number takes depends only on how it's spoken, which for 0–100 is fully
/// determined by the last digit (or the tens/hundred word for a round number, D21). These are
/// hand-verified ground truth for the 20 distinct "terminal words"; every other number in 0–100
/// is checked against the one whose last digit it shares, independently of how the formatter
/// itself derives that (self-consistency across a decade, not a re-implementation of it).
struct TurkishNumberSuffixTests {
    private static let genitiveTerminals: [Int: String] = [
        0: "0'ın", 1: "1'in", 2: "2'nin", 3: "3'ün", 4: "4'ün", 5: "5'in", 6: "6'nın", 7: "7'nin",
        8: "8'in", 9: "9'un", 10: "10'un", 20: "20'nin", 30: "30'un", 40: "40'ın", 50: "50'nin",
        60: "60'ın", 70: "70'in", 80: "80'in", 90: "90'ın", 100: "100'ün",
    ]

    private static let ablativeTerminals: [Int: String] = [
        0: "0'dan", 1: "1'den", 2: "2'den", 3: "3'ten", 4: "4'ten", 5: "5'ten", 6: "6'dan",
        7: "7'den", 8: "8'den", 9: "9'dan", 10: "10'dan", 20: "20'den", 30: "30'dan", 40: "40'tan",
        50: "50'den", 60: "60'tan", 70: "70'ten", 80: "80'den", 90: "90'dan", 100: "100'den",
    ]

    @Test(arguments: Array(genitiveTerminals.keys))
    func genitiveMatchesHandVerifiedTerminals(n: Int) {
        #expect(TurkishNumberSuffix.genitive(n) == Self.genitiveTerminals[n])
    }

    @Test(arguments: Array(ablativeTerminals.keys))
    func ablativeMatchesHandVerifiedTerminals(n: Int) {
        #expect(TurkishNumberSuffix.ablative(n) == Self.ablativeTerminals[n])
    }

    @Test(arguments: 0...100)
    func genitiveSharesItsTerminalsSuffixWithItsLastDigit(n: Int) {
        let terminalDigit = terminalKey(for: n)
        let expectedSuffix = Self.genitiveTerminals[terminalDigit]!.drop { $0 != "'" }
        #expect(TurkishNumberSuffix.genitive(n).hasSuffix(expectedSuffix))
    }

    @Test(arguments: 0...100)
    func ablativeSharesItsTerminalsSuffixWithItsLastDigit(n: Int) {
        let terminalDigit = terminalKey(for: n)
        let expectedSuffix = Self.ablativeTerminals[terminalDigit]!.drop { $0 != "'" }
        #expect(TurkishNumberSuffix.ablative(n).hasSuffix(expectedSuffix))
    }

    /// Which of the 20 hand-verified table entries a number shares its spoken terminal with.
    private func terminalKey(for n: Int) -> Int {
        if n == 0 || n == 100 { return n }
        let remainder = n % 10
        return remainder == 0 ? n : remainder
    }
}
