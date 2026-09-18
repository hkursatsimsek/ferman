import FermanCore
import FermanReplay
import SwiftUI

/// Full-screen sand table, no player controls (design brief §4.5). Plays the "savaşı başlat"
/// choreography (§3.5) once, then shows the running battle. `BattleScene` (F1.4) draws frames; this
/// view only decides when it's visible and dims/scales it while the intro plays.
struct BattleView: View {
    @State private var model: BattleModel
    /// Guards `onShowResult` against firing twice — once from a manual "Sonuç" tap and again from
    /// the clock naturally finishing, or vice versa.
    @State private var hasShownResult = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onShowResult: (BattleResult) -> Void = { _ in }

    init(config: BattleConfig, orders: [OrderStack.Item], onShowResult: @escaping (BattleResult) -> Void = { _ in }) {
        _model = State(initialValue: BattleModel(config: config, orders: orders))
        self.onShowResult = onShowResult
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            if let clock = model.clock, let timeline = model.timeline {
                BattleSceneView(map: model.config.map, timeline: timeline, clock: clock, onUnitTapped: model.selectUnit)
                    .ignoresSafeArea()
                    .scaleEffect(sceneScale)
                    .brightness(sceneBrightness)
            }

            if model.phase == .lampFlicker {
                Color.white.opacity(0.25).ignoresSafeArea()
            }

            if model.phase == .playing {
                BattleHUD(
                    elapsedSeconds: elapsedSeconds,
                    isPlaying: model.clock?.isPlaying ?? false,
                    speed: speedBinding,
                    triggerRows: model.triggerRows,
                    onTogglePlayPause: { model.clock?.togglePlayPause() },
                    onRestart: { model.restart() },
                    onShowResult: { showResult(delayed: false) }
                )
            }

            choreographyOverlay
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.5), value: model.phase)
        .task {
            model.start(reduceMotion: reduceMotion)
        }
        .onDisappear {
            model.stop()
        }
        .onTapGesture {
            model.skip()
        }
        // The battle screen is watch-only (brief §4.5) — once the clock plays itself out there's
        // nothing left to do here, so it cuts to the debrief on its own rather than stranding the
        // player on a frozen sand table waiting for a manual "Sonuç" tap.
        .onChange(of: model.clock?.isPlaying) { _, isPlaying in
            guard model.phase == .playing, isPlaying == false, model.clock?.isFinished == true else { return }
            showResult(delayed: true)
        }
    }

    /// Guarded by `hasShownResult` so a manual "Sonuç" tap and the auto-finish transition can never
    /// both fire. `delayed` gives the player a beat to register the battle's last frame before the
    /// cut — a manual tap already IS that beat, so it navigates immediately.
    private func showResult(delayed: Bool) {
        guard !hasShownResult, let result = model.result else { return }
        hasShownResult = true
        guard delayed else {
            onShowResult(result)
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            onShowResult(result)
        }
    }

    private var elapsedSeconds: Int {
        Int((model.clock?.currentTick ?? 0) / Int32(BattleConfig.ticksPerSecond))
    }

    private var speedBinding: Binding<BattleSpeed> {
        Binding(get: { model.clock?.speed ?? .x1 }, set: { model.clock?.speed = $0 })
    }

    private var sceneScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch model.phase {
        case .stamping, .slidingAway: return 0.92
        default: return 1
        }
    }

    private var sceneBrightness: Double {
        guard !reduceMotion else { return 0 }
        switch model.phase {
        case .stamping, .slidingAway: return -0.25
        default: return 0
        }
    }

    @ViewBuilder
    private var choreographyOverlay: some View {
        switch model.phase {
        case .stamping(let stampedCount):
            orderStackOverlay(stampedCount: stampedCount)
        case .slidingAway:
            orderStackOverlay(stampedCount: model.orders.count)
                .offset(x: reduceMotion ? 0 : 420)
                .opacity(reduceMotion ? 0 : 1)
        default:
            EmptyView()
        }
    }

    private func orderStackOverlay(stampedCount: Int) -> some View {
        VStack {
            Spacer()
            OrderStack(items: Array(model.orders.prefix(stampedCount)))
                .padding(FermanSpacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: stampedCount)
    }
}
