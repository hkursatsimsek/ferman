import FermanCore
import Foundation
import Testing

@testable import FermanContent

@Suite("Bundled content")
struct BundledContentTests {
    @Test func loadsAndValidates() throws {
        let catalog = try ContentCatalog.bundled()
        #expect(catalog.units.map(\.id) == ["kalkan", "mizrakci", "okcu", "suvari"])
        #expect(catalog.maps.map(\.id) == ["alan", "gecit", "ova", "vadi"])
        #expect(catalog.unitType("okcu")?.ability == .volley)
        #expect(catalog.unitType("fil") == nil)
        #expect(catalog.map("ova")?.width == 24)
        #expect(catalog.map("yok") == nil)
        #expect(catalog.levels.map(\.id) == Array(1...8))
    }

    /// Both teams must face the same battlefield, or balance runs would measure the map instead of the orders.
    @Test func mapsAreMirrorSymmetricBetweenTeams() throws {
        for namedMap in try ContentCatalog.bundled().maps {
            let map = namedMap.map
            for row in 0..<map.height {
                for column in 0..<map.width {
                    let cell = row * map.width + column
                    let mirrored = row * map.width + (map.width - 1 - column)
                    #expect(map.terrain[cell] == map.terrain[mirrored], "\(namedMap.id.rawValue) at \(column),\(row)")
                }
            }
            let mirroredPlayerZone = map.playerZone.map { cell in
                let (column, row) = map.coordinates(ofCell: cell)
                return row * map.width + (map.width - 1 - column)
            }
            #expect(mirroredPlayerZone.sorted() == map.enemyZone, "\(namedMap.id.rawValue) zones")
        }
    }

    @Test func countersFormACycleWithShieldOutsideIt() throws {
        let catalog = try ContentCatalog.bundled()
        let counters = Dictionary(uniqueKeysWithValues: catalog.units.map { ($0.id, $0.counters) })
        #expect(counters["mizrakci"] == ["suvari"])
        #expect(counters["suvari"] == ["okcu"])
        #expect(counters["okcu"] == ["mizrakci"])
        #expect(counters["kalkan"] == [])
    }
}

@Suite("Content validation")
struct ContentValidationTests {
    static let validUnits = """
        {"units": [
          {"id": "okcu", "cost": 30, "maxHP": 70, "speedMilliCellsPerSecond": 1000, "rangeMilliCells": 6000,
           "damage": 10, "attackIntervalTicks": 36, "armor": 0, "moraleMax": 90, "counters": [], "ability": "volley"}
        ]}
        """
    static let validMap = #"{"terrain": ["..."], "zones": ["P.E"]}"#

