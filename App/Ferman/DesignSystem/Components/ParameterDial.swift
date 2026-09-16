import SwiftUI

/// ParametreKadranı — opens on top of the order card that owns it, never on
/// a separate screen. The five-up carousel is the whole interaction (design brief §4.4).
struct ParameterDial: View {
    let label: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>

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

        Text(range.contains(candidate) ? "\(candidate)" : " ")
            .font(FermanFont.counter(size: size, weight: weight))
            .foregroundStyle(Color.paper.opacity(opacity))
            .onTapGesture {
                if range.contains(candidate) { value = candidate }
            }
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
