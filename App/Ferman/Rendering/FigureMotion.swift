import CoreGraphics
import FermanCore
import FermanReplay

/// What to draw for one figure at one instant (D27). Computed, never accumulated: the same replay time
/// always gives the same pose, however the clock got there — seeking, 1×/2×/4× and the offline clip
/// (D15) draw identical frames.
nonisolated struct FigurePose: Equatable, Sendable {
    struct Seal: Equatable, Sendable {
        /// 0-based, as `ruleActivated` reports it; the seal prints `ruleIndex + 1`.
        let ruleIndex: Int
        /// 0 → 1 over the seal's life.
        let progress: CGFloat
    }

    /// Where the figure stands on the table, in scene points — lunges and knockback included.
    var position: CGPoint
    /// Where its contact shadow falls, relative to `position`: away from the lamp (ART-DIRECTION §3).
    var shadowOffset: CGVector
    /// `zRotation` for art that faces up (+Y).
    var rotation: CGFloat
    /// 0…1: how far off the table the hand has lifted the miniature mid-step.
    var lift: CGFloat
    /// Extra rotation while rocking on a step or tipping over.
    var tilt: CGFloat
    /// Lengthwise stretch — a charging horse (1 = none).
    var stretch: CGFloat
    /// Lengthwise squash while tipping over — seen from above, a falling figure foreshortens (1 = none).
    var squash: CGFloat
    /// Momentary scale when an order fires (1 = none).
    var pulse: CGFloat
    var pose: UnitPose
    /// 0…1 toward paper, when struck. Never spark cyan (brief §3.2).
    var flash: CGFloat
    /// 0…1 toward the sand, while routing.
    var dim: CGFloat
    var isFallen: Bool
    /// 0…1 progress of the rule spark; player figures only, `nil` when none is showing.
    var spark: CGFloat?
    var seal: Seal?
}

/// An arrow in flight at one instant.
nonisolated struct ArrowPose: Equatable, Sendable {
    var position: CGPoint
    /// Where its shadow falls on the table (the arc lifts the arrow off it).
    var groundPosition: CGPoint
    var rotation: CGFloat
    /// 0…1 of the arrow's arc height.
    var height: CGFloat
}

/// Timings and sizes of the hand-moved miniature (ART-DIRECTION §4), in seconds and scene points.
nonisolated enum MotionStyle {
    static let lungeOut = 0.08
    static let lungeBack = 0.15
    static let lungeDistance: CGFloat = 3.5
    static let recoilDistance: CGFloat = 1.5
    static let flashDuration = 0.07
    static let flashStrength: CGFloat = 0.7
    static let knockbackDuration = 0.15
    static let knockbackDistance: CGFloat = 1.5
    static let tipDuration = 0.12
    static let sparkDuration = 0.35
    static let sealDuration = 0.7
    static let pulseDuration = 0.12
    static let pulseScale: CGFloat = 0.06
    static let footStepCells = 0.35
    static let mountedStepCells = 0.6
    static let rockAngle: CGFloat = 4 * .pi / 180
    static let routDim: CGFloat = 0.35
    static let tremble: CGFloat = 0.8
    static let facingLookAhead = 0.25
    static let faceTargetBefore = 0.2
    static let faceTargetAfter = 0.4
    static let chargeStretch: CGFloat = 1.08
    /// A unit type reaching this far fights with arrows rather than a blade.
    static let rangedThresholdMilliCells = 2_000
}

