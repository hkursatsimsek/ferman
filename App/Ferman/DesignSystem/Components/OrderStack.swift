import SwiftUI

/// PusulaYığını — a vertical stack of order cards. Reordering is wired up
/// by the screen that owns real rule data (F1.7); this is presentation only.
struct OrderStack: View {
    struct Item: Identifiable {
        let id: UUID
        var priority: Int
        var condition: String
        var action: String
        var state: OrderCardState
        /// Shown once above the first item of each run of equal titles — e.g. the unit type whose
        /// program follows, when several programs share one stack.
        var groupTitle: String?

        init(
            id: UUID = UUID(), priority: Int, condition: String, action: String, state: OrderCardState,
            groupTitle: String? = nil
        ) {
            self.id = id
            self.priority = priority
            self.condition = condition
            self.action = action
            self.state = state
            self.groupTitle = groupTitle
        }
    }

    let items: [Item]
    /// Items at or past this index keep their place in the layout but stay invisible — a stack that
    /// is still being stamped in grows card by card without the cards above it shifting.
    var revealedCount: Int = .max
    /// Revealed cards carry the ink seal — the stack being sealed before battle (brief §3.5).
    var sealsRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.md - 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let title = item.groupTitle, index == 0 || items[index - 1].groupTitle != title {
                    Text(title)
                        .font(FermanFont.tab())
                        .foregroundStyle(Color.paper.opacity(0.75))
                        .padding(.top, index == 0 ? 0 : FermanSpacing.sm)
                        .opacity(index < revealedCount ? 1 : 0)
                }
                OrderCard(
                    priority: item.priority, condition: item.condition, action: item.action, state: item.state,
                    isSealed: sealsRevealed && index < revealedCount
                )
                .opacity(index < revealedCount ? 1 : 0)
                .scaleEffect(index < revealedCount ? 1 : 1.06)
            }
        }
    }
}

#Preview("OrderStack — gruplu", traits: .sizeThatFitsLayout) {
    OrderStack(
        items: [
            .init(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal, groupTitle: "Okçu"),
            .init(priority: 2, condition: "başka durumda", action: "İLERLE", state: .isDefault, groupTitle: "Okçu"),
            .init(priority: 1, condition: "başka durumda", action: "YERİNDE KAL", state: .isDefault, groupTitle: "Kalkanlı"),
        ], revealedCount: 2
    )
    .padding()
    .background(Color.ink)
}

#Preview("OrderStack", traits: .sizeThatFitsLayout) {
    OrderStack(items: [
        .init(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal),
        .init(priority: 2, condition: "canım %35'in altındaysa", action: "SİPER AL", state: .normal),
        .init(priority: 3, condition: "başka durumda", action: "İLERLE", state: .isDefault),
    ])
    .padding()
    .background(Color.ink)
}
