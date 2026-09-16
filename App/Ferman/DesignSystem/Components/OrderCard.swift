import SwiftUI

enum OrderCardState: Equatable {
    case normal
    case dragging
    case triggered(count: Int)
    case disabled
    case isDefault
    case editing
}

/// EmirPusulası — an order card. A physical object, not a row: paper cut at 2pt,
/// its own shadow, no divider lines inside it (design brief §4.4).
struct OrderCard: View {
    let priority: Int
    let condition: String
    let action: String
    let state: OrderCardState

    var body: some View {
        HStack(alignment: .top, spacing: FermanSpacing.sm) {
            priorityBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(condition)
                    .font(FermanFont.orderCondition())
                    .foregroundStyle(conditionColor)
                Text(action)
                    .font(FermanFont.orderAction())
                    .tracking(FermanFont.Tracking.orderAction)
                    .foregroundStyle(actionColor)
            }
            Spacer(minLength: 0)
            trailingAccessory
        }
        .padding(.horizontal, FermanSpacing.md)
        .padding(.vertical, FermanSpacing.sm + 1)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: FermanRadius.orderCard))
        .overlay(border)
        .overlay(triggeredGlow)
        .rotationEffect(.degrees(state == .dragging ? -1.1 : 0))
        .compositingGroup()
        .modifier(ShadowForState(state: state))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var priorityBadge: some View {
        let dashed = state == .isDefault
        ZStack {
            Circle()
                .strokeBorder(
                    badgeStroke,
                    style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : [])
                )
            Text("\(priority)")
                .font(FermanFont.counter(size: 12))
                .foregroundStyle(badgeText)
        }
        .frame(width: 23, height: 23)
        .padding(.top, 1)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch state {
        case .triggered(let count):
            Text("\(count)×")
                .font(FermanFont.counter(size: 13, weight: .medium))
                .foregroundStyle(Color.paperInk)
                .padding(.top, 4)
        case .normal, .dragging:
            DotGridHandle()
                .padding(.top, 4)
        case .disabled, .isDefault, .editing:
            EmptyView()
        }
    }

    private var background: some View {
        Group {
            switch state {
            case .normal, .dragging, .triggered, .editing:
                Paper()
            case .disabled:
                Color.paper.opacity(0.14)
            case .isDefault:
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var border: some View {
        if state == .isDefault {
            RoundedRectangle(cornerRadius: FermanRadius.orderCard)
                .strokeBorder(Color.paper.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }

    @ViewBuilder
    private var triggeredGlow: some View {
        if case .triggered = state {
            RoundedRectangle(cornerRadius: FermanRadius.orderCard)
                .strokeBorder(Color.spark, lineWidth: 2)
                .shadow(color: .spark.opacity(0.4), radius: 12)
        }
    }

    private var conditionColor: Color {
        switch state {
        case .disabled: Color.paperInk.opacity(0.38)
        case .isDefault: Color.paper.opacity(0.55)
        default: Color.paperInk
        }
    }

    private var actionColor: Color {
        switch state {
        case .disabled: Color.paperInk.opacity(0.38)
        case .isDefault: Color.paper.opacity(0.7)
        default: Color.paperInk
        }
    }

    private var badgeStroke: Color {
        switch state {
        case .disabled: Color.paper.opacity(0.28)
        case .isDefault: Color.paper.opacity(0.35)
        default: Color.brass
        }
    }

    private var badgeText: Color {
        switch state {
        case .disabled: Color.paper.opacity(0.4)
        case .isDefault: Color.paper.opacity(0.55)
        default: Color.paperInk
        }
    }

    private struct ShadowForState: ViewModifier {
        let state: OrderCardState

        func body(content: Content) -> some View {
            switch state {
            case .dragging:
                AnyView(content.fermanDraggingShadow())
            case .editing:
                AnyView(content.fermanEditingShadow())
            case .disabled, .isDefault:
                AnyView(content)
            default:
                AnyView(content.fermanCardShadow())
            }
        }
    }
}

/// Paper fill with a faint horizontal fiber texture (design brief §3.0 — "elyaf deseni").
private struct Paper: View {
    var body: some View {
        Color.paper
            .overlay(
                Canvas { context, size in
                    var y: CGFloat = 0
                    let line = Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: size.width, y: 0))
                    }
                    while y < size.height {
                        context.translateBy(x: 0, y: y == 0 ? 0 : 4)
                        context.stroke(line, with: .color(.paperInk.opacity(0.035)), lineWidth: 1)
                        y += 4
                    }
                }
            )
    }
}

private struct DotGridHandle: View {
    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3.5) {
            GridRow {
                dot
                dot
            }
            GridRow {
                dot
                dot
            }
            GridRow {
                dot
                dot
            }
        }
    }

    private var dot: some View {
        Circle()
            .fill(Color.paperInk.opacity(0.42))
            .frame(width: 3, height: 3)
    }
}

#Preview("OrderCard — durumlar", traits: .sizeThatFitsLayout) {
    VStack(spacing: FermanSpacing.sm) {
        OrderCard(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal)
        OrderCard(priority: 2, condition: "canım %35'in altındaysa", action: "SİPER AL", state: .dragging)
        OrderCard(
            priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .triggered(count: 14))
        OrderCard(priority: 3, condition: "düşman okçuysa", action: "KUŞAT", state: .disabled)
        OrderCard(priority: 4, condition: "başka durumda", action: "İLERLE", state: .isDefault)
    }
    .padding()
    .background(Color.ink)
    .environment(\.colorScheme, .dark)
}

#Preview("OrderCard — açık mod", traits: .sizeThatFitsLayout) {
    OrderCard(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal)
        .padding()
        .background(Color.ink)
        .environment(\.colorScheme, .light)
}

#Preview("OrderCard — XXL", traits: .sizeThatFitsLayout) {
    OrderCard(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal)
        .padding()
        .background(Color.ink)
        .environment(\.dynamicTypeSize, .accessibility3)
}
