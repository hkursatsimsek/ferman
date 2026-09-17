import FermanCore
import FermanReplay
import Foundation

/// Turns a `BattleResult` and `DebriefAnalyzer`'s findings into the diagnosis sentence design brief
/// §4.6 wants ("Okçularının %70'i 12. saniyede aynı anda öldü.") — a teşhis, not a congratulation
/// (CLAUDE.md's tone rules). Pure text formatting, same separation as `OrderPhraseFormatter` (D21).
nonisolated enum DebriefInsightFormatter {
    static func title(for outcome: BattleOutcome) -> String {
        switch outcome {
        case .playerWin: String(localized: "Hat tutuldu.")
        case .enemyWin: String(localized: "Cephe yarıldı.")
        case .draw: String(localized: "Savaş berabere bitti.")
        }
    }

    /// Picks the largest death/morale cluster that happened to the *other* team from the outcome's
    /// point of view (why you won: the enemy broke; why you lost: your line broke) and phrases it. A
    /// draw, or a battle with no clean cluster, falls back to a generic sentence about `endReason`.
    static func diagnosis(insights: [DebriefInsight], outcome: BattleOutcome, endReason: EndReason) -> String {
        guard outcome != .draw else {
            return fallback(outcome: outcome, endReason: endReason)
        }
        let relevantTeam: Team = outcome == .playerWin ? .enemy : .player
        let describesOpponent = outcome == .playerWin

        let candidates: [(count: Int, tick: Int32, insight: DebriefInsight)] = insights.compactMap { insight in
            switch insight {
            case .deathCluster(let team, _, let tick, let unitIDs, _) where team == relevantTeam:
                (unitIDs.count, tick, insight)
            case .moraleCascade(let team, let tick, let unitIDs, _) where team == relevantTeam:
                (unitIDs.count, tick, insight)
            default:
                nil
            }
        }
        guard let best = candidates.max(by: { $0.count == $1.count ? $0.tick < $1.tick : $0.count < $1.count })
        else {
            return fallback(outcome: outcome, endReason: endReason)
        }
        return clusterSentence(best.insight, describesOpponent: describesOpponent)
    }

    private static func clusterSentence(_ insight: DebriefInsight, describesOpponent: Bool) -> String {
        let opponentPrefix = describesOpponent ? String(localized: "Düşman ") : ""
        switch insight {
        case .deathCluster(_, let unitType, let tick, _, let fractionOfType):
            let percent = (fractionOfType * 100).rounded()
            let subject = opponentPrefix + OrderPhraseFormatter.pluralPossessiveGenitiveUnitName(unitType)
            return String(
                localized:
                    "\(subject) %\(TurkishNumberSuffix.possessive(percent)) \(secondsPhrase(tick)) aynı anda öldü."
            )
        case .moraleCascade(_, let tick, _, let fractionOfTeam):
            let percent = (fractionOfTeam * 100).rounded()
            let subject = opponentPrefix + String(localized: "ordusunun")
            return String(
                localized:
                    "\(subject) %\(TurkishNumberSuffix.possessive(percent)) \(secondsPhrase(tick)) aynı anda morali bozuldu."
            )
        case .unusedRule, .dominantRule, .concurrentActivation, .keyMoment:
            return ""
        }
    }

    private static func secondsPhrase(_ tick: Int32) -> String {
        let seconds = Int(tick) / BattleConfig.ticksPerSecond
        return String(localized: "\(seconds). saniyede")
    }

    private static func fallback(outcome: BattleOutcome, endReason: EndReason) -> String {
        switch (outcome, endReason) {
        case (.playerWin, .elimination): String(localized: "Düşman ordusu yok edildi.")
        case (.playerWin, .rout): String(localized: "Düşman ordusu dağıldı.")
        case (.playerWin, .timeLimit): String(localized: "Hat, süre sonunda tutuldu.")
        case (.enemyWin, .elimination): String(localized: "Ordun yok edildi.")
        case (.enemyWin, .rout): String(localized: "Ordun dağıldı.")
        case (.enemyWin, .timeLimit): String(localized: "Hat, süre sonunda yarıldı.")
        case (.draw, _): String(localized: "Savaş berabere bitti.")
        }
    }
}
