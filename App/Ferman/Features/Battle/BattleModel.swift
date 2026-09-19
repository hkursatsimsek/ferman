import FermanCore
import FermanReplay
import Observation

/// Drives one battle screen: the "savaşı başlat" choreography (design brief §3.5), then playback.
///
/// Sim-then-render (CLAUDE.md rule 4): the whole battle is simulated once, up front, off the main
/// actor. Everything after that — restart, seek, speed — only moves a clock over an already-known
/// result; none of it re-simulates.
@Observable
@MainActor
final class BattleModel {
    /// One step of the one-time intro sequence (brief §3.5). `.playing` covers the entire watched
    /// battle afterwards, whether paused, running or finished.
    enum Phase: Equatable {
        case stamping(stampedCount: Int)
        case slidingAway
        case cameraDescending
        case lampFlicker
        case playing
    }

    /// A trigger strip row (brief §4.5) — which order, how often it has fired, and whether it just did.
    struct TriggerRow: Identifiable, Equatable {
        let id: Int
        let priority: Int
        let fraction: Double
        let count: Int
        let isSpark: Bool
        /// The order's words (`OrderPhraseFormatter`), empty when none were handed in.
        var condition: String = ""
        var action: String = ""
        var isDefault: Bool = false
    }

    static let stampInterval: Duration = .milliseconds(60)
    static let slideAwayDuration: Duration = .milliseconds(300)
    static let cameraDescendDuration: Duration = .milliseconds(500)
    static let lampFlickerDuration: Duration = .milliseconds(150)
    /// A tap speeds the choreography up rather than cutting it (brief §3.5 — "dokununca hızlanır").
    static let skippingStepDuration: Duration = .milliseconds(16)
    /// The trigger strip samples `ReplayTimeline.fireCounts(upTo:)` at 10 Hz, not every SpriteKit
    /// frame, so SwiftUI isn't invalidated 60 times a second for numbers that only need to look live
    /// (ARCHITECTURE §8).
    static let sampleInterval: Duration = .milliseconds(100)
    /// How long a trigger bar glows after its order fires, matched to `BattleScene`'s spark particle
    /// lifetime so the sand table and the strip flash in step.
    static let sparkGlowTicks: Int32 = 10
    /// Replay time past the battle's last tick, so the final blows land visibly: the battle ends the tick
    /// its last unit dies, and without this the last figure to fall would freeze mid-tip (D27).
    nonisolated static let settleTicks: Int32 = 15

    let config: BattleConfig
    /// What to stamp into view before the battle starts. Already-formatted text: this model
    /// sequences an animation, it doesn't know `Condition`/`Action` (that's `OrderPhraseFormatter`,
    /// F1.7's job).
    let orders: [OrderStack.Item]
    /// Each of the player's programs as formatted cards, by unit type — the trigger strip's and the
    /// tapped unit's words. Formatted by the caller for the same reason as `orders`.
    let phrases: [UnitTypeID: [OrderStack.Item]]

    private(set) var phase: Phase
    private(set) var clock: ReplayClock?
    private(set) var timeline: ReplayTimeline?
    private(set) var result: BattleResult?
    private(set) var triggerRows: [TriggerRow] = []
    private(set) var selectedUnitType: UnitTypeID?

    /// Rows the trigger strip reserves: the longest of the player's programs, default order included.
    var reservedTriggerRowCount: Int {
        config.player.programs.map(\.rules.count).max() ?? 0
    }

    private let runner: BattleRunner
    private let audio: any AudioPlaying
    private var isSkipping = false
    private var runTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?

    init(
        config: BattleConfig, orders: [OrderStack.Item], phrases: [UnitTypeID: [OrderStack.Item]] = [:],
        runner: BattleRunner = BattleRunner(), audio: any AudioPlaying = SilentAudioPlaying()
    ) {
        self.config = config
        self.orders = orders
        self.phrases = phrases
        self.runner = runner
        self.audio = audio
        self.phase = orders.isEmpty ? .slidingAway : .stamping(stampedCount: 0)
        self.selectedUnitType = config.player.programs.first?.unitType
    }

