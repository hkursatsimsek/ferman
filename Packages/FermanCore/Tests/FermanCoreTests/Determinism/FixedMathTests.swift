import Foundation
import Testing

@testable import FermanCore

@Suite("FixedMath")
struct FixedMathTests {
    private static let allAngles = (0..<FixedAngle.unitsPerTurn).map { FixedAngle(raw: $0) }

    private static func radians(_ angle: FixedAngle) -> Double {
        Double(angle.raw) / Double(FixedAngle.unitsPerTurn) * 2 * Double.pi
    }

    /// Any change to the committed tables changes simulation results, so it must be deliberate and bump
    /// `simulationVersion`; accuracy itself is covered by the platform comparison tests below.
    @Test func tablesHaveTheirPinnedChecksum() {
        var checksum = FNV1a64()
        for value in FixedMath.quarterSineTable {
            checksum.combine(value)
        }
        for value in FixedMath.arctangentTable {
            checksum.combine(value)
        }
        #expect(FixedMath.quarterSineTable.count == 1_025)
        #expect(FixedMath.arctangentTable.count == 1_025)
        #expect(checksum.value == 0x3433_aca7_cfbb_c2ff, "0x\(String(checksum.value, radix: 16))")
    }

    @Test func cardinalAnglesAreExact() {
        #expect(FixedMath.sin(.zero) == .zero)
        #expect(FixedMath.cos(.zero) == .one)
        #expect(FixedMath.sin(.quarterTurn) == .one)
        #expect(FixedMath.cos(.quarterTurn) == .zero)
        #expect(FixedMath.sin(.halfTurn) == .zero)
        #expect(FixedMath.cos(.halfTurn) == -.one)
        #expect(FixedMath.sin(.threeQuarterTurn) == -.one)
        #expect(FixedMath.cos(.threeQuarterTurn) == .zero)
    }

    @Test func sineAndCosineTrackPlatformValuesEverywhere() {
        for angle in Self.allAngles {
            let expectedSine = Foundation.sin(Self.radians(angle)) * 65_536
            let expectedCosine = Foundation.cos(Self.radians(angle)) * 65_536
            #expect(abs(Double(FixedMath.sin(angle).raw) - expectedSine) <= 0.5 + 1e-9, "sin at \(angle.raw)")
            #expect(abs(Double(FixedMath.cos(angle).raw) - expectedCosine) <= 0.5 + 1e-9, "cos at \(angle.raw)")
        }
    }

    @Test func reflectionIdentitiesAreExact() {
        for angle in Self.allAngles {
            #expect(FixedMath.sin(-angle) == -FixedMath.sin(angle))
            #expect(FixedMath.cos(-angle) == FixedMath.cos(angle))
            #expect(FixedMath.sin(.halfTurn - angle) == FixedMath.sin(angle))
            #expect(FixedMath.cos(.halfTurn - angle) == -FixedMath.cos(angle))
            #expect(FixedMath.sin(angle + .halfTurn) == -FixedMath.sin(angle))
        }
    }

    @Test func directionsHaveUnitLength() {
        for angle in Self.allAngles {
            let error = (FixedMath.direction(angle).length - .one).magnitude
            #expect(error <= Fixed(raw: 2), "angle \(angle.raw)")
        }
    }

