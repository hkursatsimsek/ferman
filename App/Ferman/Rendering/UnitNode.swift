import FermanCore
import SpriteKit

/// One pooled node per unit, created once when `BattleScene` learns the roster from the event stream
/// and reused for the rest of the replay — no per-frame node creation (F1.4's "kare başına tahsis yok").
///
/// A cast miniature seen from above (D24): the figure sprite turns to face its direction, the
/// contact shadow under it is a separate sprite so it can stay on the table while the figure hops
/// (D27). Figures, shadows and ring come from one atlas so they batch. Every frame `BattleScene` hands
/// it a `FigurePose`; the node keeps no animation state of its own.
final class UnitNode: SKNode {
    let unitID: UnitID
    let unitType: UnitTypeID
    let team: Team

    private let shadow: SKSpriteNode
    private let figure: SKSpriteNode
    private let selectionRing: SKSpriteNode
    private let spark: SKSpriteNode
    private let seal: SKSpriteNode
    private let poseTextures: [UnitPose: SKTexture]
    private let shadowTexture: SKTexture
    private let fallenShadowTexture: SKTexture

    /// Figures share one atlas (`Assets.xcassets/Units.spriteatlas`) — the whole army in a few draw calls.
    private static let atlas = SKTextureAtlas(named: UnitArt.atlasName)
    private static let canvasSize = CGSize(width: UnitArt.canvasPoints, height: UnitArt.canvasPoints)
    private static let paper = SKColor(red: 0xD6 / 255, green: 0xD0 / 255, blue: 0xC2 / 255, alpha: 1)
    private static let sand = SKColor(red: 0x5E / 255, green: 0x6A / 255, blue: 0x63 / 255, alpha: 1)
    private static let sparkColor = SKColor(red: 0x6F / 255, green: 0xE3 / 255, blue: 0xF5 / 255, alpha: 1)

    /// Hit-test radius in scene points: generous, since a figure's base is a fraction of a fingertip.
    static let touchRadius: CGFloat = 28

    /// Layers, relative to the node (effective z is the parent's plus these). `SpriteView` runs with
    /// `.ignoresSiblingOrder` so sprites batch, which leaves equal-z siblings in no particular order —
    /// without explicit layers the shadow drew over the figure.
    private enum Layer {
        static let shadow: CGFloat = -0.5
        static let figure: CGFloat = 0
        static let ring: CGFloat = 0.5
        static let spark: CGFloat = 3
        static let seal: CGFloat = 3.5
    }

    /// Where a standing figure and a fallen one sit among all units: every living shadow falls over the
    /// dead, and every living figure stands over every shadow.
    private static let standingZ: CGFloat = 1
    private static let fallenZ: CGFloat = 0.3

    init(unitID: UnitID, type: UnitTypeID, team: Team) {
        self.unitID = unitID
        self.unitType = type
        self.team = team
        var textures: [UnitPose: SKTexture] = [:]
        for pose in UnitPose.allCases {
            textures[pose] = Self.atlas.textureNamed(UnitArt.imageName(type: type, team: team, pose: pose))
        }
        poseTextures = textures
        shadowTexture = Self.atlas.textureNamed(UnitArt.shadowName(type: type))
        fallenShadowTexture = Self.atlas.textureNamed(UnitArt.shadowName(type: type, fallen: true))

        shadow = SKSpriteNode(texture: shadowTexture, size: Self.canvasSize)
        figure = SKSpriteNode(texture: textures[.base], size: Self.canvasSize)
        selectionRing = SKSpriteNode(texture: Self.atlas.textureNamed(UnitArt.selectionRingName), size: Self.canvasSize)
        spark = SKSpriteNode(texture: EffectTextures.spark)
        seal = SKSpriteNode(texture: EffectTextures.seal(ruleIndex: 0))

        super.init()
        shadow.zPosition = Layer.shadow
        figure.zPosition = Layer.figure
        selectionRing.zPosition = Layer.ring
        selectionRing.isHidden = true
        spark.zPosition = Layer.spark
        spark.color = Self.sparkColor
        spark.colorBlendFactor = 1
        spark.blendMode = .add
        spark.isHidden = true
        seal.zPosition = Layer.seal
        seal.isHidden = true
        for child in [shadow, figure, selectionRing, spark, seal] {
            addChild(child)
        }
        name = Self.nodeName(for: unitID)
        zPosition = Self.standingZ
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

    func apply(_ pose: FigurePose) {
        position = pose.position
        zPosition = pose.isFallen ? Self.fallenZ : Self.standingZ

        figure.texture = poseTextures[pose.pose]
        figure.zRotation = pose.rotation + pose.tilt
        // Lifted toward the lamp: a little larger, its shadow left behind on the table.
        let scale = (1 + 0.05 * pose.lift) * pose.pulse
        figure.xScale = scale
        figure.yScale = scale * pose.stretch * pose.squash
        if pose.flash > 0 {
            figure.color = Self.paper
            figure.colorBlendFactor = pose.flash
        } else {
            figure.color = Self.sand
            figure.colorBlendFactor = pose.dim
        }

        shadow.texture = pose.isFallen ? fallenShadowTexture : shadowTexture
        shadow.zRotation = pose.rotation
        shadow.alpha = 1 - 0.35 * pose.lift
        shadow.setScale(1 - 0.06 * pose.lift)
        selectionRing.isHidden = selectionRing.isHidden || pose.isFallen

        if let progress = pose.spark {
            spark.isHidden = false
            spark.setScale(0.6 + 0.9 * progress)
            spark.alpha = 1 - progress
        } else {
            spark.isHidden = true
        }

        if let stamp = pose.seal {
            seal.isHidden = false
            seal.texture = EffectTextures.seal(ruleIndex: stamp.ruleIndex)
            // Pressed down fast, then fades — the seal stays upright; only the figure turns.
            let press = min(1, stamp.progress / 0.15)
            seal.setScale(1.4 - 0.4 * press)
            seal.alpha = stamp.progress < 0.7 ? 1 : 1 - (stamp.progress - 0.7) / 0.3
            seal.position = CGPoint(x: 0, y: UnitArt.canvasPoints * 0.42)
        } else {
            seal.isHidden = true
        }
    }
}
