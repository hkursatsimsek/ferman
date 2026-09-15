import FermanSimCLI
import Foundation

exit(CommandLineTool.run(arguments: Array(CommandLine.arguments.dropFirst()), console: .system))
