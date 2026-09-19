import SwiftUI

/// AnaMenü (design brief §4.1): the upper half is the sand table with the last battle still standing
/// on it (fallen figures where they fell), fading into the room's dark; the wordmark sits on it; the
/// menu is below. No banner, no counters.
struct HomeView: View {
    @State var model: HomeModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            table
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) { wordmark }
            menu
        }
        .background(Color.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.loadTableau() }
    }

    @ViewBuilder
    private var table: some View {
        ZStack {
            if let tableau = model.tableau {
                BattleSceneView(config: tableau.config, timeline: tableau.timeline, clock: tableau.clock)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else {
                SandTable()
                    .opacity(0.5)
            }
            // The lamp's reach ends before the menu does: the table fades into the room.
            LinearGradient(colors: [.clear, Color.ink], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.6), value: model.tableau != nil)
        .accessibilityHidden(true)
    }

    private var wordmark: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xxs) {
            Text(verbatim: "FERMAN")
                .font(.custom("Archivo-SemiBold", size: 34, relativeTo: .largeTitle))
                .tracking(9)
                .foregroundStyle(Color.paper)
            if let caption = model.tableau?.caption {
                Text(caption)
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.75))
            }
        }
        .padding(FermanSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.md) {
            menuRow(
                title: String(localized: "Seferberlik"), subtitle: model.campaignSubtitle, isEnabled: true,
                identifier: "home.seferberlik"
            ) {
                router.push(.campaign)
            }
            ForEach(model.secondaryRows) { row in
                menuRow(
                    title: row.title, subtitle: row.subtitle, isEnabled: row.route != nil,
                    identifier: "home.\(row.id)"
                ) {
                    if let route = row.route { router.push(route) }
                }
            }
        }
        .padding(FermanSpacing.lg)
        .background(Color.slateRaised)
    }

    private func menuRow(
        title: String, subtitle: String, isEnabled: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        let titleText = Text(title)
            .font(FermanFont.sectionTitle())
            .foregroundStyle(isEnabled ? Color.paper : Color.paper.opacity(0.75))
        let subtitleText = Text(subtitle)
            .font(FermanFont.caption())
            .foregroundStyle(isEnabled ? Color.brass : Color.paper.opacity(0.75))
        let marker = Image(systemName: isEnabled ? "chevron.right" : "lock")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Color.paper.opacity(0.4) : Color.paper.opacity(0.3))
            .accessibilityHidden(true)
        return Button(action: action) {
            // The title keeps its line; at large Dynamic Type sizes the subtitle wraps instead of
            // being cut off.
            HStack(alignment: .firstTextBaseline) {
                titleText
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: FermanSpacing.sm)
                if !subtitle.isEmpty {
                    subtitleText
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                marker
            }
            .padding(.vertical, FermanSpacing.sm)
            // A plain-styled row only hit-tests its intrinsic content, leaving the `Spacer()`-stretched
            // middle non-tappable — this claims the full row as the tap target.
            .contentShape(Rectangle())
        }
        .buttonStyle(FermanButton.Row())
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
