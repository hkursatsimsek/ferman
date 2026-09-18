import Foundation
import Testing

@testable import FermanSimCLI

@Suite("validate-content")
struct ValidateContentTests {
    @Test func bundledContentIsValid() {
        var output: [String] = []
        var errors: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { errors.append($0) })

        let exitCode = CommandLineTool.run(arguments: ["validate-content"], console: console)

        #expect(exitCode == ExitCode.success, "\(errors)")
        #expect(
            output == [
                "content is valid (version 1): 4 unit types [kalkan, mizrakci, okcu, suvari], "
                    + "3 maps [alan, gecit, ova], 8 levels"
            ])
    }

    @Test func invalidDirectoryFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fermansim-content-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"units": []}"#.utf8).write(to: root.appendingPathComponent("units.json"))

        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(arguments: ["validate-content", "--path", root.path], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(errors.count == 1)
        #expect(errors.first?.hasPrefix("fermansim: missing or unreadable file:") == true, "\(errors)")
    }
}
