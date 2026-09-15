import Testing

@testable import FermanSimCLI

@Suite("ArgumentParser")
struct ArgumentParserTests {
    static let commands = [
        CommandSpecification(
            name: "verify",
            summary: "Verify determinism.",
            options: [
                .init(name: "config", placeholder: "path", summary: "Battle config.", isRequired: true),
                .init(name: "runs", placeholder: "count", summary: "Run count.", isRequired: false),
            ],
            flags: [.init(name: "quiet", summary: "No progress.")]
        )
    ]

    @Test func parsesOptionsAndFlags() throws {
        let command = try ArgumentParser.parse(
            ["verify", "--config", "battle.json", "--quiet", "--runs", "1000"],
            commands: Self.commands
        )
        #expect(command.name == "verify")
        #expect(command.value(for: "config") == "battle.json")
        #expect(try command.integer(for: "runs", in: 1...1_000_000) == 1_000)
        #expect(command.isSet("quiet"))
    }

    @Test func optionalValuesMayBeOmitted() throws {
        let command = try ArgumentParser.parse(["verify", "--config", "battle.json"], commands: Self.commands)
        #expect(try command.integer(for: "runs", in: 1...10) == nil)
        #expect(!command.isSet("quiet"))
    }

    @Test(
        arguments: [
            ([], ArgumentError.missingCommand),
            (["simulate"], .unknownCommand("simulate")),
            (["verify"], .missingRequiredOption(command: "verify", option: "config")),
            (["verify", "--config"], .missingValue(option: "config")),
            (["verify", "--config", "--quiet"], .missingValue(option: "config")),
            (["verify", "--config", "a.json", "--config", "b.json"], .duplicateOption("config")),
            (["verify", "--config", "a.json", "--quiet", "--quiet"], .duplicateOption("quiet")),
            (["verify", "--config", "a.json", "--seed", "3"], .unknownOption(command: "verify", option: "seed")),
            (["verify", "battle.json"], .unexpectedArgument("battle.json")),
            (["verify", "--"], .unexpectedArgument("--")),
        ] as [([String], ArgumentError)])
    func rejectsMalformedArguments(arguments: [String], expected: ArgumentError) {
        #expect(throws: expected) {
            try ArgumentParser.parse(arguments, commands: Self.commands)
        }
    }

    @Test func rejectsOutOfRangeIntegers() throws {
        let command = try ArgumentParser.parse(
            ["verify", "--config", "a.json", "--runs", "0"],
            commands: Self.commands
        )
        #expect(throws: ArgumentError.invalidValue(option: "runs", value: "0", expected: "an integer in 1...10")) {
            try command.integer(for: "runs", in: 1...10)
        }
    }

    @Test func usageListsEveryCommandOptionAndFlag() {
        let usage = ArgumentParser.usage(for: Self.commands, toolName: "fermansim")
        #expect(usage.contains("verify"))
        #expect(usage.contains("--config <path>"))
        #expect(usage.contains("--runs <count>  Run count. (optional)"))
        #expect(usage.contains("--quiet"))
    }
}
