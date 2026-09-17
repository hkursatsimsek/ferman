import SwiftUI

/// SeviyeSheet'i (design brief §4.2) — a front's numbers before committing to it. `BottomSheet`'s own
/// preview already mocked this exact layout ("14. Cephe — Taş Geçit", 420 vs. 310 puan); this is its
/// first real use as a `.sheet(item:)`.
struct LevelSheet: View {
    let front: CampaignFront
    var onConfirm: () -> Void

    var body: some View {
        BottomSheet {
            VStack(alignment: .leading, spacing: FermanSpacing.lg) {
                Text(String(localized: "\(front.id). Cephe — \(front.title)"))
                    .font(FermanFont.screenTitle())
                    .tracking(FermanFont.Tracking.screenTitle)
                    .foregroundStyle(Color.paper)

                VStack(alignment: .leading, spacing: FermanSpacing.md) {
                    statRow(
                        label: String(localized: "Düşman bütçesi"),
                        value: String(localized: "\(front.enemyBudget) puan"))
                    BudgetMeter(label: String(localized: "Senin bütçen"), used: 0, total: front.playerBudget)
                    BudgetMeter(label: String(localized: "Kural hakkın"), used: 0, total: front.ruleBudget)
                    if let badge = front.constraintBadge {
                        statRow(label: String(localized: "Kısıt"), value: "\(badge.title) — \(badge.detail)")
                    }
                }

                Button(String(localized: "Hazırlan"), action: onConfirm)
                    .buttonStyle(FermanButton.Primary())
            }
            .padding(.horizontal, FermanSpacing.lg)
            .padding(.bottom, FermanSpacing.xl)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(label)
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.65))
            Spacer()
            Text(value)
                .font(FermanFont.counter(size: 17, weight: .medium))
                .foregroundStyle(Color.paper)
        }
    }
}

#Preview("LevelSheet", traits: .sizeThatFitsLayout) {
    LevelSheet(front: .placeholders[2], onConfirm: {})
        .frame(width: 393)
        .background(Color.ink)
}
