import SwiftUI
import TipKit

/// A note as the art direction wants it: a torn scrap of paper, pencil-grey words, a little askew on the
/// table — not a system bubble.
struct PencilNoteStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: FermanSpacing.sm) {
            // Drawn, not an SF Symbol: inside a TipView the symbol stays in the accessibility tree
            // ("Düzenle") however it's hidden, and VoiceOver would read the note as an edit button.
            PencilGlyph()
                .fill(Color.paperInk.opacity(0.75))
                .frame(width: 14, height: 14)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                if let note = configuration.tip as? any PencilNote {
                    Text(note.heading)
                        .font(FermanFont.orderAction())
                        .foregroundStyle(Color.paperInk)
                    Text(note.line)
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.paperInk)
                } else {
                    configuration.title
                    configuration.message
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.paperInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Notu kapat"))
        }
        .padding(.leading, FermanSpacing.md)
        .padding(.vertical, FermanSpacing.sm)
        // Only the paper lies askew; the words stay upright inside the tip's bounds — a turned text frame
        // pokes out of them and the accessibility audit reports it clipped.
        .background {
            DeckleEdge(seed: 17)
                .fill(Color.paper)
                .rotationEffect(.degrees(-0.8))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
    }
}

/// A pencil lying at a slant, point down-left — the note's mark.
private struct PencilGlyph: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        // Body: a slanted band from the top-right towards the point.
        path.move(to: CGPoint(x: width * 0.72, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.28))
        path.addLine(to: CGPoint(x: width * 0.34, y: height * 0.94))
        path.addLine(to: CGPoint(x: width * 0.06, y: height * 0.66))
        path.closeSubpath()
        // Point.
        path.move(to: CGPoint(x: width * 0.06, y: height * 0.72))
        path.addLine(to: CGPoint(x: width * 0.28, y: height * 0.94))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }
}
