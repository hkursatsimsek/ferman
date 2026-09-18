import FermanCore
import SwiftUI

/// OrduKurulumu (design brief §4.3). Only the player's zone is on the table; the tray below it is
/// the drag source, the grid is the drop destination — both plain `String` payloads (a unit type's
/// raw id), so dragging a unit needs no custom `Transferable` type or exported UTType.
struct ArmySetupView: View {
    @State var model: ArmySetupModel

    var body: some View {
        VStack(spacing: 0) {
            header
            placementGrid
                .frame(maxHeight: .infinity)
            unitTray
        }
        .background(Color.ink)
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

    private var placementGrid: some View {
        let columns = Array(model.gridColumns)
        let rows = Array(model.gridRows)
        return GeometryReader { proxy in
            let cellSize = min(proxy.size.width / CGFloat(columns.count), proxy.size.height / CGFloat(rows.count))
            ZStack {
                SandTable()
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.self) { column in
                                cellView(column: column, row: row)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .frame(width: cellSize * CGFloat(columns.count), height: cellSize * CGFloat(rows.count))
            }
        }
    }

    @ViewBuilder
    private func cellView(column: Int, row: Int) -> some View {
        if let cell = model.map.cellIndex(column: column, row: row), model.isPlayerZone(cell) {
            placementSlot(cell: cell)
        } else {
            Color.clear
        }
    }

    private func placementSlot(cell: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.paper.opacity(0.18), lineWidth: 1)
            if let placement = model.placement(at: cell) {
                placedUnitView(placement)
            }
        }
        .padding(2)
        .dropDestination(for: String.self, isEnabled: model.placement(at: cell) == nil) { droppedIDs, _ in
            guard let rawUnitType = droppedIDs.first else { return }
            model.place(UnitTypeID(rawValue: rawUnitType), at: cell)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(forCell: cell))
    }

    private func accessibilityLabel(forCell cell: Int) -> String {
        guard let placement = model.placement(at: cell) else {
            return String(localized: "Boş hücre")
        }
        let name = OrderPhraseFormatter.unitTypeName(placement.unitType)
        return placement.isCommander ? String(localized: "\(name), komutan") : name
    }

    @ViewBuilder
    private func placedUnitView(_ placement: ArmyPlacement) -> some View {
        ZStack(alignment: .topTrailing) {
            UnitToken(team: .brass, size: .table, isSelected: model.selectedPlacementID == placement.id)
            if placement.isCommander {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.brass)
                    .offset(x: 3, y: -3)
            }
        }
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

    private var unitTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FermanSpacing.lg) {
                ForEach(model.catalog, id: \.id) { unitType in
                    VStack(spacing: FermanSpacing.xxs) {
                        UnitToken(team: .brass, size: .tray)
                            .draggable(unitType.id.rawValue)
                        Text(OrderPhraseFormatter.unitTypeName(unitType.id))
                            .font(FermanFont.caption())
                            .foregroundStyle(Color.paper)
                        Text(String(localized: "\(unitType.cost)p"))
                            .font(FermanFont.counter(size: 12))
                            .foregroundStyle(Color.paper.opacity(0.75))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "\(OrderPhraseFormatter.unitTypeName(unitType.id)), \(unitType.cost) puan")
                    )
                }
            }
            .padding(FermanSpacing.md)
        }
        .background(Color.slateRaised)
    }
}
