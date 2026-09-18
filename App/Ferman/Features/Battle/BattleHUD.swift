import Foundation
import SwiftUI

/// The battle screen's only chrome: a minimal top bar and the live trigger strip (design brief
/// §4.5). Presentation only — reads whatever `BattleView` hands it.
struct BattleHUD: View {
    let elapsedSeconds: Int
    let isPlaying: Bool
    @Binding var speed: BattleSpeed
    let triggerRows: [BattleModel.TriggerRow]
    var onTogglePlayPause: () -> Void
    var onRestart: () -> Void
    var onShowResult: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if !triggerRows.isEmpty {
                triggerStrip
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: FermanSpacing.md) {
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

    private var triggerStrip: some View {
        VStack(spacing: FermanSpacing.sm) {
            ForEach(triggerRows) { row in
                TriggerBar(priority: row.priority, fraction: row.fraction, count: row.count, isSpark: row.isSpark)
            }
        }
        .padding(FermanSpacing.md)
        .background(Color.slateRaised.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: FermanRadius.panel))
        .padding(.horizontal, FermanSpacing.sm)
        .padding(.bottom, FermanSpacing.xs)
    }

    private var timeText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

#Preview("BattleHUD", traits: .sizeThatFitsLayout) {
    ZStack {
        Color.ink
        VStack {
            BattleHUD(
                elapsedSeconds: 23,
                isPlaying: true,
                speed: .constant(.x2),
                triggerRows: [
                    .init(id: 0, priority: 1, fraction: 0.74, count: 14, isSpark: false),
                    .init(id: 1, priority: 2, fraction: 1, count: 19, isSpark: true),
                    .init(id: 2, priority: 3, fraction: 0, count: 0, isSpark: false),
                ],
                onTogglePlayPause: {},
                onRestart: {},
                onShowResult: {}
            )
            Spacer()
        }
    }
    .frame(width: 393, height: 500)
}
