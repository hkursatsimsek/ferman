import CoreGraphics
import FermanCore

/// Where `Fixed` values become `CGFloat` — nowhere else in the render layer (CLAUDE.md rule 2).
enum SceneScale {
    /// Points per simulation cell.
    static let pointsPerCell: CGFloat = 32
}

extension Fixed {
    var scenePoints: CGFloat {
        CGFloat(raw) / CGFloat(1 << Self.fractionBits) * SceneScale.pointsPerCell
    }
}

extension FixedVector2 {
    var scenePoint: CGPoint {
        CGPoint(x: x.scenePoints, y: y.scenePoints)
    }
}

extension CGPoint {
    func interpolated(to other: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }
}
