/// Content-defined identifier of a unit type, such as `okcu`.
///
/// Display names are not part of the core; the app looks up `unit.<id>` in its String Catalog (D19).
public struct UnitTypeID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

extension UnitTypeID: Comparable {
    /// Orders by UTF-8 bytes, a platform-independent order that needs no Unicode tables.
    public static func < (lhs: UnitTypeID, rhs: UnitTypeID) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}

extension UnitTypeID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// A unit's identity within one battle, assigned in placement order.
///
/// It doubles as the final tie-breaker everywhere the simulation must choose between equals (D10).
public struct UnitID: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: UnitID, rhs: UnitID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension UnitID: CustomStringConvertible {
    public var description: String { "#\(rawValue)" }
}
