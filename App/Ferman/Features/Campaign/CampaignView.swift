import SwiftUI

/// Cephe (design brief §4.2) — a vertical line of front-line pins over the sand table. Tapping an
/// unlocked pin opens `LevelSheet`; its "Hazırlan" pushes into Ordu Kurulumu (F1.8).
struct CampaignView: View {
    @State var model: CampaignModel
    @State private var selectedFront: CampaignFront?
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: FermanSpacing.xl) {
                ForEach(model.fronts.reversed()) { front in
                    frontRow(front)
                }
            }
            .padding(.vertical, FermanSpacing.xl)
            .padding(.horizontal, FermanSpacing.lg)
        }
        .background(SandTable().ignoresSafeArea())
        .navigationTitle(String(localized: "Cephe"))
        .sheet(item: $selectedFront) { front in
            LevelSheet(front: front) {
                selectedFront = nil
                router.push(.armySetup(front))
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
            // Without this, the system falls back to its own default corner radius for the sheet
            // container itself — different from `BottomSheet`'s own `FermanRadius.panel` rounding —
            // so the (invisible-but-still-shaped) system container reads as a second, mismatched
            // rounded card stacked behind ours.
            .presentationCornerRadius(FermanRadius.panel)
        }
    }

    private func frontRow(_ front: CampaignFront) -> some View {
        let isLocked = !model.canOpen(front)
        return Button {
            selectedFront = front
        } label: {
            HStack(spacing: FermanSpacing.md) {
                FrontFlag(state: front.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "\(front.id). Cephe"))
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.paper.opacity(0.75))
                    Text(front.title)
                        .font(FermanFont.sectionTitle())
                        .foregroundStyle(isLocked ? Color.paper.opacity(0.75) : Color.paper)
                }
                Spacer()
            }
            .padding(FermanSpacing.md)
            // The sand table underneath varies in brightness with its lighting (design brief §3.2),
            // so text sitting directly on it can't have a fixed, checkable contrast ratio — a
            // `performAccessibilityAudit()` failure (F1.13), not a style choice. This panel gives
            // every row the same solid, dark backing regardless of what's rendered behind it.
            .background(Color.slateRaised.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: FermanRadius.panel))
            // See `HomeView.menuRow` — `.buttonStyle(.plain)` needs this to make the
            // `Spacer()`-stretched part of the row tappable, not just its intrinsic content.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityIdentifier("campaign.front.\(front.id)")
        // See `HomeView.menuRow`: default combining across `FrontFlag` + two differently-colored
        // `Text` runs gave the contrast audit a frame wide enough to sample empty space instead of
        // either one (F1.13). Must come after `accessibilityIdentifier` — the reverse order drops it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(front.id). Cephe, \(front.title), \(front.state.accessibilityDescription)")
        )
    }
}

#Preview("CampaignView") {
    NavigationStack {
        CampaignView(model: CampaignModel())
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
