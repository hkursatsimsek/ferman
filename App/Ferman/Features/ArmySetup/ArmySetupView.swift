import FermanCore
import SwiftUI

/// OrduKurulumu (design brief §4.3). Only the player's zone is on the table; the tray below it is
/// the drag source, the grid is the drop destination — both plain `String` payloads (a unit type's
/// raw id), so dragging a unit needs no custom `Transferable` type or exported UTType.
struct ArmySetupView: View {
    let front: CampaignFront
    @State var model: ArmySetupModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            header
            placementGrid
                .frame(maxHeight: .infinity)
            unitTray
            if !model.placements.isEmpty {
                writeOrdersButton
            }
        }
        .background(Color.ink)
    }

    // At least one placement showing before this appears, rather than showing it disabled from the
    // start: `FermanButton.Primary()`'s disabled state (`Color.paper` at low opacity on low opacity)
    // isn't meant to sit on screen at launch — `performAccessibilityAudit()` flags it there (F1.14).
    private var writeOrdersButton: some View {
        Button(String(localized: "Emirleri Yaz")) {
            router.push(.ruleEditor(front, model.teamSetup))
        }
        .buttonStyle(FermanButton.Primary())
        .padding(FermanSpacing.md)
        .background(Color.slateRaised)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.sm) {
            BudgetMeter(label: String(localized: "Bütçe"), used: model.usedBudget, total: model.totalBudget)
            if let badge = model.constraintBadge {
                HStack(spacing: FermanSpacing.xs) {
                    Text(badge.title)
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.brass)
                    Text(badge.detail)
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.paper.opacity(0.75))
                }
            }
        }
        .padding(FermanSpacing.md)
    }

    /// The zone laid out upright like the battle table (D26): its column nearest the enemy on top,
    /// ASCII row 0 on the left — so a unit lands in battle exactly where it was placed.
    private var placementGrid: some View {
        let screenRows = BoardProjection(map: model.map).screenRows(columns: model.gridColumns, rows: model.gridRows)
        let columnCount = screenRows.first?.count ?? 1
        return GeometryReader { proxy in
            let cellSize = min(
                proxy.size.width / CGFloat(columnCount), proxy.size.height / CGFloat(max(screenRows.count, 1)))
            ZStack {
                SandTable()
                if let zoneTableImage = model.zoneTableImage {
                    Image(decorative: zoneTableImage, scale: TerrainBaker.battlePixelsPerPoint)
                        .resizable()
                        .frame(width: cellSize * CGFloat(columnCount), height: cellSize * CGFloat(screenRows.count))
                }
                VStack(spacing: 0) {
                    ForEach(screenRows.indices, id: \.self) { screenRow in
                        HStack(spacing: 0) {
                            ForEach(screenRows[screenRow], id: \.row) { cell in
                                cellView(column: cell.column, row: cell.row, cellSize: cellSize)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .frame(width: cellSize * CGFloat(columnCount), height: cellSize * CGFloat(screenRows.count))
                if model.placements.isEmpty {
                    emptyGridHint
                }
            }
        }
    }

    /// Nothing else on this screen hints that placing units is a *drag* — without this, a first-time
    /// player sees an empty grid and a tray with no visible next step (found via a real playtest,
    /// F1.14). `.allowsHitTesting(false)` so it never steals a drop from the grid cell underneath it.
    ///
    /// Backed by a `slateRaised` panel rather than sitting directly on `SandTable`'s variable-brightness
    /// shader — the same fix F1.13 already needed for `CampaignView`'s front rows, and for the same
    /// reason: `performAccessibilityAudit()` fails contrast against a background that isn't a flat color.
    private var emptyGridHint: some View {
        VStack(spacing: FermanSpacing.xs) {
            Image(systemName: "hand.draw")
                .font(.system(size: 28))
                .foregroundStyle(Color.paper.opacity(0.5))
            Text(String(localized: "Birimlerini aşağıdaki tepsiden buraya sürükle."))
                .font(FermanFont.body())
                .foregroundStyle(Color.paper)
                .multilineTextAlignment(.center)
        }
        .padding(FermanSpacing.lg)
        .background(Color.slateRaised.opacity(0.94), in: RoundedRectangle(cornerRadius: FermanRadius.panel))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Birimlerini aşağıdaki tepsiden buraya sürükle."))
    }

    @ViewBuilder
    private func cellView(column: Int, row: Int, cellSize: CGFloat) -> some View {
        if let cell = model.map.cellIndex(column: column, row: row), model.isPlayerZone(cell) {
            PlacementSlotView(
                model: model, cell: cell, cellSize: cellSize, accessibilityLabel: accessibilityLabel(forCell: cell))
        } else {
            Color.clear
        }
    }

    private func accessibilityLabel(forCell cell: Int) -> String {
        guard let placement = model.placement(at: cell) else {
            return String(localized: "Boş hücre")
        }
        let name = OrderPhraseFormatter.unitTypeName(placement.unitType)
        return placement.isCommander ? String(localized: "\(name), komutan") : name
    }

    private var unitTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FermanSpacing.lg) {
                ForEach(model.catalog, id: \.id) { unitType in
                    // The whole card is the drag source, not just the `UnitToken` circle — a 44pt
                    // silhouette was a hard-to-hit drag handle on its own (found via a real
                    // playtest, F1.14); the label and cost underneath now start the drag too.
                    VStack(spacing: FermanSpacing.xxs) {
                        UnitToken(type: unitType.id, size: .tray)
                        Text(OrderPhraseFormatter.unitTypeName(unitType.id))
                            .font(FermanFont.caption())
                            .foregroundStyle(Color.paper)
                        Text(String(localized: "\(unitType.cost)p"))
                            .font(FermanFont.counter(size: 12))
                            .foregroundStyle(Color.paper.opacity(0.75))
                    }
                    .padding(FermanSpacing.xs)
                    // Still draggable when it doesn't fit — the drop is refused with a warning haptic
                    // (`PlacementSlotView`) — but dimmed so the player sees why before trying.
                    .opacity(model.canAfford(unitType.id) ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .draggable(unitType.id.rawValue)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "\(OrderPhraseFormatter.unitTypeName(unitType.id)), \(unitType.cost) puan")
                    )
                    .accessibilityHint(model.canAfford(unitType.id) ? "" : String(localized: "Bütçe yetmiyor."))
                }
            }
            .padding(FermanSpacing.md)
        }
        .background(Color.slateRaised)
    }
}

