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
    /// Stamped with the worn ink seal — the orders sealed as the battle starts (brief §3.5).
    var isSealed = false
    /// The priority of an earlier order that always decides first: this one is folded under it and will
    /// never run (`RuleReachability`).
    var foldedUnder: Int?
    /// Marks the condition's number with a dotted underline — "tap here to change it" (design mock).
    var highlightsParameter = false

    /// A fixed badge that still grows with Dynamic Type — a bare `Circle` with only a minimum size takes
    /// every point the row offers and squeezes the order's words into a narrow column.
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 23

    var body: some View {
        HStack(alignment: .top, spacing: FermanSpacing.sm) {
            priorityBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(conditionText)
                    .font(FermanFont.orderCondition())
                    .foregroundStyle(conditionColor)
                Text(action)
                    .font(FermanFont.orderAction())
                    .tracking(FermanFont.Tracking.orderAction)
                    .foregroundStyle(actionColor)
                if let foldedUnder {
                    Text(String(localized: "\(foldedUnder). emir yüzünden hiç sıra gelmez."))
                        .font(FermanFont.caption())
                        .italic()
                        .foregroundStyle(Color.paperInk.opacity(0.75))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            trailingAccessory
        }
        .padding(.horizontal, FermanSpacing.md)
        .padding(.vertical, FermanSpacing.sm + 1)
        .background(background)
        .overlay(alignment: .topTrailing) {
            if isSealed, state != .isDefault {
                SealMark()
                    .frame(width: 34, height: 34)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -6, y: 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if foldedUnder != nil, state != .isDefault {
                DogEar().frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
        .clipShape(DeckleEdge(seed: priority))
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
        // Scaled, not fixed at 23pt: at accessibility Dynamic Type sizes a fixed circle would clip the
        // number (F1.13), and a mere minimum lets the circle grow to fill the row.
        .frame(width: badgeSize, height: badgeSize)
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
            // `.disabled` used to sit on a dim paper tint; a `performAccessibilityAudit()` failure
            // (F1.13) showed `paperInk` text needs a genuinely light card under it to stay readable,
            // so it now shares `.normal`'s full-strength card and dims only its badge stroke instead.
            case .normal, .dragging, .triggered, .editing, .disabled:
                Paper()
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

    /// The condition, with its number (`3`, `%35`) dotted-underlined in brass when it can be tapped.
    private var conditionText: AttributedString {
        var text = AttributedString(condition)
        guard highlightsParameter, let match = condition.firstMatch(of: /%?\d+/),
            let range = Range(match.range, in: text)
        else { return text }
        text[range].underlineStyle = Text.LineStyle(pattern: .dot, color: .brass)
        return text
    }

    private var conditionColor: Color {
        switch state {
        case .isDefault: Color.paper.opacity(0.75)
        default: Color.paperInk
        }
    }

    private var actionColor: Color {
        switch state {
        case .isDefault: Color.paper.opacity(0.85)
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
        case .isDefault: Color.paper.opacity(0.75)
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

/// Paper fill (design brief §3.0): a faint horizontal fibre, sparse flecks, and the one fold every
/// order slip carries from being folded into a dispatch.
private struct Paper: View {
    var body: some View {
        Color.paper
            .overlay(
                Canvas { context, size in
                    let fibre = Path { path in
                        var y: CGFloat = 0
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += 4
                        }
                    }
                    context.stroke(fibre, with: .color(.paperInk.opacity(0.035)), lineWidth: 1)

                    // Flecks at stable, hashed spots — the same card looks the same every time.
                    for fleck in 0..<Int(size.width * size.height / 900) {
                        let x = Self.noise(fleck, 1) * size.width
                        let y = Self.noise(fleck, 2) * size.height
                        let radius = 0.3 + Self.noise(fleck, 3) * 0.5
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                            with: .color(.paperInk.opacity(0.12)))
                    }

                    let foldY = (size.height * 0.42).rounded()
                    context.fill(
                        Path(CGRect(x: 0, y: foldY, width: size.width, height: 0.75)),
                        with: .color(.paperInk.opacity(0.07)))
                    context.fill(
                        Path(CGRect(x: 0, y: foldY + 0.75, width: size.width, height: 0.75)),
                        with: .color(.white.opacity(0.22)))
                }
            )
    }

    fileprivate static func noise(_ index: Int, _ salt: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: index &* 2_654_435_761 ^ salt &* 40_503)
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return CGFloat(value % 10_000) / 10_000
    }
}

/// A slip cut from a sheet, not a card from a machine: edges that wander a fraction of a point, the
/// same way every time for the same slip (brief §3.0 — "hafif tırtıklı").
struct DeckleEdge: Shape {
    let seed: Int

    nonisolated func path(in rect: CGRect) -> Path {
        let step: CGFloat = 5
        var path = Path()
        func wobble(_ index: Int, _ side: Int) -> CGFloat {
            var value = UInt64(truncatingIfNeeded: (index &* 73_856_093) ^ (side &* 19_349_663) ^ (seed &* 83_492_791))
            value = (value ^ (value >> 31)) &* 0x9E37_79B9_7F4A_7C15
            return CGFloat(value % 1_000) / 1_000 * 0.9
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        var x = rect.minX
        var index = 0
        while x < rect.maxX {
            x = min(x + step, rect.maxX)
            index += 1
            path.addLine(to: CGPoint(x: x, y: rect.minY + wobble(index, 0)))
        }
        var y = rect.minY
        while y < rect.maxY {
            y = min(y + step, rect.maxY)
            index += 1
            path.addLine(to: CGPoint(x: rect.maxX - wobble(index, 1) * 0.5, y: y))
        }
        x = rect.maxX
        while x > rect.minX {
            x = max(x - step, rect.minX)
            index += 1
            path.addLine(to: CGPoint(x: x, y: rect.maxY - wobble(index, 2)))
        }
        y = rect.maxY
        while y > rect.minY {
            y = max(y - step, rect.minY)
            index += 1
            path.addLine(to: CGPoint(x: rect.minX + wobble(index, 3) * 0.5, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// The worn ink seal pressed on an order when it's sealed (brief §3.0, §3.5): cut in reverse and inked,
/// never waxed, so each impression is a little starved of ink in places (ART-DIRECTION §6).
private struct SealMark: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let ink = GraphicsContext.Shading.color(.paperInk.opacity(0.42))
            // Two rings, broken where the ink ran thin.
            for (ringRadius, width) in [(radius, 1.6), (radius * 0.78, 0.9)] {
                var ring = Path()
                ring.addArc(
                    center: center, radius: ringRadius, startAngle: .degrees(8), endAngle: .degrees(160), clockwise: false)
                ring.move(to: CGPoint(x: center.x + ringRadius * cos(.pi * 175 / 180), y: center.y + ringRadius * sin(.pi * 175 / 180)))
                ring.addArc(
                    center: center, radius: ringRadius, startAngle: .degrees(175), endAngle: .degrees(355),
                    clockwise: false)
                context.stroke(ring, with: ink, lineWidth: width)
            }
            // An eight-pointed rosette in the middle — a mark, not a signature (no tughra, brief §3.0).
            var rosette = Path()
            for point in 0..<16 {
                let angle = CGFloat(point) / 16 * 2 * .pi - .pi / 2
                let length = point.isMultiple(of: 2) ? radius * 0.55 : radius * 0.24
                let vertex = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
                if point == 0 { rosette.move(to: vertex) } else { rosette.addLine(to: vertex) }
            }
            rosette.closeSubpath()
            context.fill(rosette, with: ink)
        }
    }
}

/// The corner of a slip folded down: this order is tucked under an earlier one.
private struct DogEar: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Triangle().fill(Color.ink.opacity(0.9))
            Triangle().fill(Color.paper).rotationEffect(.degrees(180))
                .overlay(Triangle().fill(Color.paperInk.opacity(0.14)).rotationEffect(.degrees(180)))
        }
    }

    private struct Triangle: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }
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
        OrderCard(
            priority: 2, condition: "düşman 3 kareden yakınsa", action: "YERİNDE KAL", state: .normal, foldedUnder: 1,
            highlightsParameter: true)
        OrderCard(priority: 1, condition: "canım %35'in altındaysa", action: "SİPER AL", state: .normal, isSealed: true)
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
