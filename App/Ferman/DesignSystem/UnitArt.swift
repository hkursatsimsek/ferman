import CoreGraphics
import FermanCore

/// A figure's cast pose (D24). One set per unit type and team, turned to face any direction by
/// rotation; there is no walk cycle — the hand moving the miniature is animated instead (D27).
nonisolated enum UnitPose: String, CaseIterable, Sendable {
    case base
    /// Mid-attack: spear thrust, bow drawn, shield bashed forward, horse reaching.
    case strike
    /// Holding an ability: spear wall, shield wall.
    case brace
    /// Knocked over; stays on the table (D27).
    case fallen
}

/// Names of the unit images in `Assets.xcassets/Units.spriteatlas` (D24, D25). The names follow from a
/// rule rather than generated code: `Tools/figures/figures.py` renders every one of them in Blender and
/// writes it under exactly this name. Shared by SwiftUI (`UnitToken`, via `Image`) and SpriteKit
/// (`UnitNode`, via the atlas).
nonisolated enum UnitArt {
    static let atlasName = "Units"

    /// Every figure image is a square canvas this many points across, base centred, facing up.
    static let canvasPoints: CGFloat = 48
    /// The player's round base, in canvas points — what a selection ring or a hit test sizes against.
    static let baseDiameterPoints: CGFloat = 17.6

    static let selectionRingName = "ring-selection"
    /// An arrow in flight, facing up like the figures, and the shadow it throws on the table.
    static let arrowName = "arrow"
    static let arrowShadowName = "shadow-arrow"

    static func imageName(type: UnitTypeID, team: Team, pose: UnitPose) -> String {
        "\(type.rawValue)-\(team.artMaterial)-\(pose.rawValue)"
    }

    /// Contact shadow under a figure, kept separate so it can stay on the table while the figure hops.
    static func shadowName(type: UnitTypeID, fallen: Bool = false) -> String {
        fallen ? "shadow-\(type.rawValue)-fallen" : "shadow-\(type.rawValue)"
    }
}

extension Team {
    /// The figure's material: the player's army is oxidised brass, the enemy's raw iron (brief §3.1).
    nonisolated var artMaterial: String {
        switch self {
        case .player: "brass"
        case .enemy: "iron"
        }
    }
}
