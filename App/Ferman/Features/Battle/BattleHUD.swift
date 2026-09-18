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

/// The live trigger strip under the sand table (design brief §4.5). It always reserves
/// `reservedRowCount` rows — the army's longest program — so switching to a unit type with fewer
/// orders, or the strip filling in after the intro, never resizes the table above it.
struct BattleTriggerStrip: View {
    let rows: [BattleModel.TriggerRow]
    let reservedRowCount: Int

    var body: some View {
        VStack(spacing: FermanSpacing.sm) {
            ForEach(0..<max(reservedRowCount, rows.count), id: \.self) { index in
                if index < rows.count {
                    let row = rows[index]
                    TriggerBar(priority: row.priority, fraction: row.fraction, count: row.count, isSpark: row.isSpark)
                } else {
                    TriggerBar(priority: index + 1, fraction: 0, count: 0, isSpark: false)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(FermanSpacing.md)
        .background(Color.slateRaised.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: FermanRadius.panel))
        .padding(.horizontal, FermanSpacing.sm)
        .padding(.bottom, FermanSpacing.xs)
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
                .init(id: 0, priority: 1, fraction: 0.74, count: 14, isSpark: false),
                .init(id: 1, priority: 2, fraction: 1, count: 19, isSpark: true),
                .init(id: 2, priority: 3, fraction: 0, count: 0, isSpark: false),
            ],
            reservedRowCount: 4)
    }
    .background(Color.ink)
    .frame(width: 393, height: 500)
}
