import FermanContent
import Foundation

public struct Console {
    public var standardOutput: (String) -> Void
    public var standardError: (String) -> Void

    public init(standardOutput: @escaping (String) -> Void, standardError: @escaping (String) -> Void) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public static var system: Console {
        Console(
            standardOutput: { print($0) },
            standardError: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        )
    }
}

public enum ExitCode {
    public static let success: Int32 = 0
    public static let failure: Int32 = 1
    /// `EX_USAGE` from sysexits(3).
    public static let usage: Int32 = 64
}

public enum CommandLineTool {
    public static let toolName = "fermansim"

    static let commands: [CommandSpecification] = [
        CommandSpecification(
            name: "help",
            summary: "Show this help.",
            options: [],
            flags: []
        ),
        CommandSpecification(
            name: "gen-tables",
            summary: "Generate FixedMathTables.swift for FermanCore.",
            options: [
                .init(name: "out", placeholder: "path", summary: "File to write or check.", isRequired: true)
            ],
            flags: [
                .init(name: "check", summary: "Fail if the file differs from freshly generated tables; write nothing.")
            ]
        ),
        CommandSpecification(
            name: "validate-content",
            summary: "Load and validate game content (units and maps).",
            options: [
                .init(
                    name: "path",
                    placeholder: "directory",
                    summary: "Content directory with units.json and maps/; defaults to the bundled content.",
                    isRequired: false
                )
            ],
            flags: []
        ),
        CommandSpecification(
            name: "run",
            summary: "Fight one battle and print its outcome.",
            options: [
                .init(name: "config", placeholder: "path", summary: "Battle config JSON.", isRequired: true),
                .init(
                    name: "out", placeholder: "path", summary: "Write the full battle result as JSON.",
                    isRequired: false
                ),
            ],
            flags: []
        ),
        CommandSpecification(
            name: "verify",
            summary: "Fight the same battle config repeatedly and confirm every checksum matches.",
            options: [
                .init(name: "config", placeholder: "path", summary: "Battle config JSON.", isRequired: true),
                .init(
                    name: "runs", placeholder: "count",
                    summary: "Number of runs (default \(VerifyCommand.defaultRuns)).", isRequired: false
                ),
            ],
            flags: []
        ),
        CommandSpecification(
            name: "batch",
            summary: "Fight every entry of a config matrix across many seeds and write a CSV report.",
            options: [
                .init(
                    name: "matrix", placeholder: "path",
                    summary: #"Matrix JSON: {"entries":[{"name":..,"config":..}]}."#, isRequired: true
                ),
                .init(
                    name: "count", placeholder: "count", summary: "Seeds 0..<count per entry (default 1).",
                    isRequired: false),
                .init(
                    name: "jobs", placeholder: "count", summary: "Parallel worker count (default 1).", isRequired: false
                ),
                .init(name: "out", placeholder: "path", summary: "CSV file to write.", isRequired: true),
            ],
            flags: []
        ),
        CommandSpecification(
            name: "bench",
            summary: "Time repeated fights of a battle config.",
            options: [
                .init(name: "config", placeholder: "path", summary: "Battle config JSON.", isRequired: true),
                .init(
                    name: "runs", placeholder: "count",
                    summary: "Number of timed runs (default \(BenchCommand.defaultRuns)).", isRequired: false
                ),
            ],
            flags: []
        ),
    ]

    public static func run(arguments: [String], console: Console) -> Int32 {
        let command: ParsedCommand
        do {
            command = try ArgumentParser.parse(arguments, commands: commands)
        } catch {
            console.standardError("\(toolName): \(error)")
            console.standardError(ArgumentParser.usage(for: commands, toolName: toolName))
            return ExitCode.usage
        }

        switch command.name {
        case "gen-tables":
            return generateTables(command, console: console)
        case "validate-content":
            return validateContent(command, console: console)
        case "run":
            return RunCommand.execute(command, console: console)
        case "verify":
            return VerifyCommand.execute(command, console: console)
        case "batch":
            return BatchCommand.execute(command, console: console)
        case "bench":
            return BenchCommand.execute(command, console: console)
        default:
            console.standardOutput(ArgumentParser.usage(for: commands, toolName: toolName))
            return ExitCode.success
        }
    }

    private static func validateContent(_ command: ParsedCommand, console: Console) -> Int32 {
        let catalog: ContentCatalog
        do {
            if let path = command.value(for: "path") {
                catalog = try ContentCatalog.load(from: URL(fileURLWithPath: path, isDirectory: true))
            } else {
                catalog = try ContentCatalog.bundled()
            }
        } catch {
            console.standardError("\(toolName): \(error)")
            return ExitCode.failure
        }

        let unitList = catalog.units.map(\.id.rawValue).joined(separator: ", ")
        let mapList = catalog.maps.map(\.id.rawValue).joined(separator: ", ")
        console.standardOutput(
            "content is valid (version \(ContentVersion.current)): "
                + "\(catalog.units.count) unit types [\(unitList)], \(catalog.maps.count) maps [\(mapList)]"
        )
        return ExitCode.success
    }

    private static func generateTables(_ command: ParsedCommand, console: Console) -> Int32 {
        guard let path = command.value(for: "out") else {
            return ExitCode.usage
        }
        let url = URL(fileURLWithPath: path)
        let generated = TableGenerator.swiftSource()

        if command.isSet("check") {
            let existing = try? String(contentsOf: url, encoding: .utf8)
            guard existing == generated else {
                console.standardError("\(path) is out of date; run `\(toolName) gen-tables --out \(path)`")
                return ExitCode.failure
            }
            console.standardOutput("\(path) is up to date")
            return ExitCode.success
        }

        do {
            try Data(generated.utf8).write(to: url, options: .atomic)
        } catch {
            console.standardError("\(toolName): cannot write \(path): \(error.localizedDescription)")
            return ExitCode.failure
        }
        console.standardOutput("wrote \(path)")
        return ExitCode.success
    }
}
