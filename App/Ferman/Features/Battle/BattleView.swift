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
    /// The stamped stack's natural height, so it can be scaled down to fit when several unit types'
    /// programs are stamped at once.
    @State private var orderStackHeight: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    var onShowResult: (BattleResult) -> Void = { _ in }

    init(config: BattleConfig, orders: [OrderStack.Item], onShowResult: @escaping (BattleResult) -> Void = { _ in }) {
        _model = State(initialValue: BattleModel(config: config, orders: orders, audio: AudioService.shared))
        self.onShowResult = onShowResult
    }

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            // Top bar, table, strip stacked rather than overlaid (D26): the upright table gets
            // exactly the height between them, and nothing covers the player's own deployment zone
            // at the bottom. The chrome keeps its space through the intro so the table doesn't
            // resize the moment the battle starts.
            VStack(spacing: 0) {
                BattleTopBar(
                    elapsedSeconds: elapsedSeconds,
                    isPlaying: model.clock?.isPlaying ?? false,
                    speed: speedBinding,
                    onBack: { dismiss() },
                    onTogglePlayPause: { model.clock?.togglePlayPause() },
                    onRestart: { model.restart() },
                    onShowResult: { showResult(delayed: false) }
                )
                .opacity(isShowingBattle ? 1 : 0)
                .allowsHitTesting(isShowingBattle)
                .accessibilityHidden(!isShowingBattle)

                sandTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BattleTriggerStrip(rows: model.triggerRows, reservedRowCount: model.reservedTriggerRowCount)
                    .opacity(isShowingBattle ? 1 : 0)
                    .accessibilityHidden(!isShowingBattle)
            }

            if model.phase == .lampFlicker {
                Color.white.opacity(0.25).ignoresSafeArea()
            }

            choreographyOverlay
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.5), value: model.phase)
        // The system bar would sit over the sand table and offer a back button mid-intro; the HUD's
        // own back button takes its place once the battle is playing.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.start(reduceMotion: reduceMotion)
        }
        .onAppear {
            // Coming back from the debrief: the result may be shown again (after a restart, or via
            // the "Sonuç" button), and the trigger strip picks up where it stopped.
            hasShownResult = false
            model.resume()
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

    /// Past the intro — the battle is on screen, running or not.
    private var isShowingBattle: Bool {
        model.phase == .playing
    }

    @ViewBuilder
    private var sandTable: some View {
        if let clock = model.clock, let timeline = model.timeline {
            BattleSceneView(config: model.config, timeline: timeline, clock: clock, onUnitTapped: model.selectUnit)
                .scaleEffect(sceneScale)
                .brightness(sceneBrightness)
        } else {
            Color.clear
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

    /// Every program is laid out from the start (unstamped cards invisible), so cards land in place
    /// instead of pushing the stack around, and the whole stack is scaled down if it's taller than
    /// the screen.
    private func orderStackOverlay(stampedCount: Int) -> some View {
        GeometryReader { proxy in
            OrderStack(items: model.orders, revealedCount: stampedCount)
                .padding(FermanSpacing.lg)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { orderStackHeight = $0 }
                .scaleEffect(min(1, proxy.size.height / max(orderStackHeight, 1)))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: stampedCount)
    }
}
