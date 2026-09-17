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
                        .foregroundStyle(Color.paper.opacity(0.6))
                    Text(front.title)
                        .font(FermanFont.sectionTitle())
                        .foregroundStyle(isLocked ? Color.paper.opacity(0.4) : Color.paper)
                }
                Spacer()
            }
            // See `HomeView.menuRow` — `.buttonStyle(.plain)` needs this to make the
            // `Spacer()`-stretched part of the row tappable, not just its intrinsic content.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityIdentifier("campaign.front.\(front.id)")
    }
}

#Preview("CampaignView") {
    NavigationStack {
        CampaignView(model: CampaignModel())
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