    @Test func arctangentInvertsDirectionWithinOneUnit() {
        for angle in Self.allAngles {
            let direction = FixedMath.direction(angle)
            let recovered = FixedMath.atan2(y: direction.y, x: direction.x)
            let difference = (recovered - angle).raw
            #expect(
                difference <= 1 || difference >= FixedAngle.unitsPerTurn - 1, "angle \(angle.raw) → \(recovered.raw)")
        }
    }

    @Test func arctangentTracksPlatformValues() {
        var generator = DeterministicRNG(seed: 31)
        for _ in 0..<20_000 {
            let x = Int32(generator.int(in: -2_000_000...2_000_000))
            let y = Int32(generator.int(in: -2_000_000...2_000_000))
            guard x != 0 || y != 0 else {
                continue
            }
            var expected = Foundation.atan2(Double(y), Double(x)) / (2 * Double.pi) * 4_096
            if expected < 0 {
                expected += 4_096
            }
            let actual = Double(FixedMath.atan2(y: Fixed(raw: y), x: Fixed(raw: x)).raw)
            let difference = abs(actual - expected)
            #expect(min(difference, 4_096 - difference) <= 1.0, "atan2(\(y), \(x)) = \(actual), expected \(expected)")
        }
    }

    @Test func arctangentIsMirrorSymmetric() {
        var generator = DeterministicRNG(seed: 32)
        for _ in 0..<5_000 {
            let x = Fixed(raw: Int32(generator.int(in: -500_000...500_000)))
            let y = Fixed(raw: Int32(generator.int(in: -500_000...500_000)))
            let angle = FixedMath.atan2(y: y, x: x)
            #expect(FixedMath.atan2(y: -y, x: x) == -angle)
            if x != .zero || y != .zero {
                #expect(FixedMath.atan2(y: y, x: -x) == .halfTurn - angle)
            }
        }
    }

    @Test func arctangentOfAxesAndZero() {
        #expect(FixedMath.atan2(y: .zero, x: .zero) == .zero)
        #expect(FixedMath.atan2(y: .zero, x: .one) == .zero)
        #expect(FixedMath.atan2(y: .one, x: .zero) == .quarterTurn)
        #expect(FixedMath.atan2(y: .zero, x: -.one) == .halfTurn)
        #expect(FixedMath.atan2(y: -.one, x: .zero) == .threeQuarterTurn)
        #expect(FixedMath.atan2(y: .one, x: .one) == FixedAngle(raw: 512))
    }

    @Test func integerSquareRootIsFloorOfRoot() {
        var generator = DeterministicRNG(seed: 41)
        let edgeCases: [UInt64] = [
            0, 1, 2, 3, 4, 15, 16, 17, 1 << 32, (1 << 32) - 1, .max, .max - 1, 0xFFFF_FFFE_0000_0001,
        ]
        let randomCases = (0..<20_000).map { _ in generator.next() >> UInt64(generator.int(in: 0...63)) }
        for value in edgeCases + randomCases {
            let root = FixedMath.isqrt(value)
            let square = root.multipliedFullWidth(by: root)
            let nextRoot = root + 1
            let nextSquare = nextRoot.multipliedFullWidth(by: nextRoot)
            #expect(square.high == 0 && square.low <= value, "isqrt(\(value)) = \(root) is too large")
            #expect(nextSquare.high > 0 || nextSquare.low > value, "isqrt(\(value)) = \(root) is too small")
        }
    }

    @Test func roundedSquareRootPicksTheNearerInteger() {
        #expect(FixedMath.roundedSquareRoot(0) == 0)
        #expect(FixedMath.roundedSquareRoot(2) == 1)
        #expect(FixedMath.roundedSquareRoot(3) == 2)
        #expect(FixedMath.roundedSquareRoot(6) == 2)
        #expect(FixedMath.roundedSquareRoot(7) == 3)
        #expect(FixedMath.roundedSquareRoot(.max) == 1 << 32)
    }

    @Test func anglesWrapAroundAFullTurn() {
        #expect(FixedAngle(raw: -1).raw == 4_095)
        #expect(FixedAngle(raw: 4_096).raw == 0)
        #expect((FixedAngle.threeQuarterTurn + .halfTurn) == .quarterTurn)
        #expect(-FixedAngle.quarterTurn == .threeQuarterTurn)
    }

    @Test func angleCodableNormalizesAndRoundTrips() throws {
        let decoded = try JSONDecoder().decode([FixedAngle].self, from: Data("[4097, -1]".utf8))
        #expect(decoded.map(\.raw) == [1, 4_095])

        let encoded = try JSONEncoder().encode(decoded)
        #expect(String(decoding: encoded, as: UTF8.self) == "[1,4095]")
    }
}

@Suite("FNV1a64")
struct FNV1a64Tests {
    @Test(
        arguments: [
            ("", 0xcbf2_9ce4_8422_2325),
            ("a", 0xaf63_dc4c_8601_ec8c),
            ("foobar", 0x8594_4171_f739_67e8),
        ] as [(String, UInt64)]
    )
    func matchesPublishedVectors(input: String, expected: UInt64) {
        var hash = FNV1a64()
        hash.combine(Array(input.utf8))
        #expect(hash.value == expected)
    }

    @Test func multiByteValuesAreLittleEndian() {
        var words = FNV1a64()
        words.combine(0x0403_0201 as UInt32)
        words.combine(-2 as Int32)

        var bytes = FNV1a64()
        bytes.combine([0x01, 0x02, 0x03, 0x04, 0xFE, 0xFF, 0xFF, 0xFF] as [UInt8])

        #expect(words.value == bytes.value)
    }

    @Test func everyOverloadFeedsItsLittleEndianBytes() {
        var typed = FNV1a64()
        typed.combine(0x0201 as UInt16)
        typed.combine(0x0807_0605_0403_0201 as UInt64)
        typed.combine(-1 as Int64)
        typed.combine(true)
        typed.combine(false)
        typed.combine(Fixed(raw: 0x0403_0201))
        typed.combine(FixedVector2(x: Fixed(raw: 1), y: Fixed(raw: -1)))

        var bytes = FNV1a64()
        bytes.combine([0x01, 0x02] as [UInt8])
        bytes.combine([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08] as [UInt8])
        bytes.combine([UInt8](repeating: 0xFF, count: 8))
        bytes.combine([0x01, 0x00] as [UInt8])
        bytes.combine([0x01, 0x02, 0x03, 0x04] as [UInt8])
        bytes.combine([0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF] as [UInt8])

        #expect(typed.value == bytes.value)
    }
}
