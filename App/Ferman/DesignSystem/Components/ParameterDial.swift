import SwiftUI

/// ParametreKadranı — opens right under the order card that owns it, never on a separate screen
/// (design brief §4.4). Drag the numbers sideways to turn it — a step per notch, so 10 → 40 is one
/// flick instead of fifteen taps — or tap a neighbouring number.
struct ParameterDial: View {
    let label: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    /// Points of drag per step.
    private static let notch: CGFloat = 18
    @State private var dragStartValue: Int?
    @Environment(\.audio) private var audio

    private var window: [Int] { (-2...2).map { value + $0 } }

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.slateRaised)
                .frame(width: 14, height: 7)

            VStack(spacing: FermanSpacing.sm) {
                Text(label)
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: FermanSpacing.md) {
                    ForEach(window, id: \.self) { candidate in
                        valueText(for: candidate)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // Like a wheel: dragging left brings the larger numbers in from the right.
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { drag in
                            let start = dragStartValue ?? value
                            dragStartValue = start
                            let steps = Int((-drag.translation.width / Self.notch).rounded())
                            let turned = min(max(start + steps, range.lowerBound), range.upperBound)
                            if turned != value { value = turned }
                        }
                        .onEnded { _ in dragStartValue = nil }
                )
                .sensoryFeedback(.selection, trigger: value)
                .onChange(of: value) { audio.play(.dial) }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("parameterDial")
                .accessibilityLabel(label)
                .accessibilityValue(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value = min(value + 1, range.upperBound)
                    case .decrement: value = max(value - 1, range.lowerBound)
                    @unknown default: break
                    }
                }

                ZStack {
                    Rectangle().fill(Color.paper.opacity(0.14)).frame(height: 2)
                    Rectangle().fill(Color.brass).frame(width: 2, height: 10)
                }

                Text(unit)
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.5))
            }
            .padding(.horizontal, FermanSpacing.md)
            .padding(.vertical, FermanSpacing.md)
            .background(Color.slateRaised)
            .clipShape(RoundedRectangle(cornerRadius: FermanRadius.panel))
            .overlay(
                RoundedRectangle(cornerRadius: FermanRadius.panel)
                    .strokeBorder(Color.paper.opacity(0.14), lineWidth: 1)
            )
        }
        .fermanSheetShadow()
    }

    @ViewBuilder
    private func valueText(for candidate: Int) -> some View {
        let distance = abs(candidate - value)
        let size: CGFloat = distance == 0 ? 38 : distance == 1 ? 24 : 20
        let weight: FermanFont.CounterWeight = distance == 0 ? .semibold : .medium
        let opacity: Double = distance == 0 ? 1 : distance == 1 ? 0.5 : 0.3

        let isInRange = range.contains(candidate)

        Group {
            if isInRange {
                Text("\(candidate)")
                    .onTapGesture { value = candidate }
            } else {
                // Must not carry any gesture, not even a no-op one: a gesture here still
                // swallows the touch, so it'd never fall through to close the dial
                // (`RuleEditorView`'s card-tap toggle) — and a freshly added rule always
                // starts at `range.lowerBound`, putting this dead zone right in the dial's
                // most visible, most-tapped band the moment it's first opened.
                Text(" ")
                    .allowsHitTesting(false)
            }
        }
        .font(FermanFont.counter(size: size, weight: weight))
        .foregroundStyle(Color.paper.opacity(opacity))
        .accessibilityIdentifier("parameterDial.candidate.\(candidate)")
    }
}

private struct Triangle: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("ParameterDial", traits: .sizeThatFitsLayout) {
    ParameterDial(label: "Mesafe", unit: "kare", value: .constant(4), range: 1...8)
        .padding(40)
        .background(Color.ink)
}
