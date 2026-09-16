import FermanCore
import Foundation

/// Loads a `BattleConfig` from the JSON file the player-facing tooling and CI both point `--config` at. The config
/// is self-contained (catalog, tuning, map), so nothing else needs to be read alongside it.
enum BattleConfigLoader {
    enum LoadError: Error, CustomStringConvertible {
        case unreadable(path: String, underlying: String)
        case malformed(path: String, detail: String)

        var description: String {
            switch self {
            case .unreadable(let path, let underlying):
                "cannot read \(path): \(underlying)"
            case .malformed(let path, let detail):
                "malformed battle config in \(path): \(detail)"
            }
        }
    }

    static func load(from path: String) throws(LoadError) -> BattleConfig {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw .unreadable(path: path, underlying: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(BattleConfig.self, from: data)
        } catch {
            throw .malformed(path: path, detail: String(describing: error))
        }
    }
}

extension BattleConfig {
    /// The same battle, fought under a different seed. `batch` uses this to sweep a matrix entry across many
    /// seeds without the matrix file having to spell out one config per seed.
    func withSeed(_ seed: UInt64) -> BattleConfig {
        BattleConfig(
            simulationVersion: simulationVersion, map: map, unitCatalog: unitCatalog, tuning: tuning, player: player,
            enemy: enemy, objective: objective, constraints: constraints, seed: seed, maxTicks: maxTicks)
    }
}
