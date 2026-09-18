import FermanCore
import SpriteKit

/// One pooled node per unit, created once when `BattleScene` learns the roster from the event stream
/// and reused for the rest of the replay — no per-frame node creation (F1.4's "kare başına tahsis yok").
///
/// A cast miniature seen from above (D24): the figure sprite turns to face its direction, the
/// contact shadow under it is a separate sprite so it can stay on the table while the figure hops
/// (D27). All three sprites come from one atlas so they batch.
final class UnitNode: SKNode {
    let unitID: UnitID
    let unitType: UnitTypeID
    let team: Team

    private let shadow: SKSpriteNode
    private let figure: SKSpriteNode
    private let selectionRing: SKSpriteNode

    /// Figures share one atlas (`Assets.xcassets/Units.spriteatlas`) — the whole army in a few draw calls.
    private static let atlas = SKTextureAtlas(named: UnitArt.atlasName)
    private static let canvasSize = CGSize(width: UnitArt.canvasPoints, height: UnitArt.canvasPoints)

    /// Hit-test radius in scene points: generous, since a figure's base is a fraction of a fingertip.
    static let touchRadius: CGFloat = 28

    init(unitID: UnitID, type: UnitTypeID, team: Team) {
        self.unitID = unitID
        self.unitType = type
        self.team = team
        shadow = SKSpriteNode(
            texture: Self.atlas.textureNamed(UnitArt.shadowName(type: type)), size: Self.canvasSize)
        figure = SKSpriteNode(
            texture: Self.atlas.textureNamed(UnitArt.imageName(type: type, team: team, pose: .base)),
            size: Self.canvasSize)
        selectionRing = SKSpriteNode(
            texture: Self.atlas.textureNamed(UnitArt.selectionRingName), size: Self.canvasSize)
        selectionRing.isHidden = true
        // Explicit layers, not child order: `SpriteView` runs with `.ignoresSiblingOrder` (so sprites
        // batch), which leaves equal-z siblings in no particular order — the shadow drew over the
        // figure. Effective z is the parent's plus these, so every unit's shadow sits under every
        // unit's figure, not just its own.
        shadow.zPosition = -0.5
        figure.zPosition = 0
        selectionRing.zPosition = 0.5

        super.init()
        addChild(shadow)
        addChild(figure)
        addChild(selectionRing)
        name = Self.nodeName(for: unitID)
        zPosition = 1
        // Until facing is animated (G7): each army faces the other across the upright table (D26).
        figure.zRotation = team == .player ? 0 : .pi
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UnitNode does not support archiving")
    }

    var isSelected: Bool {
        get { !selectionRing.isHidden }
        set { selectionRing.isHidden = !newValue }
    }

    static func nodeName(for unitID: UnitID) -> String {
        "unit-\(unitID.rawValue)"
    }
}
