import CoreGraphics
import FermanCore
import Testing

@testable import Ferman

/// D26: the board is the ASCII map turned a quarter counter-clockwise — player zone (left columns)
/// at the bottom, enemy (right columns) at the top, ASCII row 0 on the left — in both coordinate
/// systems the app draws in.
struct BoardProjectionTests {
    /// The shipped maps' shape (F0.5, F1.12): 24 columns, 14 rows.
    private let projection = BoardProjection(mapWidth: 24, mapHeight: 14, pointsPerCell: 32)

    private func center(column: Int, row: Int) -> FixedVector2 {
        FixedVector2(x: Fixed(column) + .half, y: Fixed(row) + .half)
    }

    @Test
    func theBoardStandsUpright() {
        #expect(projection.boardSize == CGSize(width: 14 * 32, height: 24 * 32))
        #expect(abs(projection.aspectRatio - 14.0 / 24.0) < 0.0001)
    }

    @Test
    func thePlayerZoneIsAtTheBottomAndTheEnemyZoneAtTheTop() {
        let player = center(column: 0, row: 7)
        let enemy = center(column: 23, row: 7)

        // SpriteKit: y grows upward.
        #expect(projection.scenePoint(player).y < 32)
        #expect(projection.scenePoint(enemy).y > projection.boardSize.height - 32)
        // SwiftUI: y grows downward.
        #expect(projection.viewPoint(player).y > projection.boardSize.height - 32)
        #expect(projection.viewPoint(enemy).y < 32)
    }

    @Test
    func asciiRowZeroIsOnTheLeft() {
        #expect(projection.scenePoint(center(column: 5, row: 0)).x < 32)
        #expect(projection.viewPoint(center(column: 5, row: 0)).x < 32)
        #expect(projection.viewPoint(center(column: 5, row: 13)).x > projection.boardSize.width - 32)
    }

    /// A quarter turn keeps orientation: going from the player's side toward the enemy (screen up)
    /// with ASCII row 0 on the left is the ASCII picture rotated, not flipped.
    @Test
    func itIsARotationNotAMirror() {
        let origin = projection.viewPoint(center(column: 0, row: 0))
        let towardEnemy = projection.viewPoint(center(column: 1, row: 0))
        let towardLastRow = projection.viewPoint(center(column: 0, row: 1))

        // ASCII: +column is right, +row is down. Rotated counter-clockwise: right → up, down → right.
        #expect(towardEnemy.y < origin.y && towardEnemy.x == origin.x)
        #expect(towardLastRow.x > origin.x && towardLastRow.y == origin.y)
    }

    @Test
    func sceneAndViewPointsAreTheSamePlaceFlippedVertically() {
        for column in [0, 7, 23] {
            for row in [0, 5, 13] {
                let scene = projection.scenePoint(center(column: column, row: row))
                let view = projection.viewPoint(center(column: column, row: row))
                #expect(scene.x == view.x)
                #expect(scene.y == projection.boardSize.height - view.y)
            }
        }
    }

    @Test
    func aCellsViewRectContainsItsCenterAndMapsBack() {
        for column in [0, 11, 23] {
            for row in [0, 6, 13] {
                let rect = projection.viewRect(column: column, row: row)
                #expect(rect.contains(projection.viewPoint(center(column: column, row: row))))
                let cell = projection.cell(atViewPoint: CGPoint(x: rect.midX, y: rect.midY))
                #expect(cell?.column == column && cell?.row == row)
            }
        }
    }

    @Test
    func pointsOffTheBoardHaveNoCell() {
        #expect(projection.cell(atViewPoint: CGPoint(x: -1, y: 10)) == nil)
        #expect(projection.cell(atViewPoint: CGPoint(x: 10, y: projection.boardSize.height + 1)) == nil)
        #expect(projection.cell(atViewPoint: CGPoint(x: projection.boardSize.width + 1, y: 10)) == nil)
    }

    @Test
    func screenRowsReadTopToBottomLeftToRight() {
        // A 3-column deployment zone: its farthest column (toward the enemy) is the top screen row.
        let rows = projection.screenRows(columns: 0...2, rows: 0...3)

        #expect(rows.map { $0.first?.column } == [2, 1, 0])
        #expect(rows.allSatisfy { $0.map(\.row) == [0, 1, 2, 3] })
    }

    @Test
    func aRimOffsetsTheFieldAndGrowsTheBoard() {
        let rimmed = BoardProjection(mapWidth: 24, mapHeight: 14, pointsPerCell: 32, rimCells: 0.5)

        #expect(rimmed.boardSize == CGSize(width: 14 * 32 + 32, height: 24 * 32 + 32))
        #expect(rimmed.fieldRect == CGRect(x: 16, y: 16, width: 14 * 32, height: 24 * 32))
        let cornerCell = center(column: 23, row: 0)
        #expect(rimmed.scenePoint(cornerCell) == CGPoint(x: 16 + 16, y: 16 + 23.5 * 32))
        #expect(rimmed.viewPoint(cornerCell) == CGPoint(x: 16 + 16, y: 16 + 16))
        // The rim itself belongs to no cell.
        #expect(rimmed.cell(atViewPoint: CGPoint(x: 8, y: 100)) == nil)
        let rect = rimmed.viewRect(column: 4, row: 9)
        let cell = rimmed.cell(atViewPoint: CGPoint(x: rect.midX, y: rect.midY))
        #expect(cell?.column == 4 && cell?.row == 9)
    }

    @Test
    func scalingKeepsTheShape() {
        let small = projection.scaled(toPointsPerCell: 16)
        #expect(small.boardSize == CGSize(width: 14 * 16, height: 24 * 16))
        #expect(small.aspectRatio == projection.aspectRatio)
    }
}
