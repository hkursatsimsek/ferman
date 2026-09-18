import SwiftUI

/// BütçeGöstergesi — used / total, with a distinct overflow treatment.
struct BudgetMeter: View {
    let label: String
    let used: Int
    let total: Int

    private var isOverflow: Bool { used > total }
    private var fraction: Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                Text(label)
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.65))
                Spacer()
                Text("\(used) / \(total)")
                    .font(FermanFont.counter(size: 17, weight: .medium))
                    .foregroundStyle(isOverflow ? Color.alarm : Color.paper)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.paper.opacity(0.12))
                    Rectangle()
                        .fill(isOverflow ? Color.alarm : Color.brass)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("BudgetMeter", traits: .sizeThatFitsLayout) {
    VStack(spacing: FermanSpacing.md) {
        BudgetMeter(label: "Bütçe", used: 248, total: 310)
        BudgetMeter(label: "Aşım", used: 335, total: 310)
    }
    .padding()
    .frame(width: 280)
    .background(Color.slateRaised)
}
