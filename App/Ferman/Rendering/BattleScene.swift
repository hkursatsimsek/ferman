import FermanCore
import FermanReplay
import SpriteKit
import UIKit
import os

/// Draws the replay. Knows nothing about conditions, actions or why a unit is where it is — only
/// where it is and what just happened to it (CLAUDE.md rule 4).
///
/// Every frame is a pure function of the clock's replay time (D27): each figure's pose comes from
/// `FigureMotion`, arrows included, and nothing here accumulates animation state. Seeking, speed changes
/// and an offline `SKRenderer` clip (D15) all land on the same picture.
final class BattleScene: SKScene {
    private let timeline: ReplayTimeline
    private let clock: ReplayClock
    private let projection: BoardProjection
    private let motion: FigureMotion
    var onUnitTapped: ((UnitID) -> Void)?
    /// The order a player unit is following right now, for the tapped unit's bubble. Words come from the
    /// app (`BattleModel.currentOrder(of:)`); the scene only draws them.
    var currentOrder: ((UnitID) -> OrderStack.Item?)?
    /// Keeps the hand-moved flourishes (hops, lunges, knockback, tremble) off; poses and flashes stay.
    var reduceMotion = false

    private var unitNodes: [UnitID: UnitNode] = [:]
    private var arrowPool: [(arrow: SKSpriteNode, shadow: SKSpriteNode)] = []
    private var lastUpdateTime: TimeInterval?
    private var selectedUnit: UnitID?
    private let orderBubble = SKSpriteNode()
    private var orderBubbleKey: String?

    private static let arrowPoolSize = 64

    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hksimsek.FERMAN", category: "BattleScene")

    init(config: BattleConfig, timeline: ReplayTimeline, clock: ReplayClock) {
        self.timeline = timeline
        self.clock = clock
        let projection = BoardProjection.table(for: config.map)
        self.projection = projection
        self.motion = FigureMotion(result: timeline.result, config: config, projection: projection)
        // Upright (D26): the landscape map is drawn a quarter turn counter-clockwise, player at the
        // bottom — every position below goes through `projection`.
        super.init(size: projection.boardSize)

        // `.aspectFit`: the sand table (design brief §4.5 — "Tam ekran kum masası") must show the
        // whole battlefield at once. `anchorPoint` stays `.zero`, so every node position in this file
        // is bottom-left-relative; `BattleSceneView` locks its own aspect ratio to the board's so
        // the scene fills it exactly.
        backgroundColor = SKColor(red: 0x0F / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 1)
        scaleMode = .aspectFit
        isUserInteractionEnabled = true

        addChild(Self.makeSandTable(map: config.map, projection: projection))
        orderBubble.zPosition = 10
        orderBubble.anchorPoint = CGPoint(x: 0.5, y: 0)
        orderBubble.isHidden = true
        addChild(orderBubble)
        buildUnitPool()
        buildArrowPool()
        drawFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BattleScene does not support archiving")
    }

    // MARK: - Setup

    /// The whole table — rim, lamp-lit sand, terrain, grid — is one pre-baked texture (`TerrainBaker`),
    /// drawn once per frame as a single sprite.
    private static func makeSandTable(map: BattleMap, projection: BoardProjection) -> SKSpriteNode {
        let size = projection.boardSize
        let node: SKSpriteNode
        if let image = TerrainBaker.bake(
            map: map, projection: projection, pixelsPerPoint: TerrainBaker.battlePixelsPerPoint)
        {
            node = SKSpriteNode(texture: SKTexture(cgImage: image), size: size)
        } else {
            node = SKSpriteNode(color: SKColor(red: 0x5E / 255, green: 0x6A / 255, blue: 0x63 / 255, alpha: 1), size: size)
        }
        node.anchorPoint = .zero
        node.position = .zero
        node.zPosition = -1
        return node
    }

    private func buildUnitPool() {
        for unitID in motion.unitIDs {
            guard let track = motion.figures[unitID]?.track else { continue }
            let node = UnitNode(unitID: unitID, type: track.unitType, team: track.team)
            unitNodes[unitID] = node
            addChild(node)
        }
    }

