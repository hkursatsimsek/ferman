import Testing

@testable import FermanCore

@Suite("Unit catalog validation")
struct UnitCatalogValidationTests {
    static func unit(
        _ id: UnitTypeID = "okcu",
        cost: Int = 30,
        maxHP: Int = 70,
        speed: Int = 1_000,
        range: Int = 6_000,
        damage: Int = 10,
        attackInterval: Int = 36,
        armor: Int = 0,
        morale: Int = 90,
        counters: [UnitTypeID] = []
    ) -> UnitType {
        UnitType(
            id: id, cost: cost, maxHP: maxHP, speedMilliCellsPerSecond: speed, rangeMilliCells: range, damage: damage,
            attackIntervalTicks: attackInterval, armor: armor, moraleMax: morale, counters: counters, ability: .volley
        )
    }

    @Test func fixtureCatalogIsValid() throws {
        try UnitType.validateCatalog(Fixtures.catalog.sorted { $0.id < $1.id })
    }

    @Test(arguments: ["a", "okcu", "unit_2", String(repeating: "z", count: 32)])
    func acceptsIdentifiers(identifier: String) throws {
        try Self.unit(UnitTypeID(rawValue: identifier)).validate()
    }

    @Test(arguments: ["", "Okcu", "2okcu", "_okcu", "okçu", "okcu-2", "ok cu", String(repeating: "z", count: 33)])
    func rejectsIdentifiers(identifier: String) {
        let id = UnitTypeID(rawValue: identifier)
        #expect(throws: UnitTypeError.invalidIdentifier(id)) {
            try Self.unit(id).validate()
        }
    }

    struct StatisticCase: Sendable, CustomTestStringConvertible {
        let statistic: UnitStatistic
        let unit: UnitType
        let value: Int

        var testDescription: String { "\(statistic.rawValue) = \(value)" }
    }

    @Test(arguments: [
        StatisticCase(statistic: .cost, unit: unit(cost: 0), value: 0),
        StatisticCase(statistic: .cost, unit: unit(cost: 1_001), value: 1_001),
        StatisticCase(statistic: .maxHP, unit: unit(maxHP: 0), value: 0),
        StatisticCase(statistic: .maxHP, unit: unit(maxHP: 10_001), value: 10_001),
        StatisticCase(statistic: .speedMilliCellsPerSecond, unit: unit(speed: -1), value: -1),
        StatisticCase(statistic: .speedMilliCellsPerSecond, unit: unit(speed: 8_001), value: 8_001),
        StatisticCase(statistic: .rangeMilliCells, unit: unit(range: 499), value: 499),
        StatisticCase(statistic: .rangeMilliCells, unit: unit(range: 20_001), value: 20_001),
        StatisticCase(statistic: .damage, unit: unit(damage: -1), value: -1),
        StatisticCase(statistic: .damage, unit: unit(damage: 1_001), value: 1_001),
        StatisticCase(statistic: .attackIntervalTicks, unit: unit(attackInterval: 0), value: 0),
        StatisticCase(statistic: .attackIntervalTicks, unit: unit(attackInterval: 301), value: 301),
        StatisticCase(statistic: .armor, unit: unit(armor: -1), value: -1),
        StatisticCase(statistic: .armor, unit: unit(armor: 1_001), value: 1_001),
        StatisticCase(statistic: .moraleMax, unit: unit(morale: 0), value: 0),
        StatisticCase(statistic: .moraleMax, unit: unit(morale: 1_001), value: 1_001),
    ])
    func rejectsOutOfRangeStatistics(statisticCase: StatisticCase) {
        let allowed = UnitTypeLimits.allowedRange(of: statisticCase.statistic)
        #expect(throws: UnitTypeError.outOfRange(statisticCase.statistic, value: statisticCase.value, allowed: allowed))
        {
            try statisticCase.unit.validate()
        }
    }

    @Test func acceptsStatisticBounds() throws {
        for statistic in UnitStatistic.allCases {
            let range = UnitTypeLimits.allowedRange(of: statistic)
            #expect(range.lowerBound <= range.upperBound)
        }
        try Self.unit(cost: 1, maxHP: 1, speed: 0, range: 500, damage: 0, attackInterval: 1, armor: 0, morale: 1)
            .validate()
        try Self.unit(
            cost: 1_000, maxHP: 10_000, speed: 8_000, range: 20_000, damage: 1_000, attackInterval: 300, armor: 1_000,
            morale: 1_000
        ).validate()
    }

    @Test func rejectsBadCounters() {
        #expect(throws: UnitTypeError.countersItself) {
            try Self.unit("okcu", counters: ["okcu"]).validate()
        }
        #expect(throws: UnitTypeError.duplicateCounter("suvari")) {
            try Self.unit("okcu", counters: ["suvari", "suvari"]).validate()
        }
    }

    @Test func rejectsBadCatalogs() {
        #expect(throws: UnitCatalogError.empty) {
            try UnitType.validateCatalog([])
        }
        #expect(throws: UnitCatalogError.invalidUnit("okcu", .outOfRange(.cost, value: 0, allowed: 1...1_000))) {
            try UnitType.validateCatalog([Self.unit(cost: 0)])
        }
        #expect(throws: UnitCatalogError.duplicateIdentifier("okcu")) {
            try UnitType.validateCatalog([Self.unit("okcu"), Self.unit("okcu")])
        }
        #expect(throws: UnitCatalogError.notSortedByIdentifier("kalkan")) {
            try UnitType.validateCatalog([Self.unit("okcu"), Self.unit("kalkan")])
        }
        #expect(throws: UnitCatalogError.unknownCounter(unit: "okcu", counter: "fil")) {
            try UnitType.validateCatalog([Self.unit("kalkan"), Self.unit("okcu", counters: ["fil"])])
        }
    }
}
