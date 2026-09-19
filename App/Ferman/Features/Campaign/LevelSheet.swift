import FermanCore
import SwiftUI

/// SeviyeSheet'i (design brief §4.2) — a front before committing to it: the officer's one line, the
/// enemy as iron figures, the budgets side by side (a deliberate gap the player should notice, brief
/// §4.2), the order allowance, and — when this front brings a new kind of order — a sealed dispatch
/// announcing it.
struct LevelSheet: View {
    let front: CampaignFront
    var onConfirm: () -> Void

    var body: some View {
        BottomSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: FermanSpacing.lg) {
                    VStack(alignment: .leading, spacing: FermanSpacing.xs) {
                        Text(String(localized: "\(front.id). Cephe — \(front.title)"))
                            .font(FermanFont.screenTitle())
                            .tracking(FermanFont.Tracking.screenTitle)
                            .foregroundStyle(Color.paper)
                        if !front.briefing.isEmpty {
                            Text(front.briefing)
                                .font(FermanFont.body())
                                .foregroundStyle(Color.paper.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !front.enemyComposition.isEmpty, front.constraintBadge == nil {
                        enemy
                    }
                    budgets
                    statRow(label: String(localized: "Kural hakkın"), value: "\(front.ruleBudget)")
                    if let badge = front.constraintBadge {
                        statRow(label: String(localized: "Kısıt"), value: "\(badge.title) — \(badge.detail)")
                    }
                    if !front.newOrders.isEmpty {
                        dispatch
                    }

                    Button(String(localized: "Hazırlan"), action: onConfirm)
                        .buttonStyle(FermanButton.Primary())
                }
                .padding(.horizontal, FermanSpacing.lg)
                .padding(.bottom, FermanSpacing.xl)
            }
        }
    }

    private var enemy: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            Text(String(localized: "Karşındaki ordu"))
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.7))
            HStack(spacing: FermanSpacing.md) {
                ForEach(front.enemyComposition, id: \.type) { entry in
                    HStack(spacing: 2) {
                        UnitToken(type: entry.type, team: .enemy, size: .chip)
                        Text(verbatim: "×\(entry.count)")
                            .font(FermanFont.counter(size: 14, weight: .medium))
                            .foregroundStyle(Color.paper)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.count) \(OrderPhraseFormatter.unitTypeName(entry.type))")
                }
            }
        }
    }

    /// The two budgets as bars on one scale, so a gap reads at a glance before the numbers do.
    private var budgets: some View {
        let scale = CGFloat(max(front.enemyBudget, front.playerBudget, 1))
        return VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            budgetBar(
                label: String(localized: "Düşman bütçesi"), value: front.enemyBudget, fraction: CGFloat(front.enemyBudget) / scale,
                color: .iron)
            budgetBar(
                label: String(localized: "Senin bütçen"), value: front.playerBudget,
                fraction: CGFloat(front.playerBudget) / scale, color: .brass)
            if front.playerBudget < front.enemyBudget {
                Text(String(localized: "\(front.enemyBudget - front.playerBudget) puan geride başlıyorsun."))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper)
            }
        }
    }

    private func budgetBar(label: String, value: Int, fraction: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.7))
                Spacer()
                Text(String(localized: "\(value) puan"))
                    .font(FermanFont.counter(size: 15, weight: .medium))
                    .foregroundStyle(Color.paper)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.paper.opacity(0.1))
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(localized: "\(value) puan"))
    }

    /// A new kind of order arriving with this front — handed over sealed, like any other dispatch.
    private var dispatch: some View {
        HStack(alignment: .top, spacing: FermanSpacing.sm) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 18))
                .foregroundStyle(Color.paperInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Bu cephede yeni emir"))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paperInk.opacity(0.8))
                Text(front.newOrders.joined(separator: " · "))
                    .font(FermanFont.orderAction())
                    .foregroundStyle(Color.paperInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(FermanSpacing.md)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
        .accessibilityElement(children: .combine)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(label)
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.7))
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
