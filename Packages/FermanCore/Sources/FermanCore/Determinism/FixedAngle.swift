/// An angle in binary angle units: one full turn is 4096 units, measured counterclockwise from +x.
///
/// Arithmetic wraps modulo a full turn, exactly like the angle it represents, so no normalisation step can drift.
public struct FixedAngle: Sendable, Hashable {
    public static let unitsPerTurn: Int32 = 4096
    static let unitsPerQuarterTurn: Int32 = 1024

    public private(set) var raw: Int32

    public init(raw: Int32) {
        self.raw = raw & (Self.unitsPerTurn - 1)
    }

    public static let zero = FixedAngle(raw: 0)
    public static let quarterTurn = FixedAngle(raw: unitsPerQuarterTurn)
    public static let halfTurn = FixedAngle(raw: 2 * unitsPerQuarterTurn)
    public static let threeQuarterTurn = FixedAngle(raw: 3 * unitsPerQuarterTurn)

    public static func + (lhs: FixedAngle, rhs: FixedAngle) -> FixedAngle {
        FixedAngle(raw: lhs.raw &+ rhs.raw)
    }

    public static func - (lhs: FixedAngle, rhs: FixedAngle) -> FixedAngle {
        FixedAngle(raw: lhs.raw &- rhs.raw)
    }

    public static prefix func - (operand: FixedAngle) -> FixedAngle {
        FixedAngle(raw: 0 &- operand.raw)
    }
}

extension FixedAngle: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(raw: try Int32(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }
}