/// Every figure's motion over a whole battle, precomputed once per replay (D27).
nonisolated struct FigureMotion: Sendable {
    let figures: [UnitID: Figure]
    let unitIDs: [UnitID]
    private let arrows: [Arrow]
    private let maxArrowFlight: Double
    private let ticksPerSecond: Double

    init(result: BattleResult, config: BattleConfig, projection: BoardProjection) {
        let tracks = UnitTracks(result: result)
        let ticksPerSecond = Double(BattleConfig.ticksPerSecond)
        self.ticksPerSecond = ticksPerSecond
        let catalog = Dictionary(uniqueKeysWithValues: config.unitCatalog.map { ($0.id, $0) })
        let sampleInterval = Double(config.tuning.moveSampleIntervalTicks)
        let abilityTicks = Double(config.tuning.abilityDurationTicks)

        var figures: [UnitID: Figure] = [:]
        for track in tracks.tracks {
            let type = catalog[track.unitType]
            figures[track.unit] = Figure(
                track: track, projection: projection, sampleIntervalTicks: sampleInterval,
                abilityDurationTicks: abilityTicks,
                isMounted: type?.ability == .charge,
                isRanged: (type?.rangeMilliCells ?? 0) >= MotionStyle.rangedThresholdMilliCells)
        }
        self.figures = figures
        self.unitIDs = tracks.tracks.map(\.unit)

        var arrows: [Arrow] = []
        for track in tracks.tracks {
            guard let archer = figures[track.unit], archer.isRanged else { continue }
            for strike in track.strikesMade {
                guard let target = figures[strike.other] else { continue }
                let landTick = Double(strike.tick)
                let from = archer.groundPoint(atTick: landTick)
                let to = target.groundPoint(atTick: landTick)
                let cells = hypot(to.x - from.x, to.y - from.y) / projection.pointsPerCell
                let flightSeconds = min(0.45, max(0.2, Double(cells) * 0.05))
                arrows.append(
                    Arrow(
                        launchTick: landTick - flightSeconds * ticksPerSecond, landTick: landTick, from: from, to: to,
                        arcHeight: 6 + cells * 1.2))
            }
        }
        self.arrows = arrows.sorted { $0.launchTick < $1.launchTick }
        self.maxArrowFlight = 0.45 * ticksPerSecond
    }

    /// `tick` is fractional replay time in ticks (`ReplayClock.fractionalTick`).
    func pose(of unit: UnitID, atTick tick: Double, reduceMotion: Bool) -> FigurePose? {
        guard let figure = figures[unit] else { return nil }
        return figure.pose(atTick: tick, ticksPerSecond: ticksPerSecond, figures: figures, reduceMotion: reduceMotion)
    }

    /// Arrows in the air at `tick`: each leaves its archer one flight early and lands on the attack tick,
    /// so the hit and the arrow's arrival are the same frame (the simulation applies ranged damage at once).
    func arrows(atTick tick: Double) -> [ArrowPose] {
        var low = 0
        var high = arrows.count
        while low < high {
            let middle = (low + high) / 2
            if arrows[middle].launchTick < tick - maxArrowFlight { low = middle + 1 } else { high = middle }
        }
        var result: [ArrowPose] = []
        var index = low
        while index < arrows.count, arrows[index].launchTick <= tick {
            if let pose = arrows[index].pose(atTick: tick) { result.append(pose) }
            index += 1
        }
        return result
    }

    // MARK: - Arrow

    private struct Arrow: Sendable {
        let launchTick: Double
        let landTick: Double
        let from: CGPoint
        let to: CGPoint
        let arcHeight: CGFloat

        func pose(atTick tick: Double) -> ArrowPose? {
            guard tick >= launchTick, tick <= landTick, landTick > launchTick else { return nil }
            let progress = CGFloat((tick - launchTick) / (landTick - launchTick))
            let ground = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
            let height = sin(.pi * progress)
            // Top-down, "up off the table" reads as toward the lamp: the arrow drifts up-screen from its
            // shadow as it climbs, and its direction tilts with the arc.
            let lifted = CGPoint(x: ground.x, y: ground.y + height * arcHeight)
            let slope = cos(.pi * progress) * arcHeight * .pi
            let direction = CGVector(dx: to.x - from.x, dy: to.y - from.y + slope)
            return ArrowPose(
                position: lifted, groundPosition: ground,
                rotation: atan2(direction.dy, direction.dx) - .pi / 2, height: height)
        }
    }

    // MARK: - Figure

    struct Figure: Sendable {
        let track: UnitTrack
        let isMounted: Bool
        let isRanged: Bool
        private let sampleTicks: [Double]
        private let samplePoints: [CGPoint]
        /// Cells travelled by each sample — drives the stepping rhythm.
        private let sampleDistance: [Double]
        /// Heading (radians, scene space) of the last real move at or before each sample.
        private let sampleHeading: [CGFloat]
        private let sampleIntervalTicks: Double
        private let abilityDurationTicks: Double
        private let restingHeading: CGFloat
        private let cellPoints: CGFloat
        private let projection: BoardProjection

        init(
            track: UnitTrack, projection: BoardProjection, sampleIntervalTicks: Double, abilityDurationTicks: Double,
            isMounted: Bool, isRanged: Bool
        ) {
            self.track = track
            self.isMounted = isMounted
            self.isRanged = isRanged
            self.sampleIntervalTicks = sampleIntervalTicks
            self.abilityDurationTicks = abilityDurationTicks
            self.cellPoints = projection.pointsPerCell
            self.projection = projection
            // Upright board (D26): the player's army faces up the table, the enemy's down it.
            self.restingHeading = track.team == .player ? .pi / 2 : -.pi / 2
            sampleTicks = track.path.map { Double($0.tick) }
            samplePoints = track.path.map { projection.scenePoint($0.position) }

            var distance: [Double] = []
            var heading: [CGFloat] = []
            var travelled = 0.0
            var lastHeading = restingHeading
            for (index, point) in samplePoints.enumerated() {
                if index > 0 {
                    let previous = samplePoints[index - 1]
                    let step = hypot(point.x - previous.x, point.y - previous.y)
                    travelled += Double(step / projection.pointsPerCell)
                    if step > 0.01 { lastHeading = atan2(point.y - previous.y, point.x - previous.x) }
                }
                distance.append(travelled)
                heading.append(lastHeading)
            }
            sampleDistance = distance
            sampleHeading = heading
        }

        /// Where the figure's base stands at `tick`, before any flourish. A move sample only lands where the
        /// unit already was one sample interval earlier; the step between them is spread over that interval
        /// instead of all happening on the sampled tick.
        func groundPoint(atTick tick: Double) -> CGPoint {
            let clamped = track.deathTick.map { min(tick, Double($0)) } ?? tick
            let index = lastSample(atOrBefore: clamped)
            guard index + 1 < samplePoints.count else { return samplePoints[index] }
            let segmentEnd = sampleTicks[index + 1]
            let segmentStart = max(sampleTicks[index], segmentEnd - sampleIntervalTicks)
            guard clamped > segmentStart else { return samplePoints[index] }
            let fraction = CGFloat((clamped - segmentStart) / (segmentEnd - segmentStart))
            return samplePoints[index].interpolated(to: samplePoints[index + 1], fraction: fraction)
        }

        func pose(
            atTick tick: Double, ticksPerSecond: Double, figures: [UnitID: Figure], reduceMotion: Bool
        ) -> FigurePose {
            let seconds = { (ticks: Double) in ticks / ticksPerSecond }
            let wholeTick = Int32(tick.rounded(.down))
            var position = groundPoint(atTick: tick)
            var rotation = headingRotation(atTick: tick + MotionStyle.facingLookAhead * ticksPerSecond)
            var pose = UnitPose.base
            var lift: CGFloat = 0
            var tilt: CGFloat = 0
            var stretch: CGFloat = 1
            var squash: CGFloat = 1
            var pulse: CGFloat = 1
            var flash: CGFloat = 0
            var dim: CGFloat = 0

            // Stepping: the hand lifts and sets the miniature down once per stride.
            if let travel = travelled(atTick: tick), travel.moving, !reduceMotion {
                let stride = isMounted ? MotionStyle.mountedStepCells : MotionStyle.footStepCells
                let phase = travel.distance / stride
                lift = CGFloat(abs(sin(.pi * phase)))
                let side: CGFloat = Int(phase.rounded(.down)).isMultiple(of: 2) ? 1 : -1
                tilt = side * lift * MotionStyle.rockAngle
            }

            // Facing a foe while fighting it, and the lunge (or an archer's recoil) on each blow.
            let lookAhead = Int32((tick + MotionStyle.faceTargetBefore * ticksPerSecond).rounded(.down))
            if let strike = track.lastStrikeMade(atOrBefore: lookAhead),
                seconds(tick - Double(strike.tick)) < MotionStyle.faceTargetAfter,
                let target = figures[strike.other]
            {
                let targetPoint = target.groundPoint(atTick: tick)
                let direction = CGVector(dx: targetPoint.x - position.x, dy: targetPoint.y - position.y)
                if hypot(direction.dx, direction.dy) > 0.5 {
                    rotation = atan2(direction.dy, direction.dx) - .pi / 2
                }
                let since = seconds(tick - Double(strike.tick))
                if since >= 0, since < MotionStyle.lungeOut + MotionStyle.lungeBack {
                    pose = .strike
                    let amount = CGFloat(
                        since < MotionStyle.lungeOut
                            ? since / MotionStyle.lungeOut
                            : 1 - (since - MotionStyle.lungeOut) / MotionStyle.lungeBack)
                    let reach = isRanged ? -MotionStyle.recoilDistance : MotionStyle.lungeDistance
                    if !reduceMotion {
                        let length = max(hypot(direction.dx, direction.dy), 0.001)
                        position.x += direction.dx / length * reach * amount
                        position.y += direction.dy / length * reach * amount
                    }
                }
            }

            // Struck: a paper-coloured flash, knocked back from the blow.
            if let hit = track.lastStrikeTaken(atOrBefore: wholeTick) {
                let since = seconds(tick - Double(hit.tick))
                if since < MotionStyle.flashDuration {
                    flash = MotionStyle.flashStrength * CGFloat(1 - since / MotionStyle.flashDuration)
                }
                if since < MotionStyle.knockbackDuration, !reduceMotion, let attacker = figures[hit.other] {
                    let from = attacker.groundPoint(atTick: tick)
                    let away = CGVector(dx: position.x - from.x, dy: position.y - from.y)
                    let length = max(hypot(away.dx, away.dy), 0.001)
                    let amount = MotionStyle.knockbackDistance * CGFloat(1 - since / MotionStyle.knockbackDuration)
                    position.x += away.dx / length * amount
                    position.y += away.dy / length * amount
                }
            }

            // Holding an ability: spear or shield wall braced, a charging horse stretched out.
            if let start = track.lastAbilityStart(atOrBefore: wholeTick),
                tick - Double(start.tick) < abilityDurationTicks
            {
                switch start.ability {
                case .spearWall, .shieldWall: pose = .brace
                case .charge: stretch = MotionStyle.chargeStretch
                case .volley: break
                }
            }

            // Routing: dulled, trembling in place.
            if track.isMoraleBroken(at: wholeTick) {
                dim = MotionStyle.routDim
                if !reduceMotion {
                    position.x += Self.jitter(track.unit, wholeTick, salt: 1) * MotionStyle.tremble
                    position.y += Self.jitter(track.unit, wholeTick, salt: 2) * MotionStyle.tremble
                }
            }

            // The player's own logic at work: spark, a small pulse and the order's seal (brief §3.2).
            var spark: CGFloat?
            var seal: FigurePose.Seal?
            if track.team == .player, let activation = track.lastRuleActivation(atOrBefore: wholeTick) {
                let since = seconds(tick - Double(activation.tick))
                if since < MotionStyle.sparkDuration { spark = CGFloat(since / MotionStyle.sparkDuration) }
                if since < MotionStyle.sealDuration {
                    seal = FigurePose.Seal(
                        ruleIndex: activation.ruleIndex, progress: CGFloat(since / MotionStyle.sealDuration))
                }
                if since < MotionStyle.pulseDuration, !reduceMotion {
                    pulse = 1 + MotionStyle.pulseScale * CGFloat(1 - since / MotionStyle.pulseDuration)
                }
            }

            // Knocked over: tips for a moment, then lies where it fell for the rest of the battle.
            var isFallen = false
            if let death = track.deathTick, tick >= Double(death) {
                let since = seconds(tick - Double(death))
                rotation = headingRotation(atTick: Double(death))
                lift = 0
                stretch = 1
                pulse = 1
                dim = 0
                spark = nil
                seal = nil
                tilt = 0
                if since < MotionStyle.tipDuration, !reduceMotion {
                    squash = 1 - 0.45 * CGFloat(since / MotionStyle.tipDuration)
                    pose = .base
                } else {
                    pose = .fallen
                    isFallen = true
                }
            }

            return FigurePose(
                position: position, shadowOffset: projection.shadowOffset(atScenePoint: position), rotation: rotation, lift: lift, tilt: tilt, stretch: stretch, squash: squash,
                pulse: pulse,
                pose: pose, flash: flash, dim: dim, isFallen: isFallen, spark: spark, seal: seal)
        }

        /// Heading as a `zRotation` for up-facing art: the direction of the move under way at `tick`.
        private func headingRotation(atTick tick: Double) -> CGFloat {
            let clamped = track.deathTick.map { min(tick, Double($0)) } ?? tick
            let index = lastSample(atOrBefore: clamped)
            let heading: CGFloat
            if index + 1 < samplePoints.count, clamped > sampleTicks[index + 1] - sampleIntervalTicks {
                heading = sampleHeading[index + 1]
            } else {
                heading = sampleHeading[index]
            }
            return heading - .pi / 2
        }

        /// Cells travelled by `tick`, and whether the figure is mid-step.
        private func travelled(atTick tick: Double) -> (distance: Double, moving: Bool)? {
            if let death = track.deathTick, tick >= Double(death) { return nil }
            let index = lastSample(atOrBefore: tick)
            guard index + 1 < samplePoints.count else { return (sampleDistance[index], false) }
            let segmentEnd = sampleTicks[index + 1]
            let segmentStart = max(sampleTicks[index], segmentEnd - sampleIntervalTicks)
            guard tick > segmentStart, sampleDistance[index + 1] > sampleDistance[index] else {
                return (sampleDistance[index], false)
            }
            let fraction = (tick - segmentStart) / (segmentEnd - segmentStart)
            return (sampleDistance[index] + (sampleDistance[index + 1] - sampleDistance[index]) * fraction, true)
        }

        private func lastSample(atOrBefore tick: Double) -> Int {
            var low = 0
            var high = sampleTicks.count
            while low < high {
                let middle = (low + high) / 2
                if sampleTicks[middle] <= tick { low = middle + 1 } else { high = middle }
            }
            return max(0, low - 1)
        }

        /// A stable -1…1 wobble per unit and tick — "random" to the eye, identical on every replay.
        private static func jitter(_ unit: UnitID, _ tick: Int32, salt: UInt64) -> CGFloat {
            var value = UInt64(unit.rawValue) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(UInt32(bitPattern: tick)) &* 0xBF58_476D_1CE4_E5B9
                ^ salt &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            value &*= 0xD6E8_FEB8_6659_FD93
            value ^= value >> 32
            return CGFloat(value % 2001) / 1000 - 1
        }
    }
}
