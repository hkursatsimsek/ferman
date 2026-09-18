import CoreGraphics
import FermanCore

/// Where `Fixed` values become `CGFloat` — nowhere else in the render layer (CLAUDE.md rule 2).
/// Placing that value on screen is `BoardProjection`'s job.
nonisolated extension Fixed {
    /// This value in cells, as a float for drawing.
    var cells: CGFloat {
        CGFloat(raw) / CGFloat(1 << Self.fractionBits)
    }
}

nonisolated extension CGPoint {
    func interpolated(to other: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }
}
