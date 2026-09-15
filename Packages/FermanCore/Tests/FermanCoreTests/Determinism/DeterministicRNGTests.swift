import Foundation
import Testing

@testable import FermanCore

/// Vectors come from the authors' reference C implementations (prng.di.unimi.it: splitmix64.c, xoshiro256starstar.c)
/// and Lemire's bounded method with 128-bit multiplication, compiled with clang.
@Suite("DeterministicRNG")
struct DeterministicRNGTests {
    struct ReferenceStream: Sendable, CustomTestStringConvertible {
        let seed: UInt64
        let firstOutputs: [UInt64]

        var testDescription: String { "seed 0x" + String(seed, radix: 16) }
    }

    static let referenceStreams: [ReferenceStream] = [
        ReferenceStream(
            seed: 0,
            firstOutputs: [
                0x99ec_5f36_cb75_f2b4, 0xbf6e_1f78_4956_452a, 0x1a5f_849d_4933_e6e0, 0x6aa5_94f1_262d_2d2c,
                0xbba5_ad4a_1f84_2e59, 0xffef_8375_d9eb_caca, 0x6c16_0dee_d2f5_4c98, 0x8920_ad64_8fc3_0a3f,
            ]
        ),
        ReferenceStream(
            seed: 1,
            firstOutputs: [
                0xb3f2_af6d_0fc7_10c5, 0x853b_5596_4736_4cea, 0x92f8_9756_082a_4514, 0x642e_1c7b_c266_a3a7,
                0xb27a_48e2_9a23_3673, 0x24c1_2312_6ffd_a722, 0x1230_04ef_8df5_10e6, 0x6195_4dcc_47b1_e89d,
            ]
        ),
        ReferenceStream(
            seed: 0xdead_beef,
            firstOutputs: [
                0xc555_5444_a74d_7e83, 0x65c3_0d37_b4b1_6e38, 0x54f7_7320_0a4e_fa23, 0x429a_ed75_fb95_8af7,
                0xfb0e_1dd6_9c25_5b2e, 0x9d6d_02ec_5881_4a27, 0xf419_9b9d_a2e4_b2a3, 0x54bc_5b2c_11a4_540a,
            ]
        ),
        ReferenceStream(
            seed: .max,
            firstOutputs: [
                0x8f55_20d5_2a7e_ad08, 0xc476_a018_caa1_802d, 0x81de_31c0_d260_469e, 0xbf65_8d7e_065f_3c2f,
                0x9135_93fd_a1bc_a32a, 0xbb53_5e93_941b_a525, 0x5ecd_a415_c3c6_dfde, 0xc487_398f_c9de_9ae2,
            ]
        ),
    ]

    @Test(arguments: referenceStreams)
    func matchesReferenceImplementation(stream: ReferenceStream) {
        var generator = DeterministicRNG(seed: stream.seed)
        let outputs = (0..<stream.firstOutputs.count).map { _ in generator.next() }
        #expect(outputs == stream.firstOutputs)
    }

