import FermanCore

/// Runs `BattleSimulator` off the main actor so starting a battle never blocks the UI (D13).
///
/// The app target defaults every declaration to `@MainActor`; `@concurrent` is what actually
/// moves this one off it, since the simulation is the heavy call sim-then-render depends on.
struct BattleRunner: Sendable {
    @concurrent
    func run(_ config: BattleConfig) async -> BattleResult {
        BattleSimulator.run(config)
    }
}
