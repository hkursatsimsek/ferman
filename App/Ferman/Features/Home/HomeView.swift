import SwiftUI

/// AnaMenü (design brief §4.1). Kum masası kısmen görünür arka planda; menü altta dikey sıralanır.
struct HomeView: View {
    @State var model: HomeModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            SandTable()
                .opacity(0.4)
                .ignoresSafeArea()
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: FermanSpacing.md) {
                    menuRow(
                        title: String(localized: "Seferberlik"), subtitle: model.campaignSubtitle, isEnabled: true,
                        identifier: "home.seferberlik"
                    ) {
                        router.push(.campaign)
                    }
                    ForEach(model.secondaryRows) { row in
                        menuRow(
                            title: row.title, subtitle: row.subtitle, isEnabled: false,
                            identifier: "home.\(row.id)", action: {})
                    }
                }
                .padding(FermanSpacing.lg)
                .background(Color.slateRaised)
            }
        }
        .background(Color.ink)
    }

    private func menuRow(
        title: String, subtitle: String, isEnabled: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(FermanFont.sectionTitle())
                    .foregroundStyle(isEnabled ? Color.paper : Color.paper.opacity(0.75))
                Spacer()
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(FermanFont.caption())
                        .foregroundStyle(isEnabled ? Color.brass : Color.paper.opacity(0.75))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.paper.opacity(0.4) : Color.paper.opacity(0.15))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, FermanSpacing.sm)
            // `.buttonStyle(.plain)` alone leaves the `Spacer()`-stretched middle of the row
            // non-tappable (it only hit-tests the intrinsic content, not the reported frame) — this
            // claims the full row as the tap target.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title), \(subtitle)")
    }
}

#Preview("HomeView") {
    NavigationStack {
        HomeView(model: HomeModel(nextFront: .placeholders[2]))
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
