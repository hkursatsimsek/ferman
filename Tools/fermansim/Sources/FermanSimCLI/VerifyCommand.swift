import FermanCore

/// `fermansim verify --config <path> [--runs <count>]`: the determinism contract (CLAUDE.md rule 2), checked by
/// hand. Every run shares one config and seed, so every checksum must be identical.
enum VerifyCommand {
    static let defaultRuns = 1_000

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
            runs = try command.integer(for: "runs", in: 1...1_000_000) ?? defaultRuns
        } catch {
            console.standardError("\(CommandLineTool.toolName): \(error)")
            return ExitCode.usage
        }

        var checksums: [UInt64] = []
        checksums.reserveCapacity(runs)
        for _ in 0..<runs {
            checksums.append(BattleSimulator.run(config, options: SimulationOptions(recordEvents: false)).checksum)
        }

        if let mismatchIndex = Self.firstMismatch(in: checksums) {
            console.standardError(
                "\(CommandLineTool.toolName): checksum mismatch on run \(mismatchIndex + 1)/\(runs): "
                    + "expected \(checksums[0]), got \(checksums[mismatchIndex])")
            return ExitCode.failure
        }
        console.standardOutput("\(runs)/\(runs) runs produced checksum \(checksums[0])")
        return ExitCode.success
    }

    /// The index of the first checksum that differs from the first one, or `nil` if every run agrees.
    static func firstMismatch(in checksums: [UInt64]) -> Int? {
        guard let first = checksums.first else {
            return nil
        }
        return checksums.firstIndex { $0 != first }
    }
}
