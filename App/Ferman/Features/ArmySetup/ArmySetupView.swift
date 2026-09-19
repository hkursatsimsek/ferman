import FermanCore
import SwiftUI

/// OrduKurulumu (design brief §4.3). The whole upright table (D26), the same baked picture the battle
/// draws, scrolled to the player's zone at the bottom; the enemy's iron figures stand at the top.
/// Two ways to place a unit: pick it from the tray and tap a cell, or drag it there. Placed figures
/// can be dragged to another cell. Payloads are plain `String`s — a unit type's raw id, or
/// `move:<placement id>` — so no custom `Transferable` type or exported UTType is needed.
struct ArmySetupView: View {
    let front: CampaignFront
    @State var model: ArmySetupModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            header
            board
                .frame(maxHeight: .infinity)
            if let chosen = model.chosenTrayUnit.flatMap(model.unitType) {
                UnitBrief(unitType: chosen)
                    .transition(.opacity)
            }
            unitTray
            if !model.placements.isEmpty {
                writeOrdersButton
            }
        }
        .background(Color.ink)
        .animation(.easeOut(duration: 0.2), value: model.chosenTrayUnit)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: model.placements.count)
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

    // MARK: - Table

    /// The table fills the width, so its cells are as large as a phone allows; it is taller than the
    /// space left, so it scrolls, starting at the bottom where the player deploys.
    private var board: some View {
        GeometryReader { proxy in
            let table = BoardProjection.table(for: model.map)
            let cellSize = proxy.size.width / (table.boardSize.width / table.pointsPerCell)
            let projection = table.scaled(toPointsPerCell: cellSize)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    if let image = model.tableImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: projection.boardSize.width, height: projection.boardSize.height)
                    } else {
                        SandTable()
                    }
                    enemyFigures(projection)
                    zoneOutline(projection)
                    placementCells(projection)
                }
                .frame(width: projection.boardSize.width, height: projection.boardSize.height)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private func enemyFigures(_ projection: BoardProjection) -> some View {
        ForEach(Array(model.enemyPlacements.enumerated()), id: \.offset) { _, enemy in
            let (column, row) = model.map.coordinates(ofCell: enemy.cell)
            let rect = projection.viewRect(column: column, row: row)
            // The enemy faces down the table, toward the player (D26).
            UnitToken(type: enemy.type, team: .enemy, size: .onTable(cellSize: projection.pointsPerCell))
                .rotationEffect(.degrees(180))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    /// The deployment zone, marked out in dashed brass (design mock) and named on a dark slip so the
    /// words read on any patch of sand.
    private func zoneOutline(_ projection: BoardProjection) -> some View {
        let zone = zoneRect(projection)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.brass.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: zone.width, height: zone.height)
                .offset(x: zone.minX, y: zone.minY)
            Text(model.placements.isEmpty ? emptyZoneHint : String(localized: "senin konuşlanma bölgen"))
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper)
                .padding(.horizontal, FermanSpacing.xs)
                .padding(.vertical, 2)
                .background(Color.ink.opacity(0.85), in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
                .offset(x: zone.minX + 4, y: max(0, zone.minY - 22))
        }
        .allowsHitTesting(false)
    }

    private var emptyZoneHint: String {
        model.chosenTrayUnit == nil
            ? String(localized: "Tepsiden bir birim seç ya da sürükle.")
            : String(localized: "Bölgende bir kareye dokun.")
    }

    private func zoneRect(_ projection: BoardProjection) -> CGRect {
        let corner = projection.viewRect(column: model.gridColumns.upperBound, row: model.gridRows.lowerBound)
        let opposite = projection.viewRect(column: model.gridColumns.lowerBound, row: model.gridRows.upperBound)
        return corner.union(opposite)
    }

    private func placementCells(_ projection: BoardProjection) -> some View {
        ForEach(model.map.zone(for: .player), id: \.self) { cell in
            let (column, row) = model.map.coordinates(ofCell: cell)
            let rect = projection.viewRect(column: column, row: row)
            PlacementSlotView(
                model: model, cell: cell, cellSize: projection.pointsPerCell,
                accessibilityLabel: accessibilityLabel(forCell: cell)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }

    private func accessibilityLabel(forCell cell: Int) -> String {
        guard let placement = model.placement(at: cell) else {
            return String(localized: "Boş hücre")
        }
        let name = OrderPhraseFormatter.unitTypeName(placement.unitType)
        return placement.isCommander ? String(localized: "\(name), komutan") : name
    }

    // MARK: - Tray

    private var unitTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FermanSpacing.lg) {
                ForEach(model.catalog, id: \.id) { unitType in
                    let isChosen = model.chosenTrayUnit == unitType.id
                    // The whole card is the drag source and the tap target, not just the figure — a
                    // small figure was a hard-to-hit handle on its own (found via a real playtest,
                    // F1.14).
                    VStack(spacing: FermanSpacing.xxs) {
                        UnitToken(type: unitType.id, size: .tray, isSelected: isChosen)
                        Text(OrderPhraseFormatter.unitTypeName(unitType.id))
                            .font(isChosen ? FermanFont.tabSelected() : FermanFont.caption())
                            .foregroundStyle(Color.paper)
                        Text(String(localized: "\(unitType.cost)p"))
                            .font(FermanFont.counter(size: 12))
                            .foregroundStyle(Color.paper.opacity(0.75))
                    }
                    .padding(FermanSpacing.xs)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(isChosen ? Color.brass : .clear).frame(height: 2)
                    }
                    // Still draggable when it doesn't fit — the drop is refused with a warning haptic
                    // (`PlacementSlotView`) — but dimmed so the player sees why before trying.
                    .opacity(model.canAfford(unitType.id) ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { model.chooseTrayUnit(unitType.id) }
                    .draggable(unitType.id.rawValue)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "\(OrderPhraseFormatter.unitTypeName(unitType.id)), \(unitType.cost) puan")
                    )
                    .accessibilityHint(model.canAfford(unitType.id) ? "" : String(localized: "Bütçe yetmiyor."))
                    .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(FermanSpacing.md)
        }
        .background(Color.slateRaised)
    }
}

