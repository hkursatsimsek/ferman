import FermanCore
import Foundation
import Testing

@testable import FermanSimCLI

@Suite("verify")
struct VerifyCommandTests {
    @Test func reportsSuccessWhenEveryChecksumMatches() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = try TestFixtures.smallConfig()
        let configURL = try TestFixtures.writeConfigFile(config, in: directory)
        let expectedChecksum = BattleSimulator.run(config, options: SimulationOptions(recordEvents: false)).checksum

        var output: [String] = []
        var errors: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: ["verify", "--config", configURL.path, "--runs", "20"], console: console)

        #expect(exitCode == ExitCode.success, "\(errors)")
        #expect(output == ["20/20 runs produced checksum \(expectedChecksum)"])
    }

    @Test func defaultRunCountIs1000() throws {
        let directory = try TestFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A 2-tick battle keeps this fast; only the reported run count matters here.
        let configURL = try TestFixtures.writeConfigFile(try TestFixtures.smallConfig(maxTicks: 2), in: directory)

        var output: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { _ in })
        let exitCode = CommandLineTool.run(arguments: ["verify", "--config", configURL.path], console: console)

        #expect(exitCode == ExitCode.success)
        #expect(output.first?.hasPrefix("1000/1000") == true)
    }

    @Test func missingConfigFileFails() {
        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(arguments: ["verify", "--config", "/no/such/file.json"], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(errors.count == 1)
    }

    @Test(
        arguments: [
            ([], nil),
            ([9], nil),
            ([5, 5, 5], nil),
            ([5, 5, 7, 5], 2),
            ([7, 3], 1),
        ] as [([UInt64], Int?)]
    )
    func firstMismatchFindsTheEarliestDivergentChecksum(checksums: [UInt64], expected: Int?) {
        #expect(VerifyCommand.firstMismatch(in: checksums) == expected)
    }
}
