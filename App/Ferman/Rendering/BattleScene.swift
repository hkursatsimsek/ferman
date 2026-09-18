import FermanCore
import FermanReplay
import SpriteKit
import UIKit
import os

/// Draws `ReplayFrame`s. Knows nothing about conditions, actions or why a unit
/// is where it is — only where it is (CLAUDE.md rule 4).
final class BattleScene: SKScene {
    private let timeline: ReplayTimeline
    private let clock: ReplayClock
    private let projection: BoardProjection
    var onUnitTapped: ((UnitID) -> Void)?

    private var unitNodes: [UnitID: UnitNode] = [:]
    private var eventsByTick: [Int32: [BattleEvent]] = [:]
    private var lastProcessedTick: Int32 = -1
    private var lastUpdateTime: TimeInterval?

    private var sparkPool: [SKEmitterNode] = []
    private var nextSparkIndex = 0
    private let tappedUnitLabel: SKLabelNode

    private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hksimsek.FERMAN", category: "BattleScene")

    init(map: BattleMap, timeline: ReplayTimeline, clock: ReplayClock) {
        self.timeline = timeline
        self.clock = clock
        self.projection = BoardProjection.table(for: map)
        tappedUnitLabel = Self.makeTappedUnitLabel()

        // Upright (D26): the landscape map is drawn a quarter turn counter-clockwise, player at the
        // bottom — every position below goes through `projection`.
        let sceneSize = projection.boardSize
        super.init(size: sceneSize)

        // `.aspectFit`: the sand table (design brief §4.5 — "Tam ekran kum masası") must show the
        // whole battlefield at once. `anchorPoint` stays `.zero`, so every node position in this file
        // is bottom-left-relative; `BattleSceneView` locks its own aspect ratio to the board's so
        // the scene fills it exactly.
        backgroundColor = SKColor(red: 0x0F / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 1)
        scaleMode = .aspectFit
        isUserInteractionEnabled = true

        addChild(Self.makeSandTable(map: map, projection: projection))
        addChild(tappedUnitLabel)
        buildEventIndex()
        buildUnitPool()
        buildSparkPool()
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

    private static func makeTappedUnitLabel() -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Archivo-Medium")
        label.fontSize = 12
        label.fontColor = SKColor(red: 0xD6 / 255, green: 0xD0 / 255, blue: 0xC2 / 255, alpha: 1)
        label.isHidden = true
        label.zPosition = 10
        return label
    }

    private func buildEventIndex() {
        for event in timeline.result.events {
            eventsByTick[event.tick, default: []].append(event)
        }
    }

    private func buildUnitPool() {
        for event in timeline.result.events {
            guard case .spawn(let unit, let type, let team, _) = event.kind else { continue }
            let node = UnitNode(unitID: unit, type: type, team: team)
            node.isHidden = true
            node.zPosition = 1
            unitNodes[unit] = node
            addChild(node)
        }
    }

    private func buildSparkPool() {
        sparkPool = (0..<6).map { _ in Self.makeSparkEmitter() }
        for emitter in sparkPool {
            emitter.isHidden = true
            addChild(emitter)
        }
    }

    private static func makeSparkEmitter() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: sparkParticleImage)
        emitter.particleBirthRate = 400
        emitter.numParticlesToEmit = 14
        emitter.particleLifetime = 0.35
        emitter.particleLifetimeRange = 0.15
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 30
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -3
        emitter.particleColor = SKColor(red: 0x6F / 255, green: 0xE3 / 255, blue: 0xF5 / 255, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.zPosition = 5
        return emitter
    }

    private static let sparkParticleImage: UIImage = {
        let diameter: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        return renderer.image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            guard
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
            else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: diameter / 2, y: diameter / 2), startRadius: 0,
                endCenter: CGPoint(x: diameter / 2, y: diameter / 2), endRadius: diameter / 2,
                options: []
            )
        }
    }()

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let previous = lastUpdateTime else { return }

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("update", id: signpostID)
        defer { signposter.endInterval("update", state) }

        clock.advance(by: currentTime - previous)
        applyEventsSinceLastFrame()
        applyInterpolatedPositions()
    }

    private func applyEventsSinceLastFrame() {
        let upperTick = clock.currentTick
        guard upperTick > lastProcessedTick else { return }
        var tick = lastProcessedTick + 1
        while tick <= upperTick {
            for event in eventsByTick[tick] ?? [] {
                handle(event)
            }
            tick += 1
        }
        lastProcessedTick = upperTick
    }

    private func handle(_ event: BattleEvent) {
        guard case .ruleActivated(let unit, _) = event.kind else { return }
        fireSpark(on: unit)
    }

    private func fireSpark(on unit: UnitID) {
        guard let node = unitNodes[unit] else { return }
        let emitter = sparkPool[nextSparkIndex]
        nextSparkIndex = (nextSparkIndex + 1) % sparkPool.count
        emitter.position = node.position
        emitter.isHidden = false
        emitter.resetSimulation()
    }

    private func applyInterpolatedPositions() {
        let baseTick = clock.currentTick
        let fraction = CGFloat(clock.fractionalTick - Double(baseTick))
        let current = timeline.frame(at: baseTick)
        let next = timeline.frame(at: baseTick + 1)

        for (unitID, node) in unitNodes {
            guard current.livingUnits.contains(unitID), let currentPosition = current.positions[unitID] else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let from = projection.scenePoint(currentPosition)
            let to = next.positions[unitID].map(projection.scenePoint) ?? from
            node.position = from.interpolated(to: to, fraction: fraction)
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        guard let unitNode = nearestUnit(to: point) else {
            tappedUnitLabel.isHidden = true
            return
        }
        onUnitTapped?(unitNode.unitID)
        showLabel(for: unitNode)
    }

    /// The closest visible figure within `UnitNode.touchRadius` — a figure is too small to hit by its
    /// pixels, and a tap between two of them should still pick one.
    private func nearestUnit(to point: CGPoint) -> UnitNode? {
        var nearest: (node: UnitNode, distance: CGFloat)?
        for node in unitNodes.values where !node.isHidden {
            let distance = hypot(node.position.x - point.x, node.position.y - point.y)
            guard distance <= UnitNode.touchRadius else { continue }
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (node, distance)
            }
        }
        return nearest?.node
    }

    private func showLabel(for node: UnitNode) {
        let frame = timeline.frame(at: clock.currentTick)
        let ruleIndex = frame.activeRuleIndex[node.unitID]
        let unitType = frame.unitTypes[node.unitID]?.rawValue ?? "?"
        tappedUnitLabel.text = ruleIndex.map { "\(unitType) · \($0 + 1). emir" } ?? unitType
        tappedUnitLabel.position = CGPoint(x: node.position.x, y: node.position.y + UnitArt.canvasPoints / 2)
        tappedUnitLabel.isHidden = false
    }
}
