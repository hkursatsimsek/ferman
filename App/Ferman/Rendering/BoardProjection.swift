import CoreGraphics
import FermanCore

/// The one place where simulation space becomes screen space (D26), for SpriteKit and SwiftUI alike.
///
/// A map is authored landscape — the player's zone on the left of its ASCII rows, the enemy's on the
/// right — but a phone is held upright, so the board is drawn a quarter turn counter-clockwise from
/// that layout: the player's zone at the bottom, the enemy's at the top, ASCII row 0 on the left.
/// It's a rotation, not a mirror, so a unit's left stays on its left on screen.
///
/// Simulation space is cells, x = column, y = row (`BattleMap.center(ofCell:)`). `nonisolated`: pure
/// geometry, usable from an off-main renderer (`ClipRenderer`, D15) as much as from a view.
nonisolated struct BoardProjection: Sendable, Equatable {
    /// `BattleScene`'s own coordinate scale; SpriteKit fits the scene to the view from there.
    static let scenePointsPerCell: CGFloat = 32

    /// The map's column count — sim x, which runs bottom to top on screen.
    let mapWidth: Int
    /// The map's row count — sim y, which runs left to right on screen.
    let mapHeight: Int
    let pointsPerCell: CGFloat

    init(mapWidth: Int, mapHeight: Int, pointsPerCell: CGFloat = Self.scenePointsPerCell) {
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.pointsPerCell = pointsPerCell
    }

    init(map: BattleMap, pointsPerCell: CGFloat = Self.scenePointsPerCell) {
        self.init(mapWidth: map.width, mapHeight: map.height, pointsPerCell: pointsPerCell)
    }

    /// The same board at another scale — e.g. a SwiftUI grid sized to its container.
    func scaled(toPointsPerCell pointsPerCell: CGFloat) -> BoardProjection {
        BoardProjection(mapWidth: mapWidth, mapHeight: mapHeight, pointsPerCell: pointsPerCell)
    }

    /// On-screen size: the map's rows across, its columns up.
    var boardSize: CGSize {
        CGSize(width: CGFloat(mapHeight) * pointsPerCell, height: CGFloat(mapWidth) * pointsPerCell)
    }

    /// Width over height, for `aspectRatio(_:contentMode:)`.
    var aspectRatio: CGFloat {
        CGFloat(mapHeight) / CGFloat(mapWidth)
    }

    // MARK: - SpriteKit (origin bottom-left, y up)

    func scenePoint(_ position: FixedVector2) -> CGPoint {
        CGPoint(x: position.y.cells * pointsPerCell, y: position.x.cells * pointsPerCell)
    }

    // MARK: - SwiftUI (origin top-left, y down)

    func viewPoint(_ position: FixedVector2) -> CGPoint {
        CGPoint(x: position.y.cells * pointsPerCell, y: (CGFloat(mapWidth) - position.x.cells) * pointsPerCell)
    }

    func viewRect(column: Int, row: Int) -> CGRect {
        CGRect(
            x: CGFloat(row) * pointsPerCell, y: CGFloat(mapWidth - 1 - column) * pointsPerCell,
            width: pointsPerCell, height: pointsPerCell)
    }

    func cell(atViewPoint point: CGPoint) -> (column: Int, row: Int)? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let row = Int(point.x / pointsPerCell)
        let column = mapWidth - 1 - Int(point.y / pointsPerCell)
        guard (0..<mapWidth).contains(column), (0..<mapHeight).contains(row) else { return nil }
        return (column, row)
    }

    /// The cells of a sub-rectangle (say, a deployment zone's bounds) in screen reading order: one
    /// array per on-screen row, top to bottom, each left to right — what a SwiftUI `VStack` of
    /// `HStack`s lays out.
    func screenRows(columns: ClosedRange<Int>, rows: ClosedRange<Int>) -> [[(column: Int, row: Int)]] {
        columns.reversed().map { column in
            rows.map { row in (column, row) }
        }
    }
}
