import SwiftUI

/// TetiklenmeÇubuğu — a live-filling counter. The one place spark glows
/// outside the battle scene itself (design brief §3.2, §4.5).
struct TriggerBar: View {
    let priority: Int
    let fraction: Double
    let count: Int
    let isSpark: Bool

    var body: some View {
        HStack(spacing: FermanSpacing.xs + 2) {
            Text("\(priority)")
                .font(FermanFont.counter(size: 11))
                .foregroundStyle(isSpark ? Color.spark : Color.paper.opacity(0.55))
                // `minWidth`, not `width` — a hard width clips this at accessibility Dynamic Type sizes.
                .frame(minWidth: 12, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.paper.opacity(0.1))
                    Capsule()
                        .fill(isSpark ? Color.spark : Color.brass)
                        .frame(width: proxy.size.width * fraction)
                        .shadow(color: .spark.opacity(isSpark ? 0.8 : 0), radius: 6)
                }
            }
            .frame(height: 6)

            Text("\(count)")
                .font(FermanFont.counter(size: 12))
                .foregroundStyle(isSpark ? Color.spark : Color.paper.opacity(0.7))
                .frame(minWidth: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(priority). emir"))
        .accessibilityValue(String(localized: "\(count) kez tetiklendi"))
    }
}

#Preview("TriggerBar", traits: .sizeThatFitsLayout) {
    VStack(spacing: FermanSpacing.sm) {
        TriggerBar(priority: 1, fraction: 0.74, count: 14, isSpark: false)
        TriggerBar(priority: 2, fraction: 0.42, count: 8, isSpark: true)
        TriggerBar(priority: 3, fraction: 0, count: 0, isSpark: false)
    }
    .padding()
    .frame(width: 260)
    .background(Color.slateRaised)
}
