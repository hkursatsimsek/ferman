import Foundation
import Testing

@testable import FermanCore

/// The 5 reference battles CLAUDE.md's test table calls the golden files (F0.12). Each `battle-NN.json` is a
/// complete, self-contained `BattleConfig`; `battle-NN.expected.json` pins the result it must keep producing.
///
/// This is the test that proves arm64 and x86_64 agree: CI runs it on both, against the exact same checksums
/// committed here. A mismatch means the determinism contract broke, not that the golden file is stale — see
/// CLAUDE.md's "Altın dosya kırıldığında" note before touching these numbers.
@Suite("Golden battles")
struct GoldenBattleTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Resources/Golden", isDirectory: true)

    private struct Expectation: Decodable {
        let checksum: UInt64
        let outcome: BattleOutcome
        let endReason: EndReason
        let tickCount: Int
        let survivorsPlayer: Int
        let survivorsEnemy: Int
    }

    @Test(arguments: 1...5)
    func reproducesTheRecordedResult(number: Int) throws {
        let name = String(format: "battle-%02d", number)
        let config = try JSONDecoder().decode(
            BattleConfig.self, from: try Data(contentsOf: Self.directory.appendingPathComponent("\(name).json")))
        let expected = try JSONDecoder().decode(
            Expectation.self,
            from: try Data(contentsOf: Self.directory.appendingPathComponent("\(name).expected.json")))

        let result = BattleSimulator.run(config, options: SimulationOptions(recordEvents: false))

        #expect(result.checksum == expected.checksum)
        #expect(result.outcome == expected.outcome)
        #expect(result.endReason == expected.endReason)
        #expect(result.tickCount == expected.tickCount)
        #expect(result.survivorsPlayer == expected.survivorsPlayer)
        #expect(result.survivorsEnemy == expected.survivorsEnemy)
    }
}