    /// Starts the intro sequence (or, under Reduce Motion, cuts straight to playing) and the battle
    /// behind it. Call once, from the view's `.task`.
    func start(reduceMotion: Bool) {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            if reduceMotion {
                await self.runInstant()
            } else {
                await self.runChoreography()
            }
        }
    }

    /// Speeds up whatever is left of the intro sequence (brief §3.5); a no-op once playing.
    func skip() {
        isSkipping = true
    }

    /// Seeks back to tick 0. The battle already ran — this never re-simulates (< 100 ms).
    func restart() {
        clock?.restart()
        startSampling()
    }

    func stop() {
        runTask?.cancel()
        samplingTask?.cancel()
    }

    /// Picks the trigger strip back up after `stop()` — e.g. returning here from the debrief, where
    /// the finished battle can still be restarted. A no-op before the intro has finished.
    func resume() {
        guard phase == .playing else { return }
        startSampling()
    }

    /// How far before a reviewed moment the replay starts, so the player sees it build up.
    static let reviewLeadInTicks: Int32 = 60

    /// Replays from a little before `tick` at normal speed — the debrief's "O anı izle".
    func review(from tick: Int32) {
        guard let clock else { return }
        clock.seek(to: max(0, tick - Self.reviewLeadInTicks))
        clock.speed = .x1
        clock.isPlaying = true
        startSampling()
    }

    /// The unit types with a program of their own — the trigger strip's tabs.
    var playerUnitTypes: [UnitTypeID] {
        config.player.programs.map(\.unitType)
    }

    /// Switches the trigger strip to the tapped unit's program, if it's one of the player's own.
    func selectUnit(_ unitID: UnitID) {
        guard let timeline, let clock else { return }
        let frame = timeline.frame(at: clock.currentTick)
        guard frame.teams[unitID] == .player, let unitType = frame.unitTypes[unitID] else { return }
        selectUnitType(unitType)
    }

    func selectUnitType(_ unitType: UnitTypeID) {
        guard config.player.program(for: unitType) != nil else { return }
        selectedUnitType = unitType
        refreshTriggerRows()
    }

    /// The order a player unit is following right now — what the tapped unit's bubble says (brief §4.5,
    /// "şu an uyguluyor"). `nil` for the enemy's units, the dead, and before any order has fired.
    func currentOrder(of unitID: UnitID) -> OrderStack.Item? {
        guard let timeline, let clock else { return nil }
        let frame = timeline.frame(at: clock.currentTick)
        guard frame.teams[unitID] == .player, frame.livingUnits.contains(unitID),
            let unitType = frame.unitTypes[unitID], let ruleIndex = frame.activeRuleIndex[unitID],
            let items = phrases[unitType], ruleIndex < items.count
        else { return nil }
        return items[ruleIndex]
    }

    // MARK: - Choreography

    private func runChoreography() async {
        // The battle is simulated while the orders are stamped, and installed the moment it's ready, so
        // the (still distant, dimmed) sand table is already there under the stamps and the camera's
        // descent onto it is something the player actually sees (brief §3.5).
        let simulation = Task { [runner, config] in await runner.run(config) }
        let installation = Task { [weak self] in
            let result = await simulation.value
            self?.installResult(result)
        }

        for index in orders.indices {
            phase = .stamping(stampedCount: index + 1)
            audio.play(.stamp)
            await sleepStep(Self.stampInterval)
        }
        phase = .slidingAway
        await sleepStep(Self.slideAwayDuration)

        await installation.value
        phase = .cameraDescending
        await sleepStep(Self.cameraDescendDuration)

        phase = .lampFlicker
        await sleepStep(Self.lampFlickerDuration)

        beginPlaying()
    }

    private func runInstant() async {
        installResult(await runner.run(config))
        beginPlaying()
    }

    private func beginPlaying() {
        phase = .playing
        clock?.isPlaying = true
        startSampling()
    }

    private func installResult(_ result: BattleResult) {
        self.result = result
        let timeline = ReplayTimeline(result: result)
        self.timeline = timeline
        let clock = ReplayClock(tickCount: Int32(result.tickCount) + Self.settleTicks)
        clock.isPlaying = false
        clock.speed = GameSettings.defaultSpeed
        self.clock = clock
    }

    private func sleepStep(_ duration: Duration) async {
        try? await Task.sleep(for: isSkipping ? Self.skippingStepDuration : duration)
    }

    // MARK: - Trigger strip

    /// Refreshes once synchronously before spawning the recurring sampler: `phase` flips to
    /// `.playing` the moment this is called (from `beginPlaying()`), so without an immediate,
    /// non-async refresh here `triggerRows` would stay empty until the new `Task` first gets
    /// scheduled — a race a caller watching `phase` has no way to wait out.
    private func startSampling() {
        samplingTask?.cancel()
        refreshTriggerRows()
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let clock = self.clock, !clock.isFinished else { break }
                try? await Task.sleep(for: Self.sampleInterval)
                self.refreshTriggerRows()
            }
        }
    }

    private func refreshTriggerRows() {
        guard let timeline, let clock, let unitType = selectedUnitType,
            let program = config.player.program(for: unitType)
        else {
            triggerRows = []
            return
        }

        let tick = clock.currentTick
        let counts = Self.counts(in: timeline.fireCounts(upTo: tick), team: .player, unitType: unitType)
        let priorCounts = Self.counts(
            in: timeline.fireCounts(upTo: max(0, tick - Self.sparkGlowTicks)), team: .player, unitType: unitType)
        let total = max(1, counts.reduce(0, +))

        let words = phrases[unitType] ?? []
        triggerRows = program.rules.indices.map { index in
            let count = index < counts.count ? counts[index] : 0
            let priorCount = index < priorCounts.count ? priorCounts[index] : 0
            return TriggerRow(
                id: index,
                priority: index + 1,
                fraction: Double(count) / Double(total),
                count: count,
                isSpark: count > priorCount,
                condition: index < words.count ? words[index].condition : "",
                action: index < words.count ? words[index].action : "",
                isDefault: index == program.rules.count - 1
            )
        }
    }

    private static func counts(in entries: [RuleFireCounts], team: Team, unitType: UnitTypeID) -> [Int] {
        entries.first { $0.team == team && $0.unitType == unitType }?.counts ?? []
    }
}
