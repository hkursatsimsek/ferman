/// xoshiro256** (Blackman & Vigna), seeded through SplitMix64.
///
/// Deliberately not a `RandomNumberGenerator`: the standard library's `random(in:using:)` and `shuffle(using:)`
/// algorithms carry no stability guarantee, so routing them through this generator could change battle outcomes
/// between Swift releases. Every draw the simulation needs is implemented here against a fixed reference.
public struct DeterministicRNG: Sendable, Hashable, Codable {
    private var state0: UInt64
    private var state1: UInt64
    private var state2: UInt64
    private var state3: UInt64

    public init(seed: UInt64) {
        var seeder = SplitMix64(state: seed)
        state0 = seeder.next()
        state1 = seeder.next()
        state2 = seeder.next()
        state3 = seeder.next()
    }

    public mutating func next() -> UInt64 {
        let result = rotateLeft(state1 &* 5, by: 7) &* 9
        let shifted = state1 << 17
        state2 ^= state0
        state3 ^= state1
        state1 ^= state2
        state0 ^= state3
        state2 ^= shifted
        state3 = rotateLeft(state3, by: 45)
        return result
    }

    /// A uniformly distributed integer in `range`, without modulo bias.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(truncatingIfNeeded: range.upperBound &- range.lowerBound) &+ 1
        guard span != 0 else {
            return Int(truncatingIfNeeded: next())
        }
        return range.lowerBound &+ Int(truncatingIfNeeded: bounded(below: span))
    }

    /// A uniformly distributed value in [0, 1) at full Q16.16 resolution.
    public mutating func fixedUnit() -> Fixed {
        Fixed(raw: Int32(next() >> UInt64(64 - Fixed.fractionBits)))
    }

    /// Lemire's nearly divisionless method ("Fast Random Integer Generation in an Interval", 2019).
    private mutating func bounded(below bound: UInt64) -> UInt64 {
        var product = next().multipliedFullWidth(by: bound)
        if product.low < bound {
            let threshold = (0 &- bound) % bound
            while product.low < threshold {
                product = next().multipliedFullWidth(by: bound)
            }
        }
        return product.high
    }
}

struct SplitMix64: Sendable, Hashable {
    private var state: UInt64

    init(state: UInt64) {
        self.state = state
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        return mixed ^ (mixed >> 31)
    }
}

private func rotateLeft(_ value: UInt64, by count: UInt64) -> UInt64 {
    (value << count) | (value >> (64 - count))
}
