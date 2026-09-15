import Foundation
import Testing

@testable import FermanCore
@testable import FermanSimCLI

@Suite("gen-tables")
struct TableGeneratorTests {
    static let committedTablesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Packages/FermanCore/Sources/FermanCore/Determinism/FixedMathTables.swift")

    @Test func committedTablesMatchTheGenerator() throws {
        let committed = try String(contentsOf: Self.committedTablesURL, encoding: .utf8)
        #expect(
            committed == TableGenerator.swiftSource(),
            "Run `fermansim gen-tables --out \(Self.committedTablesURL.path)`")
    }

    @Test func compiledTablesMatchTheGenerator() {
        #expect(FixedMath.quarterSineTable == TableGenerator.quarterSineTable())
        #expect(FixedMath.arctangentTable == TableGenerator.arctangentTable())
    }

    @Test func tableEndpoints() {
        let sine = TableGenerator.quarterSineTable()
        let arctangent = TableGenerator.arctangentTable()
        #expect(sine.first == 0)
        #expect(sine.last == 65_536)
        #expect(arctangent.first == 0)
        #expect(arctangent.last == 512)
        #expect(zip(sine, sine.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(zip(arctangent, arctangent.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func checkFlagReportsUpToDateTables() {
        var output: [String] = []
        var errors: [String] = []
        let console = Console(standardOutput: { output.append($0) }, standardError: { errors.append($0) })

        let exitCode = CommandLineTool.run(
            arguments: ["gen-tables", "--out", Self.committedTablesURL.path, "--check"],
            console: console
        )

        #expect(exitCode == ExitCode.success, "\(errors)")
        #expect(output.count == 1)
    }

    @Test func checkFlagFailsForStaleTables() throws {
        let staleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FixedMathTables-\(ProcessInfo.processInfo.processIdentifier)-stale.swift")
        try Data("// stale\n".utf8).write(to: staleURL)
        defer { try? FileManager.default.removeItem(at: staleURL) }

        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        let exitCode = CommandLineTool.run(
            arguments: ["gen-tables", "--out", staleURL.path, "--check"], console: console)

        #expect(exitCode == ExitCode.failure)
        #expect(errors.first?.contains("out of date") == true)
        #expect(try String(contentsOf: staleURL, encoding: .utf8) == "// stale\n")
    }

    @Test func writesTablesToTheRequestedPath() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FixedMathTables-\(ProcessInfo.processInfo.processIdentifier)-fresh.swift")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let console = Console(standardOutput: { _ in }, standardError: { _ in })
        let exitCode = CommandLineTool.run(arguments: ["gen-tables", "--out", outputURL.path], console: console)

        #expect(exitCode == ExitCode.success)
        #expect(try String(contentsOf: outputURL, encoding: .utf8) == TableGenerator.swiftSource())
    }

    @Test func usageErrorsExitWithUsageCode() {
        var errors: [String] = []
        let console = Console(standardOutput: { _ in }, standardError: { errors.append($0) })
        #expect(CommandLineTool.run(arguments: ["gen-tables"], console: console) == ExitCode.usage)
        #expect(errors.first == "fermansim: 'gen-tables' requires '--out'")
    }
}
