/// 64-bit FNV-1a, the battle checksum.
///
/// Multi-byte values are fed in little-endian order explicitly, so the checksum does not depend on host byte order.
public struct FNV1a64: Sendable, Hashable {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    public private(set) var value: UInt64 = offsetBasis

    public init() {}

    public mutating func combine(_ byte: UInt8) {
        value = (value ^ UInt64(byte)) &* Self.prime
    }

    public mutating func combine(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            combine(byte)
        }
    }

    public mutating func combine(_ word: UInt16) {
        combineLittleEndian(UInt64(word), byteCount: 2)
    }

    public mutating func combine(_ word: UInt32) {
        combineLittleEndian(UInt64(word), byteCount: 4)
    }

    public mutating func combine(_ word: UInt64) {
        combineLittleEndian(word, byteCount: 8)
    }

    public mutating func combine(_ word: Int32) {
        combine(UInt32(bitPattern: word))
    }

    public mutating func combine(_ word: Int64) {
        combine(UInt64(bitPattern: word))
    }

    public mutating func combine(_ flag: Bool) {
        combine(flag ? 1 as UInt8 : 0)
    }

    public mutating func combine(_ number: Fixed) {
        combine(number.raw)
    }

    public mutating func combine(_ vector: FixedVector2) {
        combine(vector.x)
        combine(vector.y)
    }

    private mutating func combineLittleEndian(_ word: UInt64, byteCount: Int) {
        for index in 0..<byteCount {
            combine(UInt8(truncatingIfNeeded: word >> UInt64(8 * index)))
        }
    }
}
