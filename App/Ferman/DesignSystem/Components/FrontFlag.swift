import SwiftUI

enum FrontFlagState: Hashable {
    case cleared
    case open
    case locked

    /// The flag carries this through color alone otherwise — VoiceOver has no color.
    var accessibilityDescription: String {
        switch self {
        case .cleared: String(localized: "geçildi")
        case .open: String(localized: "açık")
        case .locked: String(localized: "kilitli")
        }
    }
}

/// CepheBayrağı — a map pin stuck into the sand table (design brief §4.2).
struct FrontFlag: View {
    let state: FrontFlagState

    private var poleColor: Color {
        switch state {
        case .cleared: Color.brass
        case .open: Color(hex: 0xC2A05C)
        case .locked: Color.iron
        }
    }

    private var poleHeight: CGFloat { state == .locked ? 38 : 44 }
    private var poleTopInset: CGFloat { state == .locked ? 6 : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(poleColor)
                .frame(width: 2, height: poleHeight)
                .padding(.top, poleTopInset)
                .opacity(state == .locked ? 0.6 : 1)

            RoundedRectangle(cornerRadius: 1)
                .fill(poleColor)
                .frame(width: 13, height: 10)
                .offset(x: 2, y: poleTopInset + 3)
                .opacity(state == .locked ? 0.6 : 1)
                .shadow(color: poleColor.opacity(state == .open ? 0.7 : 0), radius: 10)
        }
        .frame(width: 26, height: 44, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
    }
}

#Preview("FrontFlag", traits: .sizeThatFitsLayout) {
    HStack(alignment: .bottom, spacing: FermanSpacing.lg) {
        VStack {
            FrontFlag(state: .cleared)
            Text("geçildi").font(FermanFont.caption())
        }
        VStack {
            FrontFlag(state: .open)
            Text("açık").font(FermanFont.caption()).foregroundStyle(Color(hex: 0xC2A05C))
        }
        VStack {
            FrontFlag(state: .locked)
            Text("kilitli").font(FermanFont.caption())
        }
    }
    .foregroundStyle(Color.paper.opacity(0.5))
    .padding()
    .background(Color.sand)
}
