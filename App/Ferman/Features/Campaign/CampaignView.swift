import SwiftUI

/// Seferberlik (design brief §4.2) — the campaign as pins stuck along a winding track on the sand
/// table, first front at the bottom, marching up. Cleared stretches of the track are brass; the front
/// to play next stands taller. Tapping an unlocked pin opens `LevelSheet`; "Hazırlan" pushes into
/// Ordu Kurulumu.
struct CampaignView: View {
    @State var model: CampaignModel
    /// Re-reads the fronts from progress whenever the line comes back into view — a battle just won
    /// clears its pin and opens the next.
    var loadFronts: () -> [CampaignFront] = { [] }
    @State private var selectedFront: CampaignFront?
    @Environment(AppRouter.self) private var router

    private static let rowHeight: CGFloat = 108
    /// Where each front's pin stands across the table, as a fraction of its width — a track that winds.
    private static let lanes: [CGFloat] = [0.3, 0.62, 0.4, 0.7, 0.28, 0.58, 0.36, 0.66]

    private var bottomUp: [CampaignFront] { model.fronts.reversed() }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: FermanSpacing.lg) {
                    header
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            track(width: geometry.size.width)
                            VStack(spacing: 0) {
                                ForEach(Array(bottomUp.enumerated()), id: \.element.id) { _, front in
                                    pinRow(front, width: geometry.size.width)
                                        .frame(height: Self.rowHeight)
                                        .id(front.id)
                                }
                            }
                        }
                    }
                    .frame(height: Self.rowHeight * CGFloat(model.fronts.count))
                }
                .padding(.vertical, FermanSpacing.lg)
                .padding(.horizontal, FermanSpacing.md)
            }
            .onAppear {
                let fresh = loadFronts()
                if !fresh.isEmpty { model.update(fronts: fresh) }
                if let current = model.currentFront?.id { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .background(SandTable().ignoresSafeArea())
        .navigationTitle(String(localized: "Seferberlik"))
        .navigationBarTitleDisplayMode(.inline)
        // The title sits over lamp-lit sand otherwise — no contrast it can promise (accessibility audit).
        .toolbarBackground(Color.ink.opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $selectedFront) { front in
            LevelSheet(front: front) {
                selectedFront = nil
                router.push(.armySetup(front))
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
            // Without this, the system falls back to its own default corner radius for the sheet
            // container itself — different from `BottomSheet`'s own `FermanRadius.panel` rounding —
            // so the (invisible-but-still-shaped) system container reads as a second, mismatched
            // rounded card stacked behind ours.
            .presentationCornerRadius(FermanRadius.panel)
        }
    }

    private var header: some View {
        Text(String(localized: "\(model.clearedCount) cephe geçildi"))
            .font(FermanFont.caption())
            .foregroundStyle(Color.paper)
            .padding(.horizontal, FermanSpacing.sm)
            .padding(.vertical, FermanSpacing.xxs)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
    }

    private func laneX(_ front: CampaignFront, width: CGFloat) -> CGFloat {
        Self.lanes[(front.id - 1) % Self.lanes.count] * width
    }

    /// The dashed track between pins, drawn under them; brass where the player has already marched.
    private func track(width: CGFloat) -> some View {
        Canvas { context, _ in
            let fronts = bottomUp
            for index in fronts.indices.dropLast() {
                let upper = fronts[index]
                let lower = fronts[index + 1]
                var segment = Path()
                segment.move(
                    to: CGPoint(x: laneX(upper, width: width), y: CGFloat(index) * Self.rowHeight + Self.rowHeight / 2))
                segment.addLine(
                    to: CGPoint(
                        x: laneX(lower, width: width), y: CGFloat(index + 1) * Self.rowHeight + Self.rowHeight / 2))
                let marched = lower.state == .cleared
                context.stroke(
                    segment, with: .color(marched ? .brass.opacity(0.9) : .ink.opacity(0.45)),
                    style: StrokeStyle(lineWidth: marched ? 2 : 1.5, lineCap: .round, dash: [6, 6]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pinRow(_ front: CampaignFront, width: CGFloat) -> some View {
        let isLocked = !model.canOpen(front)
        let isCurrent = front.id == model.currentFront?.id
        // A pin on the right half carries its label on its left, so the words always have most of the
        // row to wrap into at large Dynamic Type sizes instead of being squeezed against the edge.
        let labelLeads = laneX(front, width: width) > width / 2
        let pin = ZStack {
            if isCurrent {
                Circle()
                    .fill(Color(hex: 0xC2A05C).opacity(0.35))
                    .frame(width: 44, height: 44)
                    .blur(radius: 8)
            }
            FrontFlag(state: front.state)
                .scaleEffect(isCurrent ? 1.35 : 1)
        }
        let label = VStack(alignment: labelLeads ? .trailing : .leading, spacing: 2) {
            Text(String(localized: "\(front.id). Cephe"))
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.8))
            Text(front.title)
                .font(isCurrent ? FermanFont.sectionTitle() : FermanFont.tabSelected())
                .foregroundStyle(isLocked ? Color.paper.opacity(0.75) : Color.paper)
                .multilineTextAlignment(labelLeads ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The sand's brightness varies with the lamp, so words on it get a dark slip of their own — a
        // fixed contrast the accessibility audit can check (F1.13).
        .padding(.horizontal, FermanSpacing.sm)
        .padding(.vertical, FermanSpacing.xxs)
        .background(Color.ink.opacity(0.85), in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
        return Button {
            selectedFront = front
        } label: {
            HStack(spacing: FermanSpacing.sm) {
                if labelLeads {
                    label
                    pin
                } else {
                    pin
                    label
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FermanButton.Row())
        .disabled(isLocked)
        .padding(labelLeads ? .trailing : .leading, max(0, labelLeads ? width - laneX(front, width: width) - 14 : laneX(front, width: width) - 14))
        .frame(maxWidth: .infinity, alignment: labelLeads ? .trailing : .leading)
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
