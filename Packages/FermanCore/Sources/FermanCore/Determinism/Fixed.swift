/// A signed Q16.16 fixed-point number: the only fractional numeric type the simulation uses (D2).
///
/// Rounding: multiplication, division and square roots round to the nearest representable value with ties away
/// from zero. The rule is symmetric under negation, so a unit moving left covers exactly the distance of a unit
/// moving right; flooring would give one side of the battlefield a systematic drift.
///
/// Overflow: every operation traps when its result leaves the Q16.16 range, in debug and release builds alike.
/// Inputs that could overflow (map sizes, speeds, ranges) are bounded by the content and config validators, so a
/// trap always indicates a programming error rather than a legitimate battle.
public struct Fixed: Sendable, Hashable {
    public static let fractionBits = 16
    static let scale: Int64 = 1 << 16

    public var raw: Int32

    public init(raw: Int32) {
        self.raw = raw
    }

    public init(_ integer: Int) {
        raw = Int32(Int64(integer) * Self.scale)
    }

    /// `numerator / denominator`, rounded to the nearest representable value.
    public init(numerator: Int, denominator: Int) {
        let (scaled, overflow) = Int64(numerator).multipliedReportingOverflow(by: Self.scale)
        precondition(!overflow, "Fixed(numerator: \(numerator), denominator: \(denominator)) overflows")
        raw = Int32(Self.roundedDivision(scaled, by: Int64(denominator)))
    }

    public static let zero = Fixed(raw: 0)
    public static let one = Fixed(raw: 1 << 16)
    public static let half = Fixed(raw: 1 << 15)
    public static let min = Fixed(raw: .min)
    public static let max = Fixed(raw: .max)

    public var magnitude: Fixed {
        Fixed(raw: raw < 0 ? -raw : raw)
    }

    /// The largest integer less than or equal to the value.
    public func roundedDown() -> Int {
        Int(raw >> Int32(Self.fractionBits))
    }

    /// The nearest integer, ties away from zero.
    public func rounded() -> Int {
        Int(Self.roundedShiftRight(Int64(raw), by: Int64(Self.fractionBits)))
    }

    public func squareRoot() -> Fixed {
        precondition(raw >= 0, "square root of negative Fixed \(self)")
        let radicand = UInt64(raw) << UInt64(Self.fractionBits)
        return Fixed(raw: Int32(FixedMath.roundedSquareRoot(radicand)))
    }

    public func clamped(to range: ClosedRange<Fixed>) -> Fixed {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    public var squared: FixedSquared {
        FixedSquared(raw: Int64(raw) * Int64(raw))
    }

    static func roundedShiftRight(_ value: Int64, by bits: Int64) -> Int64 {
        let half: Int64 = 1 << (bits - 1)
        return value >= 0 ? (value + half) >> bits : -((-value + half) >> bits)
    }

    static func roundedDivision(_ numerator: Int64, by denominator: Int64) -> Int64 {
        precondition(denominator != 0, "Fixed division by zero")
        let divisor = denominator.magnitude
        let quotient = Int64((numerator.magnitude + divisor / 2) / divisor)
        return (numerator < 0) != (denominator < 0) ? -quotient : quotient
    }
}

extension Fixed: Comparable {
    public static func < (lhs: Fixed, rhs: Fixed) -> Bool {
        lhs.raw < rhs.raw
    }
}

extension Fixed: AdditiveArithmetic {
    public static func + (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(raw: lhs.raw + rhs.raw)
    }

    public static func - (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(raw: lhs.raw - rhs.raw)
    }
}

extension Fixed {
    public static prefix func - (operand: Fixed) -> Fixed {
        Fixed(raw: -operand.raw)
    }

    public static func * (lhs: Fixed, rhs: Fixed) -> Fixed {
        let product = Int64(lhs.raw) * Int64(rhs.raw)
        return Fixed(raw: Int32(roundedShiftRight(product, by: Int64(fractionBits))))
    }

    public static func / (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(raw: Int32(roundedDivision(Int64(lhs.raw) * scale, by: Int64(rhs.raw))))
    }

    public static func * (lhs: Fixed, rhs: Int) -> Fixed {
        Fixed(raw: Int32(Int64(lhs.raw) * Int64(rhs)))
    }

    public static func * (lhs: Int, rhs: Fixed) -> Fixed {
        rhs * lhs
    }

    public static func / (lhs: Fixed, rhs: Int) -> Fixed {
        Fixed(raw: Int32(roundedDivision(Int64(lhs.raw), by: Int64(rhs))))
    }

    public static func *= (lhs: inout Fixed, rhs: Fixed) {
        lhs = lhs * rhs
    }

    public static func /= (lhs: inout Fixed, rhs: Fixed) {
        lhs = lhs / rhs
    }

    public static func *= (lhs: inout Fixed, rhs: Int) {
        lhs = lhs * rhs
    }

    public static func /= (lhs: inout Fixed, rhs: Int) {
        lhs = lhs / rhs
    }
}

extension Fixed: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension Fixed: Codable {
    public init(from decoder: any Decoder) throws {
        raw = try Int32(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }
}

extension Fixed: CustomStringConvertible {
    /// Decimal rendering rounded to five fractional digits, computed without floating point.
    ///
    /// The largest fraction, 65535/65536, rounds to 0.99998, so rounding never carries into the whole part.
    public var description: String {
        let magnitude = Int64(raw).magnitude
        let whole = magnitude >> UInt64(Self.fractionBits)
        let fraction = ((magnitude & 0xFFFF) * 100_000 + (1 << 15)) >> UInt64(Self.fractionBits)
        let sign = raw < 0 ? "-" : ""
        guard fraction != 0 else {
            return "\(sign)\(whole)"
        }
        var digits = String(fraction)
        digits = String(repeating: "0", count: 5 - digits.count) + digits
        while digits.last == "0" {
            digits.removeLast()
        }
        return "\(sign)\(whole).\(digits)"
    }
}

/// A Q32.32 quantity holding squared lengths, which outgrow the Q16.16 range on larger maps.
///
/// Distance checks compare squared values so the hot path never takes a square root.
public struct FixedSquared: Sendable, Hashable, Comparable {
    public var raw: Int64

    public init(raw: Int64) {
        self.raw = raw
    }

    public static func < (lhs: FixedSquared, rhs: FixedSquared) -> Bool {
        lhs.raw < rhs.raw
    }

    public static func + (lhs: FixedSquared, rhs: FixedSquared) -> FixedSquared {
        FixedSquared(raw: lhs.raw + rhs.raw)
    }

    /// The Q16.16 square root, rounded to nearest.
    public func squareRoot() -> Fixed {
        precondition(raw >= 0, "square root of negative FixedSquared")
        return Fixed(raw: Int32(FixedMath.roundedSquareRoot(UInt64(raw))))
    }
}