    /// Writes a content directory into a fresh temporary folder and loads it.
    static func load(units: String?, maps: [String: String]?) throws(ContentError) -> ContentCatalog {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FermanContentTests-\(UInt64.random(in: 0...UInt64.max))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let units {
                try Data(units.utf8).write(to: root.appendingPathComponent(ContentCatalog.unitsFileName))
            }
            if let maps {
                let mapsURL = root.appendingPathComponent(ContentCatalog.mapsDirectoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: mapsURL, withIntermediateDirectories: true)
                for (fileName, contents) in maps {
                    try Data(contents.utf8).write(to: mapsURL.appendingPathComponent(fileName))
                }
            }
        } catch {
            Issue.record("could not write fixture: \(error)")
        }
        return try ContentCatalog.load(from: root)
    }

    static func error(units: String?, maps: [String: String]?) -> ContentError? {
        do {
            _ = try load(units: units, maps: maps)
            return nil
        } catch {
            return error
        }
    }

    @Test func minimalContentLoads() throws {
        let catalog = try Self.load(units: Self.validUnits, maps: ["ova.json": Self.validMap, "notes.txt": "ignored"])
        #expect(catalog.units.count == 1)
        #expect(catalog.maps.map(\.id) == ["ova"])
    }

    @Test func missingUnitsFile() {
        guard case .missingFile(let path) = Self.error(units: nil, maps: ["ova.json": Self.validMap]) else {
            Issue.record("expected missingFile")
            return
        }
        #expect(path.hasSuffix("units.json"))
    }

    @Test func missingMapsDirectory() {
        guard case .missingFile(let path) = Self.error(units: Self.validUnits, maps: nil) else {
            Issue.record("expected missingFile")
            return
        }
        #expect(path.hasSuffix("maps"))
    }

    @Test func emptyMapsDirectory() {
        #expect(Self.error(units: Self.validUnits, maps: [:]) == .noMaps)
    }

    @Test(arguments: [
        #"{"units": "#,
        #"{"unit": []}"#,
        #"{"units": [{"id": "okcu"}]}"#,
        #"{"units": [{"id": "okcu", "cost": 1.5, "maxHP": 70, "speedMilliCellsPerSecond": 1000, "rangeMilliCells": 6000, "damage": 10, "attackIntervalTicks": 36, "armor": 0, "moraleMax": 90, "counters": [], "ability": "volley"}]}"#,
        #"{"units": [{"id": "okcu", "cost": 30, "maxHP": 70, "speedMilliCellsPerSecond": 1000, "rangeMilliCells": 6000, "damage": 10, "attackIntervalTicks": 36, "armor": 0, "moraleMax": 90, "counters": [], "ability": "fly"}]}"#,
    ])
    func malformedUnitsFile(units: String) {
        guard case .malformedJSON(let path, _) = Self.error(units: units, maps: ["ova.json": Self.validMap]) else {
            Issue.record("expected malformedJSON")
            return
        }
        #expect(path.hasSuffix("units.json"))
    }

    @Test func invalidUnitStatistic() {
        let units = Self.validUnits.replacingOccurrences(of: #""armor": 0"#, with: #""armor": -3"#)
        let expected = ContentError.invalidUnitCatalog(
            .invalidUnit("okcu", .outOfRange(.armor, value: -3, allowed: 0...1_000))
        )
        #expect(Self.error(units: units, maps: ["ova.json": Self.validMap]) == expected)
    }

    @Test func unknownCounter() {
        let units = Self.validUnits.replacingOccurrences(of: #""counters": []"#, with: #""counters": ["fil"]"#)
        let expected = ContentError.invalidUnitCatalog(.unknownCounter(unit: "okcu", counter: "fil"))
        #expect(Self.error(units: units, maps: ["ova.json": Self.validMap]) == expected)
    }

    @Test func duplicateUnit() throws {
        let unit = try #require(ContentCatalog.bundled().unitType("okcu"))
        #expect(throws: ContentError.invalidUnitCatalog(.duplicateIdentifier("okcu"))) {
            try ContentCatalog(units: [unit, unit], maps: ContentCatalog.bundled().maps)
        }
    }

    @Test func invalidMapStructure() {
        let map = #"{"terrain": ["...", ".."], "zones": ["P.E", "P."]}"#
        let expected = ContentError.invalidMap("ova", .raggedRows(row: 1, expectedWidth: 3, actualWidth: 2))
        #expect(Self.error(units: Self.validUnits, maps: ["ova.json": map]) == expected)
    }

    @Test func malformedMapFile() {
        guard
            case .malformedJSON(let path, _) = Self.error(
                units: Self.validUnits, maps: ["ova.json": #"{"terrain": ["..."]}"#])
        else {
            Issue.record("expected malformedJSON")
            return
        }
        #expect(path.hasSuffix("ova.json"))
    }

    @Test(arguments: ["Ova.json", "2ova.json", "orman_gecidi.json", "ova map.json"])
    func invalidMapFileName(fileName: String) {
        let identifier = String(fileName.dropLast(".json".count))
        #expect(
            Self.error(units: Self.validUnits, maps: [fileName: Self.validMap]) == .invalidMapIdentifier(identifier))
    }

    @Test func duplicateAndInvalidMapsInMemory() throws {
        let catalog = try ContentCatalog.bundled()
        let ova = try #require(catalog.maps.first { $0.id == "ova" })
        #expect(throws: ContentError.duplicateMap("ova")) {
            try ContentCatalog(units: catalog.units, maps: [ova, ova])
        }
        #expect(throws: ContentError.invalidMapIdentifier("Ova")) {
            try ContentCatalog(units: catalog.units, maps: [NamedMap(id: "Ova", map: ova.map)])
        }
    }

    @Test func errorsDescribeThemselves() {
        let errors: [ContentError] = [
            .missingFile(path: "units.json"),
            .malformedJSON(path: "units.json", detail: "bad"),
            .invalidUnitCatalog(.empty),
            .invalidMapIdentifier("Ova"),
            .invalidMap("ova", .empty),
            .duplicateMap("ova"),
            .noMaps,
            .invalidLevelCatalog(.duplicateIdentifier(1)),
        ]
        #expect(Set(errors.map(\.description)).count == errors.count)
    }
}
