public struct FixedVector2: Sendable, Hashable, Codable {
    public var x: Fixed
    public var y: Fixed

    public init(x: Fixed, y: Fixed) {
        self.x = x
        self.y = y
    }

    public static let zero = FixedVector2(x: .zero, y: .zero)

    public var lengthSquared: FixedSquared {
        x.squared + y.squared
    }

    public var length: Fixed {
        lengthSquared.squareRoot()
    }

    public func distanceSquared(to other: FixedVector2) -> FixedSquared {
        (other - self).lengthSquared
    }

    /// The Q16.16 dot product. The full-width sum is rounded once, so the result stays symmetric under negation.
    public func dot(_ other: FixedVector2) -> Fixed {
        let sum = Int64(x.raw) * Int64(other.x.raw) + Int64(y.raw) * Int64(other.y.raw)
        return Fixed(raw: Int32(Fixed.roundedShiftRight(sum, by: Int64(Fixed.fractionBits))))
    }

    /// A unit-length vector in the same direction; the zero vector stays zero.
    public func normalized() -> FixedVector2 {
        let length = length
        guard length != .zero else {
            return .zero
        }
        return FixedVector2(x: x / length, y: y / length)
    }

    public static func + (lhs: FixedVector2, rhs: FixedVector2) -> FixedVector2 {
        FixedVector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: FixedVector2, rhs: FixedVector2) -> FixedVector2 {
        FixedVector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static prefix func - (operand: FixedVector2) -> FixedVector2 {
        FixedVector2(x: -operand.x, y: -operand.y)
    }

    public static func * (lhs: FixedVector2, rhs: Fixed) -> FixedVector2 {
        FixedVector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func * (lhs: Fixed, rhs: FixedVector2) -> FixedVector2 {
        rhs * lhs
    }

    public static func / (lhs: FixedVector2, rhs: Fixed) -> FixedVector2 {
        FixedVector2(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    public static func * (lhs: FixedVector2, rhs: Int) -> FixedVector2 {
        FixedVector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: FixedVector2, rhs: Int) -> FixedVector2 {
        FixedVector2(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    public static func += (lhs: inout FixedVector2, rhs: FixedVector2) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout FixedVector2, rhs: FixedVector2) {
        lhs = lhs - rhs
    }
}

extension FixedVector2: CustomStringConvertible {
    public var description: String {
        "(\(x), \(y))"
    }
}
