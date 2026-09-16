import FermanCore
import Foundation

/// `fermansim bench --config <path> [--runs <count>]`: times repeated fights of one config (`recordEvents:
/// false`, matching how `batch` and strategist rollouts run) to check the simulation still scales — the stress
/// report F0.11 asks for at 150 units, and the 24v24 throughput `batch` needs to hit 10k runs under a minute.
enum BenchCommand {
    static let defaultRuns = 5

    static func execute(_ command: ParsedCommand, console: Console) -> Int32 {
        guard let path = command.value(for: "config") else {
            return ExitCode.usage
        }
        let config: BattleConfig
        do {
            config = try BattleConfigLoader.load(from: path)
        } catch {
            console.standardError("\(CommandLineTool.toolName): \(error)")
            return ExitCode.failure
        }

        let runs: Int
        do {
            runs = try command.integer(for: "runs", in: 1...1_000) ?? defaultRuns
        } catch {
            console.standardError("\(CommandLineTool.toolName): \(error)")
            return ExitCode.usage
        }

        let unitCount = config.player.placements.count + config.enemy.placements.count
        let clock = ContinuousClock()
        var secondsPerRun: [Double] = []
        secondsPerRun.reserveCapacity(runs)
        var tickCount = 0
        for _ in 0..<runs {
            let start = clock.now
            let result = BattleSimulator.run(config, options: SimulationOptions(recordEvents: false))
            secondsPerRun.append(Self.seconds(clock.now - start))
            tickCount = result.tickCount
        }

        let average = secondsPerRun.reduce(0, +) / Double(runs)
        let fastest = secondsPerRun.min() ?? average
        let ticksPerSecond = average > 0 ? Double(tickCount) / average : .infinity

        console.standardOutput(
            String(
                format: "%d units, %d ticks/run, %d runs: avg %.1f ms (%.0f ticks/sec), fastest %.1f ms", unitCount,
                tickCount, runs, average * 1_000, ticksPerSecond, fastest * 1_000))
        return ExitCode.success
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
