import SwiftUI

/// AltSheet — 14pt corners, elevated metal-housing surface (design brief §3.4).
struct BottomSheet<Content: View>: View {
    @ViewBuilder var content: Content

    /// The drag handle's band above `content` — for a sheet that sizes its detent to what it holds.
    static var handleHeight: CGFloat { FermanSpacing.sm + 4 + FermanSpacing.md + 2 }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.paper.opacity(0.25))
                .frame(width: 38, height: 4)
                .padding(.top, FermanSpacing.sm)
                .padding(.bottom, FermanSpacing.md + 2)
            content
        }
        // The surface runs on under the home indicator; otherwise the clear system sheet shows the
        // table through a strip below the content.
        .background {
            UnevenRoundedRectangle(topLeadingRadius: FermanRadius.panel, topTrailingRadius: FermanRadius.panel)
                .fill(Color.slateRaised)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: FermanRadius.panel, topTrailingRadius: FermanRadius.panel)
                .strokeBorder(Color.paper.opacity(0.12), lineWidth: 1)
                .ignoresSafeArea(edges: .bottom)
        }
        .fermanSheetShadow()
    }
}

#Preview("BottomSheet", traits: .sizeThatFitsLayout) {
    BottomSheet {
        VStack(alignment: .leading, spacing: FermanSpacing.md) {
            Text("14. Cephe — Taş Geçit")
                .font(FermanFont.screenTitle())
                .tracking(FermanFont.Tracking.screenTitle)
                .foregroundStyle(Color.paper)
            BudgetMeter(label: "Senin bütçen", used: 248, total: 310)
        }
        .padding(.horizontal, FermanSpacing.lg)
        .padding(.bottom, FermanSpacing.xl)
    }
    .frame(width: 393)
    .background(Color.ink)
}
