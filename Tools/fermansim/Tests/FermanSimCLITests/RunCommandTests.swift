import FermanCore
import Foundation
import Testing

@testable import FermanSimCLI

@Suite("run")
struct RunCommandTests {
    @Test func printsASummaryAndExitsSuccessfully() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = try TestFixtures.writeConfigFile(try TestFixtures.smallConfig(), in: directory)

        var output: [String] = []
        var errors: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(arguments: ["run", "--config", configURL.path], console: console)

        #expect(exitCode == ExitCode.success, "\(errors)")
        #expect(output.count == 1)
        #expect(output[0].contains("outcome="))
        #expect(output[0].contains("checksum="))
    }

    @Test func writesTheFullResultWhenOutIsGiven() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = try TestFixtures.writeConfigFile(try TestFixtures.smallConfig(), in: directory)
        let outURL = directory.appendingPathComponent("result.json")

        let console = Console(standardOutput: { _ in }, standardError: { _ in })
        let exitCode = CommandLineTool.run(
            arguments: ["run", "--config", configURL.path, "--out", outURL.path], console: console)

        #expect(exitCode == ExitCode.success)
        let result = try JSONDecoder().decode(BattleResult.self, from: try Data(contentsOf: outURL))
        #expect(result.tickCount > 0)
    }

    @Test func missingConfigFileFails() {
        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(arguments: ["run", "--config", "/no/such/file.json"], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(errors.count == 1)
    }
}
