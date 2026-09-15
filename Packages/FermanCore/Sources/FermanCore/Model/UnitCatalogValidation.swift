/// The statistics a unit type declares, named for validation errors.
public enum UnitStatistic: String, Sendable, CaseIterable {
    case cost
    case maxHP
    case speedMilliCellsPerSecond
    case rangeMilliCells
    case damage
    case attackIntervalTicks
    case armor
    case moraleMax
}

/// Bounds for every unit statistic.
///
/// A unit catalog arrives with every `BattleConfig`, including configs downloaded from other players (D5). These bounds
/// keep any accepted catalog far from Q16.16 overflow and from ticks that do no useful work.
public enum UnitTypeLimits {
    public static let identifierLength = 1...32

    public static func allowedRange(of statistic: UnitStatistic) -> ClosedRange<Int> {
        switch statistic {
        case .cost: 1...1_000
        case .maxHP: 1...10_000
        case .speedMilliCellsPerSecond: 0...8_000
        case .rangeMilliCells: 500...20_000
        case .damage: 0...1_000
        case .attackIntervalTicks: 1...300
        case .armor: 0...1_000
        case .moraleMax: 1...1_000
        }
    }
}

public enum UnitTypeError: Error, Equatable, Sendable {
    /// Identifiers are 1–32 characters of `a-z`, `0-9` and `_`, starting with a letter.
    case invalidIdentifier(UnitTypeID)
    case outOfRange(UnitStatistic, value: Int, allowed: ClosedRange<Int>)
    case countersItself
    case duplicateCounter(UnitTypeID)
}

public enum UnitCatalogError: Error, Equatable, Sendable {
    case empty
    case invalidUnit(UnitTypeID, UnitTypeError)
    case duplicateIdentifier(UnitTypeID)
    case notSortedByIdentifier(UnitTypeID)
    case unknownCounter(unit: UnitTypeID, counter: UnitTypeID)
}

extension UnitType {
    public func value(of statistic: UnitStatistic) -> Int {
        switch statistic {
        case .cost: cost
        case .maxHP: maxHP
        case .speedMilliCellsPerSecond: speedMilliCellsPerSecond
        case .rangeMilliCells: rangeMilliCells
        case .damage: damage
        case .attackIntervalTicks: attackIntervalTicks
        case .armor: armor
        case .moraleMax: moraleMax
        }
    }

    public func validate() throws(UnitTypeError) {
        guard Self.isValidIdentifier(id) else {
            throw .invalidIdentifier(id)
        }
        for statistic in UnitStatistic.allCases {
            let allowed = UnitTypeLimits.allowedRange(of: statistic)
            let value = value(of: statistic)
            guard allowed.contains(value) else {
                throw .outOfRange(statistic, value: value, allowed: allowed)
            }
        }
        var seenCounters: [UnitTypeID] = []
        for counter in counters {
            guard counter != id else {
                throw .countersItself
            }
            guard !seenCounters.contains(counter) else {
                throw .duplicateCounter(counter)
            }
            seenCounters.append(counter)
        }
    }

    /// Validates a catalog as `BattleConfig` requires it: non-empty, strictly ordered by `id`, counters resolvable.
    public static func validateCatalog(_ catalog: [UnitType]) throws(UnitCatalogError) {
        guard !catalog.isEmpty else {
            throw .empty
        }
        for (index, unitType) in catalog.enumerated() {
            do {
                try unitType.validate()
            } catch {
                throw .invalidUnit(unitType.id, error)
            }
            if index > 0 {
                let previous = catalog[index - 1].id
                guard previous != unitType.id else {
                    throw .duplicateIdentifier(unitType.id)
                }
                guard previous < unitType.id else {
                    throw .notSortedByIdentifier(unitType.id)
                }
            }
        }
        for unitType in catalog {
            for counter in unitType.counters where !catalog.contains(where: { $0.id == counter }) {
                throw .unknownCounter(unit: unitType.id, counter: counter)
            }
        }
    }

    private static func isValidIdentifier(_ id: UnitTypeID) -> Bool {
        let bytes = Array(id.rawValue.utf8)
        guard UnitTypeLimits.identifierLength.contains(bytes.count), let first = bytes.first else {
            return false
        }
        let isLowercaseLetter = { (byte: UInt8) in (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) }
        let isDigit = { (byte: UInt8) in (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        return isLowercaseLetter(first)
            && bytes.allSatisfy { isLowercaseLetter($0) || isDigit($0) || $0 == UInt8(ascii: "_") }
    }
}