    @Test func splitMixMatchesReferenceImplementation() {
        var seeder = SplitMix64(state: 0)
        let outputs = (0..<4).map { _ in seeder.next() }
        #expect(
            outputs == [0xe220_a839_7b1d_cdaf, 0x6e78_9e6a_a1b9_65f4, 0x06c4_5d18_8009_454f, 0xf88b_b8a8_724c_81ec])
    }

    struct BoundedCase: Sendable, CustomTestStringConvertible {
        let bound: UInt64
        let draws: [UInt64]

        var testDescription: String { "[0, \(bound))" }
    }

    static let boundedCases: [BoundedCase] = [
        BoundedCase(bound: 1, draws: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        BoundedCase(bound: 2, draws: [0, 0, 1, 1, 1, 1, 1, 1, 1, 1]),
        BoundedCase(bound: 6, draws: [0, 2, 4, 5, 5, 4, 4, 5, 4, 3]),
        BoundedCase(bound: 7, draws: [0, 2, 4, 6, 6, 5, 5, 5, 5, 4]),
        BoundedCase(bound: 100, draws: [8, 37, 68, 92, 99, 76, 71, 85, 76, 58]),
        BoundedCase(
            bound: 1_000_000_007,
            draws: [
                83_862_971, 378_980_253, 680_043_415, 924_692_951, 991_803_921, 769_739_465, 719_258_582,
                850_008_449, 761_374_386, 583_349_313,
            ]
        ),
        BoundedCase(
            bound: 0x8000_0000_0000_0001,
            draws: [
                9_147_776_489_032_658_738, 7_099_593_415_032_875_292, 6_633_989_454_467_100_377,
                7_022_439_175_346_172_479, 2_681_029_139_591_840_946, 7_388_145_106_668_446_555,
                8_095_973_720_557_042_685, 7_852_687_488_934_748_778, 6_528_572_799_845_377_949,
                856_482_903_962_274_924,
            ]
        ),
    ]

    /// Ranges start at `Int.min` so spans wider than `Int.max`, and the wrapping arithmetic behind them, are covered.
    @Test(arguments: boundedCases)
    func boundedDrawsMatchReferenceImplementation(boundedCase: BoundedCase) {
        var generator = DeterministicRNG(seed: 42)
        let range = Int.min...(Int.min &+ Int(truncatingIfNeeded: boundedCase.bound &- 1))
        let draws = (0..<boundedCase.draws.count).map { _ in
            UInt64(truncatingIfNeeded: generator.int(in: range) &- Int.min)
        }
        #expect(draws == boundedCase.draws)
    }

    @Test func offsetRangesShiftTheReferenceDraws() {
        var generator = DeterministicRNG(seed: 42)
        let draws = (0..<10).map { _ in generator.int(in: -50...49) }
        #expect(draws == [8, 37, 68, 92, 99, 76, 71, 85, 76, 58].map { $0 - 50 })
    }

    @Test func fullIntegerRangeUsesTheRawOutput() {
        var reference = DeterministicRNG(seed: 9)
        var generator = DeterministicRNG(seed: 9)
        #expect(generator.int(in: Int.min...Int.max) == Int(truncatingIfNeeded: reference.next()))
    }

    @Test func singleValueRangeAlwaysReturnsThatValue() {
        var generator = DeterministicRNG(seed: 3)
        #expect((0..<32).allSatisfy { _ in generator.int(in: 17...17) == 17 })
    }

    @Test func fixedUnitUsesTheTopSixteenBits() {
        var generator = DeterministicRNG(seed: 7)
        let draws = (0..<8).map { _ in generator.fixedUnit().raw }
        #expect(draws == [45_912, 18_268, 55_025, 64_297, 64_937, 57_198, 3_981, 6_844])
        #expect(draws.allSatisfy { (0..<Fixed.one.raw).contains($0) })
    }

    @Test func drawsCoverTheRangeUniformly() {
        var generator = DeterministicRNG(seed: 2026)
        var histogram = [Int](repeating: 0, count: 6)
        let drawCount = 60_000
        for _ in 0..<drawCount {
            histogram[generator.int(in: 0...5)] += 1
        }
        // Each face expects 10 000 draws with a standard deviation of ~91; ±500 is more than five sigma.
        #expect(histogram.allSatisfy { abs($0 - drawCount / 6) < 500 }, "\(histogram)")
    }

    @Test func codableRoundTripResumesTheSameStream() throws {
        var original = DeterministicRNG(seed: .max)
        _ = original.next()

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(DeterministicRNG.self, from: data)

        #expect(restored == original)
        #expect((0..<16).map { _ in restored.next() } == (0..<16).map { _ in original.next() })
    }

    @Test func platformIntegerIsSixtyFourBits() {
        #expect(Int.bitWidth == 64)
    }
}