/// One placement cell. Its own view (rather than a `ArmySetupView` method) so it can own the
/// `isTargeted` highlight — the only feedback a player gets, while their finger is still down, that
/// a cell will actually receive the drop (found missing via a real playtest, F1.14).
private struct PlacementSlotView: View {
    let model: ArmySetupModel
    let cell: Int
    let cellSize: CGFloat
    let accessibilityLabel: String

    @State private var isTargeted = false
    @State private var refusedDrops = 0

    private var placement: ArmyPlacement? { model.placement(at: cell) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isTargeted ? Color.brass.opacity(0.25) : Color.clear)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isTargeted ? Color.brass : Color.paper.opacity(0.18), lineWidth: isTargeted ? 2 : 1)
            if let placement {
                placedUnitView(placement)
            }
        }
        .padding(2)
        .dropDestination(for: String.self, isEnabled: placement == nil) { droppedIDs, session in
            switch session.phase {
            case .entering, .active:
                isTargeted = true
            default:
                isTargeted = false
            }
            guard let rawUnitType = droppedIDs.first else { return }
            if !model.place(UnitTypeID(rawValue: rawUnitType), at: cell) {
                refusedDrops += 1
            }
        }
        .sensoryFeedback(.warning, trigger: refusedDrops)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func placedUnitView(_ placement: ArmyPlacement) -> some View {
        ZStack(alignment: .topTrailing) {
            UnitToken(
                type: placement.unitType, size: .onTable(cellSize: cellSize),
                isSelected: model.selectedPlacementID == placement.id)
            if placement.isCommander {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.brass)
                    .offset(x: 3, y: -3)
            }
        }
        // The figure's base is well under the tappable minimum on its own
        // (found via a real playtest, F1.14). The whole cell (already sized well past 44pt by
        // `placementGrid`'s layout) becomes the tap/context-menu target instead of just the token.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            model.toggleSelection(placement.id)
        }
        .contextMenu {
            if placement.isCommander {
                Button(String(localized: "Komutanlığı Kaldır")) {
                    model.clearCommander(placement.id)
                }
            } else {
                Button(String(localized: "Komutan Yap")) {
                    model.setCommander(placement.id)
                }
            }
            Button(role: .destructive) {
                model.remove(placement.id)
            } label: {
                Text(String(localized: "Kaldır"))
            }
        }
    }
}
