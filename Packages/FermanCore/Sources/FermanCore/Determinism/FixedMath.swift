/// Trigonometry and roots over fixed-point values, backed by generated integer tables.
///
/// Platform `sin`/`atan2` results differ between libm implementations, so the simulation never calls them. The
/// tables in `FixedMathTables.swift` are produced once by `fermansim gen-tables` and committed as literals.
///
/// Only the first quadrant is tabulated and the others are derived by reflection. Beyond saving space, this makes
/// identities such as `sin(-a) == -sin(a)` and `sin(halfTurn - a) == sin(a)` exact by construction, which keeps
/// mirrored formations on both teams behaving identically.
public enum FixedMath {
    static let tableResolution = Int(FixedAngle.unitsPerQuarterTurn)

    public static func sin(_ angle: FixedAngle) -> Fixed {
        let quadrant = angle.raw >> 10
        let offset = Int(angle.raw & (FixedAngle.unitsPerQuarterTurn - 1))
        switch quadrant {
        case 0:
            return Fixed(raw: quarterSineTable[offset])
        case 1:
            return Fixed(raw: quarterSineTable[tableResolution - offset])
        case 2:
            return Fixed(raw: -quarterSineTable[offset])
        default:
            return Fixed(raw: -quarterSineTable[tableResolution - offset])
        }
    }

    public static func cos(_ angle: FixedAngle) -> Fixed {
        Self.sin(angle + .quarterTurn)
    }

    /// The unit vector pointing along `angle`.
    public static func direction(_ angle: FixedAngle) -> FixedVector2 {
        FixedVector2(x: Self.cos(angle), y: Self.sin(angle))
    }

    /// The angle of the vector `(x, y)`; the zero vector maps to `.zero`.
    public static func atan2(y: Fixed, x: Fixed) -> FixedAngle {
        let absoluteX = Int64(x.raw).magnitude
        let absoluteY = Int64(y.raw).magnitude
        guard absoluteX != 0 || absoluteY != 0 else {
            return .zero
        }

        let resolution = UInt64(tableResolution)
        let firstQuadrantAngle: Int32
        if absoluteY <= absoluteX {
            let index = (absoluteY * resolution + absoluteX / 2) / absoluteX
            firstQuadrantAngle = arctangentTable[Int(index)]
        } else {
            let index = (absoluteX * resolution + absoluteY / 2) / absoluteY
            firstQuadrantAngle = FixedAngle.unitsPerQuarterTurn - arctangentTable[Int(index)]
        }

        switch (x.raw >= 0, y.raw >= 0) {
        case (true, true):
            return FixedAngle(raw: firstQuadrantAngle)
        case (false, true):
            return FixedAngle(raw: 2 * FixedAngle.unitsPerQuarterTurn - firstQuadrantAngle)
        case (false, false):
            return FixedAngle(raw: 2 * FixedAngle.unitsPerQuarterTurn + firstQuadrantAngle)
        case (true, false):
            return FixedAngle(raw: FixedAngle.unitsPerTurn - firstQuadrantAngle)
        }
    }

    /// The integer square root ⌊√value⌋, by the digit-by-digit method.
    public static func isqrt(_ value: UInt64) -> UInt64 {
        var remainder = value
        var root: UInt64 = 0
        var bit: UInt64 = 1 << 62
        while bit > remainder {
            bit >>= 2
        }
        while bit != 0 {
            if remainder >= root + bit {
                remainder -= root + bit
                root = (root >> 1) + bit
            } else {
                root >>= 1
            }
            bit >>= 2
        }
        return root
    }

    /// √value rounded to the nearest integer.
    static func roundedSquareRoot(_ value: UInt64) -> UInt64 {
        let root = isqrt(value)
        // (root + ½)² = root² + root + ¼, so the true root is nearer root + 1 exactly when value − root² > root.
        return value - root * root > root ? root + 1 : root
    }
}
