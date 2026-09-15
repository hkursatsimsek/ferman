import FermanCore
import Foundation

/// Identifier of a bundled map: its file name without extension, such as `ova`.
public struct MapID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    /// 1–32 characters of `a-z`, `0-9` and `-`, starting with a letter.
    public var isValid: Bool {
        let bytes = Array(rawValue.utf8)
        guard (1...32).contains(bytes.count), let first = bytes.first else {
            return false
        }
        let isLowercaseLetter = { (byte: UInt8) in (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) }
        let isDigit = { (byte: UInt8) in (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        return isLowercaseLetter(first)
            && bytes.allSatisfy { isLowercaseLetter($0) || isDigit($0) || $0 == UInt8(ascii: "-") }
    }
}

extension MapID: Comparable {
    public static func < (lhs: MapID, rhs: MapID) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}

public struct NamedMap: Sendable, Hashable {
    public let id: MapID
    public let map: BattleMap

    public init(id: MapID, map: BattleMap) {
        self.id = id
        self.map = map
    }
}

/// The validated game content: unit types and maps. Levels join in F1.12.
///
/// On disk the content is a directory holding `units.json` and `maps/<id>.json`; the app ships it as this package's
/// resource bundle and `fermansim validate-content` can point at a working copy.
public struct ContentCatalog: Sendable, Hashable {
    public static let unitsFileName = "units.json"
    public static let mapsDirectoryName = "maps"

    /// Ordered by `id`, ready to become `BattleConfig.unitCatalog`.
    public let units: [UnitType]
    /// Ordered by `id`.
    public let maps: [NamedMap]

    public init(units: [UnitType], maps: [NamedMap]) throws(ContentError) {
        let sortedUnits = units.sorted { $0.id < $1.id }
        do {
            try UnitType.validateCatalog(sortedUnits)
        } catch {
            throw .invalidUnitCatalog(error)
        }

        let sortedMaps = maps.sorted { $0.id < $1.id }
        guard !sortedMaps.isEmpty else {
            throw .noMaps
        }
        for (index, namedMap) in sortedMaps.enumerated() {
            guard namedMap.id.isValid else {
                throw .invalidMapIdentifier(namedMap.id.rawValue)
            }
            guard index == 0 || sortedMaps[index - 1].id != namedMap.id else {
                throw .duplicateMap(namedMap.id)
            }
        }

        self.units = sortedUnits
        self.maps = sortedMaps
    }

    /// The content shipped inside this package.
    public static func bundled() throws(ContentError) -> ContentCatalog {
        guard let root = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            throw .missingFile(path: "Resources")
        }
        return try load(from: root)
    }

    public static func load(from root: URL) throws(ContentError) -> ContentCatalog {
        let unitsURL = root.appendingPathComponent(unitsFileName)
        let units = try decode(UnitsFile.self, at: unitsURL).units

        let mapsURL = root.appendingPathComponent(mapsDirectoryName, isDirectory: true)
        let mapURLs: [URL]
        do {
            mapURLs = try FileManager.default.contentsOfDirectory(at: mapsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8) }
        } catch {
            throw .missingFile(path: mapsURL.path)
        }

        var maps: [NamedMap] = []
        for url in mapURLs {
            let id = MapID(rawValue: url.deletingPathExtension().lastPathComponent)
            guard id.isValid else {
                throw .invalidMapIdentifier(id.rawValue)
            }
            let file = try decode(MapFile.self, at: url)
            do {
                maps.append(NamedMap(id: id, map: try BattleMap(terrainRows: file.terrain, zoneRows: file.zones)))
            } catch {
                throw .invalidMap(id, error)
            }
        }

        return try ContentCatalog(units: units, maps: maps)
    }

    public func unitType(_ id: UnitTypeID) -> UnitType? {
        units.first { $0.id == id }
    }

    public func map(_ id: MapID) -> BattleMap? {
        maps.first { $0.id == id }?.map
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, at url: URL) throws(ContentError) -> Value {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .missingFile(path: url.path)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .malformedJSON(path: url.path, detail: String(describing: error))
        }
    }
}

private struct UnitsFile: Decodable {
    let units: [UnitType]
}

/// Map rows are decoded separately from `BattleMap` so structural problems surface as a typed `BattleMapError`.
private struct MapFile: Decodable {
    let terrain: [String]
    let zones: [String]
}

public enum ContentError: Error, Equatable, Sendable {
    case missingFile(path: String)
    case malformedJSON(path: String, detail: String)
    case invalidUnitCatalog(UnitCatalogError)
    case invalidMapIdentifier(String)
    case invalidMap(MapID, BattleMapError)
    case duplicateMap(MapID)
    case noMaps
}

extension ContentError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingFile(let path):
            "missing or unreadable file: \(path)"
        case .malformedJSON(let path, let detail):
            "malformed JSON in \(path): \(detail)"
        case .invalidUnitCatalog(let error):
            "invalid unit catalog: \(error)"
        case .invalidMapIdentifier(let identifier):
            "invalid map identifier '\(identifier)'; use 1–32 of a-z, 0-9 and '-', starting with a letter"
        case .invalidMap(let id, let error):
            "invalid map '\(id.rawValue)': \(error)"
        case .duplicateMap(let id):
            "map '\(id.rawValue)' is defined more than once"
        case .noMaps:
            "content has no maps"
        }
    }
}
