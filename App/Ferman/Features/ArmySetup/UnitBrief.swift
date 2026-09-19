import FermanCore
import SwiftUI

/// What the unit in hand is for, shown above the tray while it's chosen: its part in the army in one
/// line, and how fast, far-reaching and sturdy it is on a three-step scale — adjectives, not a stat
/// sheet, since the numbers only matter relative to each other.
struct UnitBrief: View {
    let unitType: UnitType

    var body: some View {
        HStack(alignment: .top, spacing: FermanSpacing.md) {
            UnitToken(type: unitType.id, size: .result)
            VStack(alignment: .leading, spacing: FermanSpacing.xs) {
                Text(OrderPhraseFormatter.unitTypeName(unitType.id))
                    .font(FermanFont.tabSelected())
                    .foregroundStyle(Color.paper)
                Text(Self.role(of: unitType.id))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: FermanSpacing.md) {
                    scale(String(localized: "Hız"), Self.step(unitType.speedMilliCellsPerSecond, cuts: 1_000, 1_500))
                    scale(String(localized: "Menzil"), Self.step(unitType.rangeMilliCells, cuts: 1_200, 3_000))
                    scale(String(localized: "Dayanıklılık"), Self.step(unitType.maxHP, cuts: 100, 140))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(FermanSpacing.md)
        .background(Color.slate)
        .accessibilityElement(children: .combine)
    }

    private func scale(_ name: String, _ level: Int) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.7))
            ForEach(0..<3, id: \.self) { pip in
                Circle()
                    .fill(pip < level ? Color.brass : Color.paper.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Self.levelWord(level))
    }

    /// 1–3: below the first cut, between the cuts, at or past the second.
    private static func step(_ value: Int, cuts low: Int, _ high: Int) -> Int {
        value < low ? 1 : value < high ? 2 : 3
    }

    private static func levelWord(_ level: Int) -> String {
        switch level {
        case 1: String(localized: "düşük")
        case 2: String(localized: "orta")
        default: String(localized: "yüksek")
        }
    }

    /// The four shipped units' parts, in the officer's plain voice (brief §7). A unit added to the
    /// catalog without one here gets no line rather than a wrong one.
    private static func role(of unitType: UnitTypeID) -> String {
        switch unitType.rawValue {
        case "mizrakci": String(localized: "Süvariye karşı güçlü. Mızrak duvarıyla atlıları durdurur.")
        case "okcu": String(localized: "Uzaktan vurur, yakında zayıftır. Yaylımla bir alanı döver.")
        case "suvari": String(localized: "Hızlıdır, okçuları avlar. Hücumda ilk vuruşu sert indirir.")
        case "kalkan": String(localized: "Oklara dayanır, hattı tutar. Kalkan duvarıyla yerinde durur.")
        default: ""
        }
    }
}
