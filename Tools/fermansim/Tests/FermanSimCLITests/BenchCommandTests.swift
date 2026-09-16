import Foundation
import Testing

@testable import FermanSimCLI

@Suite("bench")
struct BenchCommandTests {
    @Test func reportsUnitCountAndThroughput() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = try TestFixtures.writeConfigFile(try TestFixtures.smallConfig(maxTicks: 10), in: directory)

        var output: [String] = []
        var errors: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: ["bench", "--config", configURL.path, "--runs", "3"], console: console)

        #expect(exitCode == ExitCode.success, "\(errors)")
        #expect(output.count == 1)
        #expect(output[0].contains("2 units"))
        #expect(output[0].contains("10 ticks/run"))
        #expect(output[0].contains("3 runs"))
        #expect(output[0].contains("ticks/sec"))
    }

    @Test func missingConfigFileFails() {
        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(arguments: ["bench", "--config", "/no/such/file.json"], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(!errors.isEmpty)
    }
}
