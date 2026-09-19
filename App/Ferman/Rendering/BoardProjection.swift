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
    /// The table's rim around the playing field, in cells: room for a figure on an edge cell to show
    /// its whole base and weapon instead of being cut by the view's edge.
    let rimCells: CGFloat

    init(mapWidth: Int, mapHeight: Int, pointsPerCell: CGFloat = Self.scenePointsPerCell, rimCells: CGFloat = 0) {
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.pointsPerCell = pointsPerCell
        self.rimCells = rimCells
    }

    init(map: BattleMap, pointsPerCell: CGFloat = Self.scenePointsPerCell, rimCells: CGFloat = 0) {
        self.init(mapWidth: map.width, mapHeight: map.height, pointsPerCell: pointsPerCell, rimCells: rimCells)
    }

    /// The sand table as the battle and army setup draw it: scene scale, with a rim.
    static func table(for map: BattleMap) -> BoardProjection {
        BoardProjection(map: map, rimCells: 0.75)
    }

    /// The same board at another scale — e.g. a SwiftUI grid sized to its container.
    func scaled(toPointsPerCell pointsPerCell: CGFloat) -> BoardProjection {
        BoardProjection(mapWidth: mapWidth, mapHeight: mapHeight, pointsPerCell: pointsPerCell, rimCells: rimCells)
    }

    private var rim: CGFloat { rimCells * pointsPerCell }

    /// On-screen size, rim included: the map's rows across, its columns up.
    var boardSize: CGSize {
        CGSize(
            width: CGFloat(mapHeight) * pointsPerCell + 2 * rim, height: CGFloat(mapWidth) * pointsPerCell + 2 * rim)
    }

    /// The playing field inside the rim, in SwiftUI coordinates (identical in SpriteKit's: it's centred).
    var fieldRect: CGRect {
        CGRect(
            x: rim, y: rim, width: CGFloat(mapHeight) * pointsPerCell, height: CGFloat(mapWidth) * pointsPerCell)
    }

    /// Width over height, for `aspectRatio(_:contentMode:)`.
    var aspectRatio: CGFloat {
        boardSize.width / boardSize.height
    }

    // MARK: - The lamp

    /// Where the one lamp hangs (brief §3.1): a little above the field's centre on screen. The sand's
    /// light falls off from here, and every contact shadow on the table is cast away from it.
    var lampViewPoint: CGPoint {
        CGPoint(x: fieldRect.midX, y: fieldRect.minY + fieldRect.height * 0.34)
    }

    var lampScenePoint: CGPoint {
        CGPoint(x: lampViewPoint.x, y: boardSize.height - lampViewPoint.y)
    }

    /// How far a contact shadow falls from what casts it, at a scene point: `near` right under the lamp,
    /// growing to `far` at the table's farthest corner (ART-DIRECTION §3, 1.5–3 pt on screen).
    func shadowOffset(atScenePoint point: CGPoint, near: CGFloat = 2, far: CGFloat = 4) -> CGVector {
        let lamp = lampScenePoint
        let away = CGVector(dx: point.x - lamp.x, dy: point.y - lamp.y)
        let distance = hypot(away.dx, away.dy)
        let reach = max(hypot(max(lamp.x, boardSize.width - lamp.x), max(lamp.y, boardSize.height - lamp.y)), 1)
        let length = near + (far - near) * min(1, distance / reach)
        // Right under the lamp the shadow still has to go somewhere: down the table, like the rest.
        guard distance > 0.5 else { return CGVector(dx: 0, dy: -length) }
        return CGVector(dx: away.dx / distance * length, dy: away.dy / distance * length)
    }

    // MARK: - SpriteKit (origin bottom-left, y up)

    func scenePoint(_ position: FixedVector2) -> CGPoint {
        CGPoint(x: rim + position.y.cells * pointsPerCell, y: rim + position.x.cells * pointsPerCell)
    }

    // MARK: - SwiftUI (origin top-left, y down)

    func viewPoint(_ position: FixedVector2) -> CGPoint {
        CGPoint(
            x: rim + position.y.cells * pointsPerCell,
            y: rim + (CGFloat(mapWidth) - position.x.cells) * pointsPerCell)
    }

    func viewRect(column: Int, row: Int) -> CGRect {
        CGRect(
            x: rim + CGFloat(row) * pointsPerCell, y: rim + CGFloat(mapWidth - 1 - column) * pointsPerCell,
            width: pointsPerCell, height: pointsPerCell)
    }

    func cell(atViewPoint point: CGPoint) -> (column: Int, row: Int)? {
        let local = CGPoint(x: point.x - rim, y: point.y - rim)
        guard local.x >= 0, local.y >= 0 else { return nil }
        let row = Int(local.x / pointsPerCell)
        let column = mapWidth - 1 - Int(local.y / pointsPerCell)
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
