import Foundation
import Testing

@testable import FermanCore

@Suite("Fixed")
struct FixedTests {
    @Test func integerConversionIsExact() {
        #expect(Fixed(3).raw == 3 << 16)
        #expect(Fixed(-7).raw == -7 << 16)
        #expect(Fixed(32_767).raw == 32_767 << 16)
        #expect(Fixed(-32_768).raw == Int32.min)
        #expect(Fixed.one == 1)
    }

    struct RatioCase: Sendable, CustomTestStringConvertible {
        let numerator: Int
        let denominator: Int
        let raw: Int32

        var testDescription: String { "\(numerator)/\(denominator)" }
    }

    @Test(arguments: [
        RatioCase(numerator: 1, denominator: 2, raw: 32_768),
        RatioCase(numerator: 1, denominator: 3, raw: 21_845),
        RatioCase(numerator: 2, denominator: 3, raw: 43_691),
        RatioCase(numerator: -1, denominator: 3, raw: -21_845),
        RatioCase(numerator: -2, denominator: 3, raw: -43_691),
        RatioCase(numerator: 2, denominator: -3, raw: -43_691),
        RatioCase(numerator: 1_500, denominator: 1_000, raw: 98_304),
        RatioCase(numerator: 1, denominator: 131_072, raw: 1),
        RatioCase(numerator: -1, denominator: 131_072, raw: -1),
        RatioCase(numerator: 1, denominator: 131_073, raw: 0),
    ])
    func ratiosRoundToNearestWithTiesAwayFromZero(ratio: RatioCase) {
        #expect(Fixed(numerator: ratio.numerator, denominator: ratio.denominator).raw == ratio.raw)
    }

    @Test func multiplicationRoundsTiesAwayFromZero() {
        let smallest = Fixed(raw: 1)
        #expect((smallest * Fixed.half).raw == 1)
        #expect((-smallest * Fixed.half).raw == -1)
        #expect((Fixed(raw: 3) * Fixed(raw: 16_384)).raw == 1)
        #expect((Fixed(raw: 1) * Fixed(raw: 16_384)).raw == 0)
        #expect(Fixed(3) * Fixed(numerator: 1, denominator: 2) == Fixed(numerator: 3, denominator: 2))
    }

    @Test func divisionRoundsTiesAwayFromZero() {
        #expect((Fixed(raw: 1) / Fixed(2)).raw == 1)
        #expect((Fixed(raw: -1) / Fixed(2)).raw == -1)
        #expect((Fixed(raw: 1) / 3).raw == 0)
        #expect((Fixed(raw: 2) / 3).raw == 1)
        #expect(Fixed(1) / Fixed(3) == Fixed(numerator: 1, denominator: 3))
    }

    @Test func arithmeticIsSymmetricUnderNegation() {
        var generator = DeterministicRNG(seed: 11)
        for _ in 0..<10_000 {
            let lhs = Fixed(raw: Int32(generator.int(in: -8_000_000...8_000_000)))
            let rhs = Fixed(raw: Int32(generator.int(in: -8_000_000...8_000_000)))
            #expect((-lhs) * rhs == -(lhs * rhs))
            #expect(lhs * (-rhs) == -(lhs * rhs))
            if rhs != .zero {
                #expect((-lhs) / rhs == -(lhs / rhs))
                #expect(lhs / (-rhs) == -(lhs / rhs))
            }
        }
    }

    @Test func multiplicationMatchesRoundedWideProduct() {
        var generator = DeterministicRNG(seed: 12)
        for _ in 0..<10_000 {
            let lhs = Int32(generator.int(in: -2_000_000...2_000_000))
            let rhs = Int32(generator.int(in: -2_000_000...2_000_000))
            let exact = Double(lhs) * Double(rhs) / 65_536
            let expected = Int32(exact.rounded(.toNearestOrAwayFromZero))
            #expect((Fixed(raw: lhs) * Fixed(raw: rhs)).raw == expected)
        }
    }

    @Test func roundingToIntegers() {
        #expect(Fixed(numerator: 5, denominator: 2).rounded() == 3)
        #expect(Fixed(numerator: -5, denominator: 2).rounded() == -3)
        #expect(Fixed(numerator: 7, denominator: 3).rounded() == 2)
        #expect(Fixed(numerator: 5, denominator: 2).roundedDown() == 2)
        #expect(Fixed(numerator: -5, denominator: 2).roundedDown() == -3)
        #expect(Fixed(-3).roundedDown() == -3)
    }

    @Test func squareRootRoundsToNearest() {
        #expect(Fixed(4).squareRoot() == Fixed(2))
        #expect(Fixed(2).squareRoot().raw == 92_682)
        #expect(Fixed.zero.squareRoot() == .zero)
        #expect(Fixed(raw: 1).squareRoot().raw == 256)
        #expect(Fixed(32_767).squareRoot().raw == 11_863_102)
    }

    @Test func magnitudeClampAndSquare() {
        #expect(Fixed(-3).magnitude == Fixed(3))
        #expect(Fixed(5).clamped(to: Fixed(0)...Fixed(2)) == Fixed(2))
        #expect(Fixed(-5).clamped(to: Fixed(0)...Fixed(2)) == Fixed(0))
        #expect(Fixed(-181).squared.raw == Int64(181 * 181) << 32)
        #expect(Fixed(-181).squared.squareRoot() == Fixed(181))
    }

