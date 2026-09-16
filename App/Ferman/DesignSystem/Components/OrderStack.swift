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

        init(id: UUID = UUID(), priority: Int, condition: String, action: String, state: OrderCardState) {
            self.id = id
            self.priority = priority
            self.condition = condition
            self.action = action
            self.state = state
        }
    }

    let items: [Item]

    var body: some View {
        VStack(spacing: FermanSpacing.md - 2) {
            ForEach(items) { item in
                OrderCard(priority: item.priority, condition: item.condition, action: item.action, state: item.state)
            }
        }
    }
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
