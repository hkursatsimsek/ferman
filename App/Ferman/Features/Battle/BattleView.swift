import FermanCore
import FermanReplay
import SwiftUI

/// Full-screen sand table, no player controls (design brief §4.5). Plays the "savaşı başlat"
/// choreography (§3.5) once, then shows the running battle. `BattleScene` (F1.4) draws frames; this
/// view only decides when it's visible and dims/scales it while the intro plays.
struct BattleView: View {
    @State private var model: BattleModel
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
                    onShowResult: { if let result = model.result { onShowResult(result) } }
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
