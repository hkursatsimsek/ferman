import FermanCore
import Foundation
import Testing

@testable import FermanSimCLI

@Suite("batch")
struct BatchCommandTests {
    private struct MatrixEntryFile: Encodable {
        let name: String
        let config: BattleConfig
    }

    private struct MatrixFile: Encodable {
        let entries: [MatrixEntryFile]
    }

    @Test func writesOneRowPerEntryAndSeed() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = try TestFixtures.smallConfig(maxTicks: 5)

        let matrix = MatrixFile(entries: [
            MatrixEntryFile(name: "alpha", config: config), MatrixEntryFile(name: "beta", config: config),
        ])
        let matrixURL = directory.appendingPathComponent("matrix.json")
        try JSONEncoder().encode(matrix).write(to: matrixURL)
        let outURL = directory.appendingPathComponent("results.csv")

        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: ["batch", "--matrix", matrixURL.path, "--count", "3", "--jobs", "2", "--out", outURL.path],
            console: console)

        #expect(exitCode == ExitCode.success, "\(errors)")
        let csv = try String(contentsOf: outURL, encoding: .utf8)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 7)
        #expect(lines[0] == "entry,seed,outcome,endReason,tickCount,survivorsPlayer,survivorsEnemy,checksum")
        let dataRows = lines.dropFirst()
        #expect(dataRows.filter { $0.hasPrefix("alpha,") }.count == 3)
        #expect(dataRows.filter { $0.hasPrefix("beta,") }.count == 3)
        #expect(
            Set(dataRows.compactMap { $0.split(separator: ",").dropFirst().first.map(String.init) }) == ["0", "1", "2"])
    }

    @Test func emptyMatrixFails() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let matrixURL = directory.appendingPathComponent("matrix.json")
        try Data(#"{"entries": []}"#.utf8).write(to: matrixURL)

        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: [
                "batch", "--matrix", matrixURL.path, "--out", directory.appendingPathComponent("out.csv").path,
            ], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(!errors.isEmpty)
    }

    @Test func missingMatrixFileFails() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: [
                "batch", "--matrix", "/no/such/matrix.json", "--out",
                directory.appendingPathComponent("out.csv").path,
            ], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(!errors.isEmpty)
    }
}