    /// Arrows fly above the standing figures, their shadows on the table below them.
    private func buildArrowPool() {
        arrowPool = (0..<Self.arrowPoolSize).map { _ in
            let arrow = SKSpriteNode(texture: EffectTextures.arrow)
            arrow.zPosition = 2.5
            arrow.isHidden = true
            let shadow = SKSpriteNode(texture: EffectTextures.arrowShadow)
            shadow.zPosition = 0.8
            shadow.isHidden = true
            addChild(shadow)
            addChild(arrow)
            return (arrow, shadow)
        }
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let previous = lastUpdateTime else { return }

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("update", id: signpostID)
        defer { signposter.endInterval("update", state) }

        clock.advance(by: currentTime - previous)
        drawFrame()
    }

    private func drawFrame() {
        let tick = clock.fractionalTick
        for (unitID, node) in unitNodes {
            guard let pose = motion.pose(of: unitID, atTick: tick, reduceMotion: reduceMotion) else { continue }
            node.apply(pose)
        }

        let arrows = motion.arrows(atTick: tick)
        for (index, sprites) in arrowPool.enumerated() {
            guard index < arrows.count else {
                sprites.arrow.isHidden = true
                sprites.shadow.isHidden = true
                continue
            }
            let arrow = arrows[index]
            sprites.arrow.isHidden = false
            sprites.arrow.position = arrow.position
            sprites.arrow.zRotation = arrow.rotation
            sprites.arrow.setScale(1 + 0.25 * arrow.height)
            sprites.shadow.isHidden = false
            sprites.shadow.position = arrow.groundPosition
            sprites.shadow.zRotation = arrow.rotation
            sprites.shadow.alpha = 1 - 0.5 * arrow.height
        }

        updateOrderBubble()
    }

    /// Follows the selected figure; says which order it's on, redrawn only when that changes.
    private func updateOrderBubble() {
        guard let unit = selectedUnit, let node = unitNodes[unit],
            motion.figures[unit]?.track.isAlive(at: clock.currentTick) ?? false
        else {
            deselect()
            return
        }
        guard let order = currentOrder?(unit) else {
            orderBubble.isHidden = true
            return
        }
        let key = "\(order.priority)|\(order.action)"
        if key != orderBubbleKey {
            orderBubbleKey = key
            let texture = EffectTextures.orderBubble(
                caption: String(localized: "şu an uyguluyor"), priority: order.priority, action: order.action)
            orderBubble.texture = texture
            orderBubble.size = texture.size()
        }
        orderBubble.isHidden = false
        orderBubble.position = CGPoint(x: node.position.x, y: node.position.y + UnitArt.canvasPoints * 0.4)
    }

    private func deselect() {
        if let unit = selectedUnit { unitNodes[unit]?.isSelected = false }
        selectedUnit = nil
        orderBubble.isHidden = true
        orderBubbleKey = nil
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        deselect()
        guard let unitNode = nearestUnit(to: point) else { return }
        onUnitTapped?(unitNode.unitID)
        // Only the player's figures carry orders the player wrote — an enemy tap just closes the bubble.
        guard unitNode.team == .player else { return }
        selectedUnit = unitNode.unitID
        unitNode.isSelected = true
        updateOrderBubble()
    }

    /// The closest standing figure within `UnitNode.touchRadius` — a figure is too small to hit by its
    /// pixels, and a tap between two of them should still pick one.
    private func nearestUnit(to point: CGPoint) -> UnitNode? {
        let tick = clock.currentTick
        var nearest: (node: UnitNode, distance: CGFloat)?
        for (unitID, node) in unitNodes where motion.figures[unitID]?.track.isAlive(at: tick) ?? false {
            let distance = hypot(node.position.x - point.x, node.position.y - point.y)
            guard distance <= UnitNode.touchRadius else { continue }
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (node, distance)
            }
        }
        return nearest?.node
    }
}
