/// Hand-written parsing for `fermansim <command> [--option value] [--flag]`.
///
/// Written in-house because the project takes no package dependencies before Phase 5 (CLAUDE.md rule 6).
public struct CommandSpecification: Sendable {
    public struct Option: Sendable {
        public let name: String
        public let placeholder: String
        public let summary: String
        public let isRequired: Bool
    }

    public struct Flag: Sendable {
        public let name: String
        public let summary: String
    }

    public let name: String
    public let summary: String
    public let options: [Option]
    public let flags: [Flag]
}

public struct ParsedCommand: Equatable, Sendable {
    public let name: String
    private let values: [String: String]
    private let setFlags: Set<String>

    init(name: String, values: [String: String], setFlags: Set<String>) {
        self.name = name
        self.values = values
        self.setFlags = setFlags
    }

    public func value(for option: String) -> String? {
        values[option]
    }

    public func requiredValue(for option: String) throws(ArgumentError) -> String {
        guard let value = values[option] else {
            throw .missingRequiredOption(command: name, option: option)
        }
        return value
    }

    public func integer(for option: String, in range: ClosedRange<Int>) throws(ArgumentError) -> Int? {
        guard let text = values[option] else {
            return nil
        }
        guard let number = Int(text), range.contains(number) else {
            throw .invalidValue(option: option, value: text, expected: "an integer in \(range)")
        }
        return number
    }

    public func isSet(_ flag: String) -> Bool {
        setFlags.contains(flag)
    }
}

public enum ArgumentError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(command: String, option: String)
    case missingValue(option: String)
    case duplicateOption(String)
    case unexpectedArgument(String)
    case missingRequiredOption(command: String, option: String)
    case invalidValue(option: String, value: String, expected: String)

    public var description: String {
        switch self {
        case .missingCommand:
            "no command given"
        case .unknownCommand(let command):
            "unknown command '\(command)'"
        case .unknownOption(let command, let option):
            "'\(command)' has no option '--\(option)'"
        case .missingValue(let option):
            "option '--\(option)' needs a value"
        case .duplicateOption(let option):
            "option '--\(option)' was given more than once"
        case .unexpectedArgument(let argument):
            "unexpected argument '\(argument)'"
        case .missingRequiredOption(let command, let option):
            "'\(command)' requires '--\(option)'"
        case .invalidValue(let option, let value, let expected):
            "'--\(option) \(value)' is invalid; expected \(expected)"
        }
    }
}

public enum ArgumentParser {
    public static func parse(
        _ arguments: [String],
        commands: [CommandSpecification]
    ) throws(ArgumentError) -> ParsedCommand {
        guard let commandName = arguments.first else {
            throw .missingCommand
        }
        guard let specification = commands.first(where: { $0.name == commandName }) else {
            throw .unknownCommand(commandName)
        }

        var values: [String: String] = [:]
        var setFlags: Set<String> = []
        var remaining = arguments.dropFirst()

        while let argument = remaining.popFirst() {
            guard argument.hasPrefix("--"), argument.count > 2 else {
                throw .unexpectedArgument(argument)
            }
            let name = String(argument.dropFirst(2))
            if specification.flags.contains(where: { $0.name == name }) {
                guard setFlags.insert(name).inserted else {
                    throw .duplicateOption(name)
                }
            } else if specification.options.contains(where: { $0.name == name }) {
                guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                    throw .missingValue(option: name)
                }
                guard values.updateValue(value, forKey: name) == nil else {
                    throw .duplicateOption(name)
                }
            } else {
                throw .unknownOption(command: commandName, option: name)
            }
        }

        for option in specification.options where option.isRequired && values[option.name] == nil {
            throw .missingRequiredOption(command: commandName, option: option.name)
        }
        return ParsedCommand(name: commandName, values: values, setFlags: setFlags)
    }

    public static func usage(for commands: [CommandSpecification], toolName: String) -> String {
        var lines = ["usage: \(toolName) <command> [options]", "", "commands:"]
        for command in commands {
            lines.append("  \(command.name)  \(command.summary)")
            for option in command.options {
                let requirement = option.isRequired ? "" : " (optional)"
                lines.append("      --\(option.name) <\(option.placeholder)>  \(option.summary)\(requirement)")
            }
            for flag in command.flags {
                lines.append("      --\(flag.name)  \(flag.summary)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
