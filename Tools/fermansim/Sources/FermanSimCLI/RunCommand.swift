import FermanCore
import Foundation

/// `fermansim run --config <path> [--out <path>]`: fights one battle and prints its outcome.
enum RunCommand {
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

        let result = BattleSimulator.run(config)
        console.standardOutput(Self.summary(of: result))

        if let outPath = command.value(for: "out") {
            do {
                try Self.write(result, to: outPath)
            } catch {
                console.standardError(
                    "\(CommandLineTool.toolName): cannot write \(outPath): \(error.localizedDescription)")
                return ExitCode.failure
            }
        }
        return ExitCode.success
    }

    static func summary(of result: BattleResult) -> String {
        "outcome=\(result.outcome.rawValue) reason=\(result.endReason.rawValue) ticks=\(result.tickCount) "
            + "survivors=\(result.survivorsPlayer)v\(result.survivorsEnemy) checksum=\(result.checksum)"
    }

    private static func write(_ result: BattleResult, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(result).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
