import FermanCore
import SwiftUI

/// Every sound the game makes (ART-DIRECTION §7), synthesised by `Tools/sounds/synthesize.py` into
/// `Sounds/` under these names — a sound with variants ships as `<name>-1.wav` … `<name>-N.wav`, and a
/// repeated sound cycles through them so a volley doesn't sound like one sample on a loop.
///
/// "Close your eyes and still understand": each order the player can write has its own sound, and all of
/// them are things you'd hear at a sand table — paper, ink, wood, sand, small cast metal.
nonisolated enum SoundEffect: String, CaseIterable, Sendable {
    // Paper and ink.
    /// A seal pressed onto an order slip (the battle's opening choreography, brief §3.5).
    case stamp
    /// An order slip settling after it's moved in the stack.
    case paper
    /// A slip slapped down on the table: the battle's result.
    case slip
    /// Under the result slip: one calm strike for a held line, one dull knock for a broken one.
    case victory = "result-victory"
    case defeat = "result-defeat"
    /// A notch of the parameter dial.
    case dial
    /// The player's own order taking effect — the paper "tık" under every action sound (ART-DIRECTION §7).
    case order
    /// A cast figure set down on the table (army setup).
    case place

    // The player's orders, one sound per action.
    case advance = "action-advance"
    case retreat = "action-retreat"
    /// Both flanks; the cue is panned toward the side (`BattleSoundscape`).
    case flank = "action-flank"
    case hold = "action-hold"
    case focus = "action-focus"
    case regroup = "action-regroup"
    case scatter = "action-scatter"
    case cover = "action-cover"
    case guardCommander = "action-guard"

    // Combat.
    case release
    case land
    case hit
    case fall
    case rout
    case spearWall = "ability-spear-wall"
    case shieldWall = "ability-shield-wall"
    case charge = "ability-charge"

    var variantCount: Int {
        switch self {
        case .order, .release, .land, .fall: 3
        case .place: 2
        case .hit: 4
        default: 1
        }
    }

    /// The bundled files, without extension.
    var fileNames: [String] {
        variantCount == 1 ? [rawValue] : (1...variantCount).map { "\(rawValue)-\($0)" }
    }

    /// The sound of a player order taking effect. `nil` for `useAbility`: the ability's own sound
    /// (`spearWall`, `shieldWall`, `charge`) comes with it.
    static func action(_ kind: ActionKind) -> SoundEffect? {
        switch kind {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focus
        case .flankLeft, .flankRight: .flank
        case .regroup: .regroup
        case .useAbility: nil
        case .takeCover: .cover
        case .guardCommander: .guardCommander
        case .scatter: .scatter
        }
    }

    /// How it feels in the hand, if it's felt at all (`HapticFeel`).
    var feel: HapticFeel? {
        switch self {
        case .paper, .order: .soft
        case .stamp, .slip: .medium
        case .place: .rigid
        default: nil
        }
    }

    static func ability(_ ability: Ability) -> SoundEffect? {
        switch ability {
        case .spearWall: .spearWall
        case .shieldWall: .shieldWall
        case .charge: .charge
        // Each arrow of a volley already has its release and landing.
        case .volley: nil
        }
    }
}

/// How a sound feels in the hand, when it's one that should be felt at all (ART-DIRECTION §7): paper is
/// soft, the seal is medium, metal is rigid. Everything else — sand, wood, combat — is heard, not felt;
/// during a battle only the player's own orders and the result reach the hand.
nonisolated enum HapticFeel: Equatable, Sendable {
    case soft
    case medium
    case rigid

    var feedback: SensoryFeedback {
        switch self {
        case .soft: .impact(flexibility: .soft, intensity: 0.6)
        case .medium: .impact(weight: .medium, intensity: 0.8)
        case .rigid: .impact(flexibility: .rigid, intensity: 0.8)
        }
    }
}
