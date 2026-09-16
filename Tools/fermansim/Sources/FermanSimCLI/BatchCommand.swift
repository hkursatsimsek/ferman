import Dispatch
import FermanCore
import Foundation
import Synchronization

/// One matrix entry: a named `BattleConfig` template. `batch` fights it under seeds `0..<count`, ignoring whatever
/// seed the file itself carries.
struct BattleMatrixEntry: Decodable {
    let name: String
    let config: BattleConfig
}

struct BattleMatrixFile: Decodable {
    let entries: [BattleMatrixEntry]
}

/// `fermansim batch --matrix <path> [--count <n>] [--jobs <n>] --out <path>`: fights every matrix entry across
/// `count` seeds and writes one CSV row per fight. Runs are independent, so batches may run in parallel across
/// `jobs` workers (CLAUDE.md rule 2 only forbids concurrency *inside* one run).
enum BatchCommand {
    struct ResultRow {
        let entry: String
        let seed: UInt64
        let result: BattleResult
    }

    static func execute(_ command: ParsedCommand, console: Console) -> Int32 {
        guard let matrixPath = command.value(for: "matrix"), let outPath = command.value(for: "out") else {
            return ExitCode.usage
        }

        let matrixFile: BattleMatrixFile
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: matrixPath))
            matrixFile = try JSONDecoder().decode(BattleMatrixFile.self, from: data)
        } catch {
            console.standardError("\(CommandLineTool.toolName): cannot read \(matrixPath): \(error)")
            return ExitCode.failure
        }
        guard !matrixFile.entries.isEmpty else {
            console.standardError("\(CommandLineTool.toolName): \(matrixPath) has no entries")
            return ExitCode.failure
        }

        let count: Int
        let jobs: Int
        do {
            count = try command.integer(for: "count", in: 1...10_000_000) ?? 1
            jobs = try command.integer(for: "jobs", in: 1...1_024) ?? 1
        } catch {
            console.standardError("\(CommandLineTool.toolName): \(error)")
            return ExitCode.usage
        }

        let rows = Self.runMatrix(matrixFile, count: count, jobs: jobs)
        do {
            try Self.writeCSV(rows, to: outPath)
        } catch {
            console.standardError("\(CommandLineTool.toolName): cannot write \(outPath): \(error.localizedDescription)")
            return ExitCode.failure
        }
        console.standardOutput("wrote \(rows.count) results to \(outPath)")
        return ExitCode.success
    }

    /// Every (entry, seed) fight, in matrix-then-seed order regardless of which of the `jobs` workers finishes
    /// first. Each worker computes its own chunk in a local array and locks only to hand that chunk over, so the
    /// `Mutex` is held for a fraction of a fraction of the time a battle itself takes.
    static func runMatrix(_ matrixFile: BattleMatrixFile, count: Int, jobs: Int) -> [ResultRow] {
        let tasks: [(entryIndex: Int, seed: UInt64)] = matrixFile.entries.indices.flatMap { entryIndex in
            (0..<count).map { seed in (entryIndex, UInt64(seed)) }
        }
        guard !tasks.isEmpty else {
            return []
        }

        let chunkSize = (tasks.count + jobs - 1) / jobs
        let chunks = Mutex([[ResultRow]](repeating: [], count: jobs))
        DispatchQueue.concurrentPerform(iterations: jobs) { chunkIndex in
            let start = chunkIndex * chunkSize
            let end = Swift.min(start + chunkSize, tasks.count)
            guard start < end else { return }
            var chunkRows: [ResultRow] = []
            chunkRows.reserveCapacity(end - start)
            for taskIndex in start..<end {
                let task = tasks[taskIndex]
                let entry = matrixFile.entries[task.entryIndex]
                let result = BattleSimulator.run(
                    entry.config.withSeed(task.seed), options: SimulationOptions(recordEvents: false))
                chunkRows.append(ResultRow(entry: entry.name, seed: task.seed, result: result))
            }
            chunks.withLock { $0[chunkIndex] = chunkRows }
        }
        return chunks.withLock { $0 }.flatMap { $0 }
    }

    private static func writeCSV(_ rows: [ResultRow], to path: String) throws {
        var lines = ["entry,seed,outcome,endReason,tickCount,survivorsPlayer,survivorsEnemy,checksum"]
        for row in rows {
            let result = row.result
            lines.append(
                "\(row.entry),\(row.seed),\(result.outcome.rawValue),\(result.endReason.rawValue),\(result.tickCount),"
                    + "\(result.survivorsPlayer),\(result.survivorsEnemy),\(result.checksum)")
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
