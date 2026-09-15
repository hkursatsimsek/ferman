import Testing

@Suite("Determinism invariants")
struct InvariantTests {
    @Test func coreSourcesHonorTheDeterminismContract() throws {
        let sources = try CoreSources.load()
        try #require(!sources.isEmpty, "No FermanCore sources were found under \(CoreSources.packageRoot.path)")

        let violations = sources.flatMap { CoreInvariants.violations(in: $0.contents, file: $0.relativePath) }
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test(arguments: [
        "import SwiftUI",
        "@testable import GameplayKit",
        "import struct simd.SIMD2",
        "let speed: Float = 1",
        "let ratio = Double(3) / 2",
        "var position: SIMD2<Int32>",
        "let now = Date()",
        "let deadline = DispatchTime.now()",
        "let roll = Int.random(in: 1...6)",
        "let unit = units.randomElement()",
        "let order = units.shuffled()",
        "var generator = SystemRandomNumberGenerator()",
        "let bucket = unit.hashValue % 8",
        "let id = UUID()",
        "let angle = atan2(y, x)",
        "let length = sqrt(value)",
        "async let left = simulate()",
        "await Task.yield()",
        "struct Box: @unchecked Sendable {}",
        "nonisolated(unsafe) var shared = 0",
        "final class UnitCache {}",
        "let pointer = UnsafeMutablePointer<Int32>.allocate(capacity: 4)",
        "let label = \"tick \\(Double(tick) / 30)\"",
    ])
    func flagsForbiddenConstructs(snippet: String) {
        #expect(!CoreInvariants.violations(in: snippet, file: "Snippet.swift").isEmpty)
    }

    @Test(arguments: [
        "import Foundation",
        "// Float and Double are banned; Date() too",
        "/* nested /* Task */ comment with UUID() */ let tick = 0",
        "/// Uses sin(x) tables instead of Double math",
        "let message = \"no Float, no Date(), no async\"",
        "let raw = #\"a \"Double\" inside a raw string\"#",
        "let text = \"\"\"\n  Float\n  \"\"\"",
        "let sine = FixedMath.sin(angle)",
        "static func sin(_ angle: FixedAngle) -> Fixed { quarterWave(angle) }",
        "let label = \"tick \\(tick)\"",
        "let floating = isFloating",
        "struct DateStamp { let tick: Int }",
    ])
    func allowsCompliantCode(snippet: String) {
        let violations = CoreInvariants.violations(in: snippet, file: "Snippet.swift")
        #expect(violations.isEmpty, "\(violations.map(\.description))")
    }

    @Test func reportsTheLineOfEachViolation() {
        let source = """
            import Foundation

            // Float in a comment is fine.
            let speed: Float = 1
            """
        let violations = CoreInvariants.violations(in: source, file: "Speed.swift")
        #expect(violations.map(\.line) == [4])
    }
}