    @Test func integerScalingAndCompoundAssignment() {
        let third = Fixed(numerator: 1, denominator: 3)
        #expect(third + third + third == Fixed(raw: 65_535))
        let count = 3
        #expect(third * count == Fixed(raw: 65_535))
        #expect(count * third == third * count)
        #expect(Fixed(7) / 2 == Fixed(numerator: 7, denominator: 2))
        #expect(Fixed(-7) / 2 == Fixed(numerator: -7, denominator: 2))

        var value = Fixed(6)
        value *= Fixed.half
        #expect(value == Fixed(3))
        value /= Fixed(2)
        #expect(value == Fixed(numerator: 3, denominator: 2))
        value *= 4
        #expect(value == Fixed(6))
        value /= 4
        #expect(value == Fixed(numerator: 3, denominator: 2))
        value -= Fixed.half
        #expect(value == .one)
        value += Fixed.one
        #expect(value == Fixed(2))
    }

    @Test(arguments: [
        (Fixed(3), "3"),
        (Fixed(numerator: 1, denominator: 2), "0.5"),
        (Fixed(numerator: -5, denominator: 4), "-1.25"),
        (Fixed(raw: 1), "0.00002"),
        (Fixed(raw: -1), "-0.00002"),
        (Fixed(raw: 65_535), "0.99998"),
        (Fixed.max, "32767.99998"),
        (Fixed.min, "-32768"),
    ])
    func descriptionIsRoundedDecimal(value: Fixed, expected: String) {
        #expect(value.description == expected)
    }

    @Test func codableUsesRawValue() throws {
        let value = Fixed(numerator: -3, denominator: 2)
        let data = try JSONEncoder().encode([value])
        #expect(String(decoding: data, as: UTF8.self) == "[-98304]")
        #expect(try JSONDecoder().decode([Fixed].self, from: data) == [value])
    }
}

@Suite("FixedVector2")
struct FixedVector2Tests {
    @Test func lengthOfPythagoreanTriple() {
        let vector = FixedVector2(x: Fixed(3), y: Fixed(-4))
        #expect(vector.lengthSquared.raw == 25 << 32)
        #expect(vector.length == Fixed(5))
        #expect(FixedVector2.zero.distanceSquared(to: vector) == vector.lengthSquared)
    }

    @Test func squaredDistancesDoNotOverflowOnLargeMaps() {
        let corner = FixedVector2(x: Fixed(0), y: Fixed(0))
        let farCorner = FixedVector2(x: Fixed(4_096), y: Fixed(4_096))
        #expect(corner.distanceSquared(to: farCorner) > Fixed(5_792).squared)
        #expect(corner.distanceSquared(to: farCorner) < Fixed(5_793).squared)
    }

    @Test func normalizedVectorsHaveUnitLength() {
        var generator = DeterministicRNG(seed: 21)
        for _ in 0..<2_000 {
            let vector = FixedVector2(
                x: Fixed(raw: Int32(generator.int(in: -4_000_000...4_000_000))),
                y: Fixed(raw: Int32(generator.int(in: -4_000_000...4_000_000)))
            )
            // Relative precision is 0.5 / length.raw, so vectors shorter than a quarter cell are not held to it.
            guard vector.length >= Fixed(numerator: 1, denominator: 4) else {
                continue
            }
            let error = (vector.normalized().length - .one).magnitude
            #expect(error <= Fixed(raw: 4), "\(vector) → \(vector.normalized())")
        }
        #expect(FixedVector2.zero.normalized() == .zero)
    }

    @Test func normalizationIsMirrorSymmetric() {
        let vector = FixedVector2(x: Fixed(numerator: 7, denominator: 3), y: Fixed(numerator: -11, denominator: 5))
        let mirrored = FixedVector2(x: -vector.x, y: vector.y)
        #expect(mirrored.normalized() == FixedVector2(x: -vector.normalized().x, y: vector.normalized().y))
    }

    @Test func componentwiseArithmetic() {
        let position = FixedVector2(x: Fixed(3), y: Fixed(-2))
        let step = FixedVector2(x: Fixed.half, y: Fixed(1))

        #expect(position + step == FixedVector2(x: Fixed(numerator: 7, denominator: 2), y: Fixed(-1)))
        #expect(position - step == FixedVector2(x: Fixed(numerator: 5, denominator: 2), y: Fixed(-3)))
        #expect(-position == FixedVector2(x: Fixed(-3), y: Fixed(2)))
        #expect(step * Fixed(4) == FixedVector2(x: Fixed(2), y: Fixed(4)))
        #expect(Fixed(4) * step == step * Fixed(4))
        #expect(position / Fixed(2) == FixedVector2(x: Fixed(numerator: 3, denominator: 2), y: Fixed(-1)))
        #expect(step * 6 == FixedVector2(x: Fixed(3), y: Fixed(6)))
        #expect(position / 4 == FixedVector2(x: Fixed(numerator: 3, denominator: 4), y: Fixed.half * -1))

        var moving = position
        moving += step
        moving += step
        moving -= step
        #expect(moving == position + step)
        #expect(moving.description == "(3.5, -1)")
    }

    @Test func dotProduct() {
        let lhs = FixedVector2(x: Fixed(2), y: Fixed(numerator: 1, denominator: 2))
        let rhs = FixedVector2(x: Fixed(-3), y: Fixed(4))
        #expect(lhs.dot(rhs) == Fixed(-4))
        #expect((-lhs).dot(rhs) == Fixed(4))
    }

    @Test func codableRoundTrip() throws {
        let vector = FixedVector2(x: Fixed(numerator: 1, denominator: 3), y: Fixed(-9))
        let data = try JSONEncoder().encode(vector)
        #expect(try JSONDecoder().decode(FixedVector2.self, from: data) == vector)
    }
}
