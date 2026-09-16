import SwiftUI

/// KumMasası — the battlefield surface itself. No corner radius; it's the table, not a card.
struct SandTable: View {
    var body: some View {
        Rectangle()
            .fill(Color.sand)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.sandTableLight(
                        .float2(proxy.size),
                        .color(.sandLit),
                        .color(.sand)
                    )
                )
            }
            .overlay(GridOverlay())
    }
}

private struct GridOverlay: View {
    private let step: CGFloat = 33

    var body: some View {
        Canvas { context, size in
            let line = GraphicsContext.Shading.color(.ink.opacity(0.07))
            var x: CGFloat = 0
            while x < size.width {
                context.stroke(
                    Path {
                        $0.move(to: CGPoint(x: x, y: 0))
                        $0.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: line,
                    lineWidth: 1
                )
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                context.stroke(
                    Path {
                        $0.move(to: CGPoint(x: 0, y: y))
                        $0.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: line,
                    lineWidth: 1
                )
                y += step
            }
        }
    }
}

#Preview("SandTable", traits: .sizeThatFitsLayout) {
    SandTable()
        .frame(width: 393, height: 400)
}
