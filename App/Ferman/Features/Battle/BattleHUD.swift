import FermanCore
import Foundation
import SwiftUI

/// The battle screen's top bar (design brief §4.5). Presentation only — reads whatever `BattleView`
/// hands it.
struct BattleTopBar: View {
    let elapsedSeconds: Int
    let isPlaying: Bool
    @Binding var speed: BattleSpeed
    var onBack: () -> Void
    var onTogglePlayPause: () -> Void
    var onRestart: () -> Void
    var onShowResult: () -> Void

    var body: some View {
        HStack(spacing: FermanSpacing.md) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .foregroundStyle(Color.paper.opacity(0.85))
            }
            .accessibilityLabel(String(localized: "Geri"))

            Text(timeText)
                .font(FermanFont.counter(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.paper)
                .frame(minWidth: 44, alignment: .leading)

            Spacer(minLength: 0)

            Button(action: onRestart) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(Color.paper.opacity(0.85))
            }
            .accessibilityLabel(String(localized: "Başa sar"))

            Button(action: onTogglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(Color.paper.opacity(0.85))
            }
            .accessibilityLabel(isPlaying ? String(localized: "Duraklat") : String(localized: "Oynat"))

            SpeedControl(selection: $speed)

            Button(action: onShowResult) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Color.paper.opacity(0.85))
            }
            .accessibilityLabel(String(localized: "Sonuç"))
        }
        .padding(.horizontal, FermanSpacing.md)
        .padding(.vertical, FermanSpacing.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: FermanRadius.panel))
        .padding(.horizontal, FermanSpacing.sm)
        .padding(.top, FermanSpacing.xs)
    }

    private var timeText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

/// The live trigger strip under the sand table (design brief §4.5): the selected unit type's orders,
/// each with its words, a live bar and a count; the one that just fired lit in spark (brief §3.2).
/// It always reserves `reservedRowCount` rows — the army's longest program — so switching to a unit
/// type with fewer orders, or the strip filling in after the intro, never resizes the table above it.
struct BattleTriggerStrip: View {
    let rows: [BattleModel.TriggerRow]
    let reservedRowCount: Int
    var unitTypes: [UnitTypeID] = []
    var selectedUnitType: UnitTypeID?
    var onSelectUnitType: (UnitTypeID) -> Void = { _ in }
    /// The evaluating pen slides from order to order rather than blinking between them.
    @Namespace private var penSpace

    var body: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            if unitTypes.count > 1 {
                unitTypeTabs
            }
            ForEach(0..<max(reservedRowCount, rows.count), id: \.self) { index in
                if index < rows.count {
                    TriggerRowView(row: rows[index], penSpace: penSpace)
                } else {
                    TriggerRowView(
                        row: .init(id: index, priority: index + 1, fraction: 0, count: 0, isSpark: false), penSpace: penSpace)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
        .animation(.easeInOut(duration: 0.14), value: rows.map(\.pen))
        .padding(.horizontal, FermanSpacing.md)
        .padding(.vertical, FermanSpacing.sm)
        .background(Color.slate)
        .clipShape(RoundedRectangle(cornerRadius: FermanRadius.panel))
        .padding(.horizontal, FermanSpacing.sm)
        .padding(.bottom, FermanSpacing.xs)
    }

    private var unitTypeTabs: some View {
        HStack(spacing: FermanSpacing.sm) {
            ForEach(unitTypes, id: \.self) { unitType in
                let isSelected = unitType == selectedUnitType
                Button {
                    onSelectUnitType(unitType)
                } label: {
                    HStack(spacing: FermanSpacing.xxs) {
                        UnitToken(type: unitType, size: .chip)
                        Text(OrderPhraseFormatter.unitTypeName(unitType))
                            .font(isSelected ? FermanFont.tabSelected() : FermanFont.tab())
                            .foregroundStyle(isSelected ? Color.paper : Color.paper.opacity(0.7))
                    }
                    .padding(.trailing, FermanSpacing.xs)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(isSelected ? Color.brass : .clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(OrderPhraseFormatter.unitTypeName(unitType))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// One order in the strip: its number, its words (condition regular, action bold — the same anatomy
/// as the order slip, brief §4.4), a thin live bar and its count.
private struct TriggerRowView: View {
    let row: BattleModel.TriggerRow
    let penSpace: Namespace.ID
    /// A fixed badge that still grows with Dynamic Type — a bare `Circle` takes all the height it's offered.
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: FermanSpacing.sm) {
            ZStack {
                Circle()
                    .strokeBorder(
                        row.isSpark ? Color.spark : Color.paper.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.2, dash: row.isDefault ? [2.5, 2] : []))
                Text("\(row.priority)")
                    .font(FermanFont.counter(size: 11))
                    .foregroundStyle(row.isSpark ? Color.spark : Color.paper.opacity(0.75))
            }
            .frame(width: badgeSize, height: badgeSize)
            // The pen sits in the strip's margin, pointing at the order it's reading.
            .overlay(alignment: .leading) {
                if row.pen == .reading || row.pen == .holds {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(-135))
                        .foregroundStyle(row.pen == .holds ? Color.brass : Color.paper.opacity(0.8))
                        .matchedGeometryEffect(id: "pen", in: penSpace)
                        .offset(x: -15)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    "\(Text(row.condition).foregroundStyle(Color.paper.opacity(0.7))) \(Text(row.action).bold().foregroundStyle(row.isSpark ? Color.spark : Color.paper))"
                )
                .strikethrough(row.pen == .passed, color: Color.paper.opacity(0.6))
                .font(FermanFont.caption())
                .lineLimit(1)
                .truncationMode(.middle)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.paper.opacity(0.1))
                        Capsule()
                            .fill(row.isSpark ? Color.spark : Color.brass)
                            .frame(width: proxy.size.width * row.fraction)
                            .shadow(color: .spark.opacity(row.isSpark ? 0.8 : 0), radius: 5)
                    }
                }
                .frame(height: 3)
            }

            Text("\(row.count)")
                .font(FermanFont.counter(size: 12))
                .monospacedDigit()
                .foregroundStyle(row.isSpark ? Color.spark : Color.paper.opacity(0.75))
                .frame(minWidth: 26, alignment: .trailing)
        }
        .opacity(row.pen == .passed ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(row.priority). emir. \(row.condition) \(row.action)"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let count = String(localized: "\(row.count) kez tetiklendi")
        switch row.pen {
        case .passed: return count + ", " + String(localized: "koşulu tutmadı")
        case .holds: return count + ", " + String(localized: "şu an uygulanıyor")
        case .reading, nil: return count
        }
    }
}

#Preview("Battle HUD", traits: .sizeThatFitsLayout) {
    VStack {
        BattleTopBar(
            elapsedSeconds: 23, isPlaying: true, speed: .constant(.x2),
            onBack: {}, onTogglePlayPause: {}, onRestart: {}, onShowResult: {})
        Spacer()
        BattleTriggerStrip(
            rows: [
                .init(
                    id: 0, priority: 1, fraction: 0.74, count: 14, isSpark: false,
                    condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL"),
                .init(
                    id: 1, priority: 2, fraction: 1, count: 19, isSpark: true, condition: "canım %35'in altındaysa",
                    action: "SİPER AL"),
                .init(
                    id: 2, priority: 3, fraction: 0, count: 0, isSpark: false, condition: "başka durumda",
                    action: "İLERLE", isDefault: true),
            ],
            reservedRowCount: 4, unitTypes: ["okcu", "kalkan"], selectedUnitType: "okcu")
    }
    .background(Color.ink)
    .frame(width: 393, height: 500)
}