/// One cell of the deployment zone. Its own view so it can own the `isTargeted` highlight — the only
/// feedback a player gets, while their finger is still down, that a cell will take the drop (found
/// missing via a real playtest, F1.14).
private struct PlacementSlotView: View {
    let model: ArmySetupModel
    let cell: Int
    let cellSize: CGFloat
    let accessibilityLabel: String

    @State private var isTargeted = false
    @State private var refusedDrops = 0

    private static let movePrefix = "move:"

    private var placement: ArmyPlacement? { model.placement(at: cell) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fill)
            Rectangle()
                .strokeBorder(isTargeted ? Color.brass : Color.paper.opacity(0.12), lineWidth: isTargeted ? 2 : 0.5)
            if let placement {
                placedUnitView(placement)
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.35), value: placement?.id)
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.tapCell(cell), placement == nil, model.chosenTrayUnit != nil {
                refusedDrops += 1
            }
        }
        .dropDestination(for: String.self, isEnabled: placement == nil) { payloads, session in
            switch session.phase {
            case .entering, .active:
                isTargeted = true
            default:
                isTargeted = false
            }
            guard let payload = payloads.first else { return }
            let placed: Bool
            if payload.hasPrefix(Self.movePrefix), let id = UUID(uuidString: String(payload.dropFirst(Self.movePrefix.count))) {
                placed = model.move(id, to: cell)
            } else {
                placed = model.place(UnitTypeID(rawValue: payload), at: cell)
            }
            if !placed { refusedDrops += 1 }
        }
        .sensoryFeedback(.warning, trigger: refusedDrops)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// A drop target lights brass; with a tray unit in hand, every free cell hints it can take it.
    private var fill: Color {
        if isTargeted { return Color.brass.opacity(0.28) }
        if placement == nil, model.chosenTrayUnit != nil { return Color.brass.opacity(0.1) }
        return .clear
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
        .frame(width: cellSize, height: cellSize)
        .draggable("\(Self.movePrefix)\(placement.id.uuidString)")
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
