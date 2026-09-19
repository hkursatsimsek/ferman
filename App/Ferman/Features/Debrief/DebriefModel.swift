import FermanCore
import FermanReplay
import Observation

/// One order's row on the debrief screen: its text (D21, via `OrderPhraseFormatter`) plus how often
/// it actually fired. `neverFired` drives design brief §4.6's "Bu emir hiç çalışmadı." warning — the
/// single most valuable line on the screen, since it points straight at the player's own mistake.
struct DebriefOrderRow: Identifiable, Sendable, Hashable {
    let id: Int
    let priority: Int
    let condition: String
    let action: String
    let fireCount: Int
    /// Share of this program's total activations (same formula as `BattleModel.TriggerRow`, so the
    /// bar reads the same way it did live during the battle).
    let fraction: Double
    let neverFired: Bool
}

struct DebriefUnitSection: Identifiable, Sendable, Hashable {
    let unitType: UnitTypeID
    var id: UnitTypeID { unitType }
    let displayName: String
    let rows: [DebriefOrderRow]
    /// A finding about this program as a whole (`DebriefInsightFormatter.dominantNote`).
    var note: String?
}

/// The battle laid out along one line (Faz 1.5 G11): when the player's orders took hold, when their
/// figures fell. The diagnosis's moment is marked on it.
struct DebriefTape: Sendable, Hashable {
    let length: Int32
    let orderTicks: [Int32]
    let lossTicks: [Int32]
}

/// SavaşSonrasıAnalizi (design brief §4.6) — "a diagnosis screen, not a victory screen." Pure
/// function of the battle that just ran: a `BattleConfig` (for the player's own programs and unit
/// catalog) and its `BattleResult`. No re-simulation, no mutable state — everything is computed once
/// in `init`.
@Observable
@MainActor
final class DebriefModel {
    let isVictory: Bool
    let title: String
    let diagnosis: String
    /// The tick the diagnosis describes, for "O anı izle".
    let momentTick: Int32?
    let sections: [DebriefUnitSection]
    let tape: DebriefTape
    /// The battle's last frame, for the small photograph of the table: fallen figures where they fell.
    let config: BattleConfig
    let timeline: ReplayTimeline
    let finalClock: ReplayClock

    init(config: BattleConfig, result: BattleResult) {
        self.isVictory = result.outcome == .playerWin
        self.title = DebriefInsightFormatter.title(for: result.outcome)
        let insights = DebriefAnalyzer.analyze(result: result)
        self.diagnosis = DebriefInsightFormatter.diagnosis(
            insights: insights, outcome: result.outcome, endReason: result.endReason)
        self.momentTick = DebriefInsightFormatter.diagnosisMoment(insights: insights, outcome: result.outcome)
        self.config = config
        let timeline = ReplayTimeline(result: result)
        self.timeline = timeline
        let clock = ReplayClock(tickCount: Int32(result.tickCount) + BattleModel.settleTicks)
        clock.seek(to: clock.tickCount)
        clock.isPlaying = false
        self.finalClock = clock
        self.tape = Self.tape(of: result)

        self.sections = config.player.programs.map { program in
            let counts =
                result.ruleFireCounts.first { $0.team == .player && $0.unitType == program.unitType }?.counts ?? []
            let total = max(1, counts.reduce(0, +))
            let ability = config.unitCatalog.first { $0.id == program.unitType }?.ability

            let rows = program.rules.indices.map { index -> DebriefOrderRow in
                let rule = program.rules[index]
                let count = index < counts.count ? counts[index] : 0
                return DebriefOrderRow(
                    id: index, priority: index + 1,
                    condition: OrderPhraseFormatter.condition(rule.condition),
                    action: OrderPhraseFormatter.action(rule.action, ability: ability),
                    fireCount: count, fraction: Double(count) / Double(total), neverFired: count == 0)
            }
            return DebriefUnitSection(
                unitType: program.unitType, displayName: OrderPhraseFormatter.unitTypeName(program.unitType),
                rows: rows, note: DebriefInsightFormatter.dominantNote(insights: insights, unitType: program.unitType))
        }
    }

    private static func tape(of result: BattleResult) -> DebriefTape {
        var players = Set<UnitID>()
        var orders: [Int32] = []
        var losses: [Int32] = []
        for event in result.events {
            switch event.kind {
            case .spawn(let unit, _, .player, _): players.insert(unit)
            case .ruleActivated(let unit, _) where players.contains(unit): orders.append(event.tick)
            case .death(let unit) where players.contains(unit): losses.append(event.tick)
            default: break
            }
        }
        return DebriefTape(length: Int32(max(result.tickCount, 1)), orderTicks: orders, lossTicks: losses)
    }
}
