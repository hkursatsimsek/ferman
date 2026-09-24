import FermanCore
import FermanReplay
import SwiftUI
import TipKit

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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dismiss) private var dismiss
    /// Optional: a direct launch or preview may have no router; the debrief's replay request comes
    /// through it when there is one.
    @Environment(AppRouter.self) private var router: AppRouter?
    var onShowResult: (BattleResult) -> Void = { _ in }
    /// The campaign front this battle is on, for its pencil note (G13); `nil` off the campaign.
    let tutorialFront: Int?

    init(
        config: BattleConfig, orders: [OrderStack.Item], phrases: [UnitTypeID: [OrderStack.Item]] = [:],
        tutorialFront: Int? = nil, onShowResult: @escaping (BattleResult) -> Void = { _ in }
    ) {
        self.tutorialFront = tutorialFront
        _model = State(
            initialValue: BattleModel(config: config, orders: orders, phrases: phrases, audio: AudioService.shared))
        self.onShowResult = onShowResult
    }

    /// How long the result slip lies on the table before the debrief takes over — long enough to read.
    private static let resultSlipDwell: Duration = .milliseconds(1_600)

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
                    // Laid on the near edge of the table, over the player's own zone, not between the
                    // table and the strip — so neither moves when the note is closed.
                    .overlay(alignment: .bottom) {
                        if tutorialFront == 3, isShowingBattle {
                            TipView(PenNote())
                                .tipViewStyle(PencilNoteStyle())
                                .padding(FermanSpacing.md)
                        }
                    }

                BattleTriggerStrip(
                    rows: model.triggerRows, reservedRowCount: model.reservedTriggerRowCount,
                    unitTypes: model.playerUnitTypes, selectedUnitType: model.selectedUnitType,
                    onSelectUnitType: { model.selectUnitType($0) }
                )
                .opacity(isShowingBattle ? 1 : 0)
                    .accessibilityHidden(!isShowingBattle)
            }

            choreographyOverlay

            if isShowingBattle, model.clock?.isFinished == true, let result = model.result {
                BattleResultSlip(title: DebriefInsightFormatter.title(for: result.outcome))
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 1.18).combined(with: .opacity), removal: .opacity))
                    .onTapGesture { showResult(delayed: false) }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.5), value: model.phase)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.35), value: model.clock?.isFinished)
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
            if let tick = router?.replayRequest {
                router?.replayRequest = nil
                model.review(from: tick)
            } else {
                model.resume()
            }
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
            model.resultSlipLanded()
            showResult(delayed: true)
        }
        // In battle only the player's own orders and the result reach the hand (ART-DIRECTION §7).
        .sensoryFeedback(SoundEffect.order.feel?.feedback ?? .selection, trigger: model.orderFeedbackPulse)
        .onChange(of: model.evaluation != nil) { _, evaluating in
            if evaluating { PenNote().invalidate(reason: .actionPerformed) }
        }
        .sensoryFeedback(SoundEffect.slip.feel?.feedback ?? .selection, trigger: model.clock?.isFinished) { _, finished in
            finished == true
        }
    }

    /// Past the intro — the battle is on screen, running or not.
    private var isShowingBattle: Bool {
        model.phase == .playing
    }

    @ViewBuilder
    private var sandTable: some View {
        if let clock = model.clock, let timeline = model.timeline {
            BattleSceneView(
                config: model.config, timeline: timeline, clock: clock, onUnitTapped: model.selectUnit,
                currentOrder: { model.currentOrder(of: $0) }, audio: model.audio,
                onPlayerOrder: { model.noteOrderCue() })
                // SpriteKit carries no accessibility of its own (G15) — this stands in for the whole
                // table rather than leaving VoiceOver with nothing on it: one figure per living unit,
                // each where it stands, each a VoiceOver element of its own (rather than one opaque
                // summary string) so a touch-select target exists per figure, player and enemy alike.
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "Kum masası"))
                .accessibilityChildren {
                    UnitAccessibilityLayer(
                        units: model.unitDescriptions, board: BoardProjection.table(for: model.config.map).boardSize,
                        onActivate: { model.selectUnit($0) })
                }
                .accessibilityHidden(!isShowingBattle)
                .onChange(of: voiceOverEnabled, initial: true) { _, enabled in
                    model.describesUnits = enabled
                }
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
            try? await Task.sleep(for: Self.resultSlipDwell)
            // A restart during the dwell means the player chose to keep watching.
            guard model.clock?.isFinished == true else {
                hasShownResult = false
                return
            }
            onShowResult(result)
        }
    }

    private var elapsedSeconds: Int {
        Int((model.clock?.currentTick ?? 0) / Int32(BattleConfig.ticksPerSecond))
    }

    private var speedBinding: Binding<BattleSpeed> {
        Binding(get: { model.clock?.speed ?? .x1 }, set: { model.clock?.speed = $0 })
    }

    /// Brief §3.5, "kamera kum masasına iner": under the stamped orders the table sits far and dim; it
    /// comes up to full size as the camera descends, then the lamp dips once before the battle starts.
    private var sceneScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch model.phase {
        case .stamping, .slidingAway: return 0.84
        default: return 1
        }
    }

    private var sceneBrightness: Double {
        guard !reduceMotion else { return 0 }
        switch model.phase {
        case .stamping, .slidingAway: return -0.3
        case .lampFlicker: return -0.14
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
            OrderStack(items: model.orders, revealedCount: stampedCount, sealsRevealed: true)
                .padding(FermanSpacing.lg)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { orderStackHeight = $0 }
                .scaleEffect(min(1, proxy.size.height / max(orderStackHeight, 1)))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sensoryFeedback(SoundEffect.stamp.feel?.feedback ?? .selection, trigger: stampedCount)
    }
}

/// The outcome laid on the table as a paper slip when the battle ends (brief §4.5): the calm officer's
/// one line (brief §7), the same words the debrief opens with. Tap to go straight to the debrief.
private struct BattleResultSlip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(FermanFont.screenTitle())
            .tracking(FermanFont.Tracking.screenTitle)
            .foregroundStyle(Color.paperInk)
            .padding(.horizontal, FermanSpacing.xl)
            .padding(.vertical, FermanSpacing.lg)
            .background(Color.paper, in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
            .rotationEffect(.degrees(-1.5))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
            .accessibilityAddTraits(.isButton)
    }
}

/// The figures on the table as VoiceOver elements, each where its figure stands (G15). Laid out over
/// the scene's frame, which fits the board inside it — so the board's scale and letterbox are found
/// the same way `.aspectRatio(.fit)` found them.
private struct UnitAccessibilityLayer: View {
    let units: [BattleModel.UnitDescription]
    let board: CGSize
    let onActivate: (UnitID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / max(board.width, 1), proxy.size.height / max(board.height, 1))
            let origin = CGPoint(
                x: (proxy.size.width - board.width * scale) / 2, y: (proxy.size.height - board.height * scale) / 2)
            ForEach(units) { unit in
                Color.clear
                    .frame(width: 44, height: 44)
                    .position(x: origin.x + unit.position.x * scale, y: origin.y + unit.position.y * scale)
                    .accessibilityElement()
                    .accessibilityLabel(unit.label)
                    .accessibilityValue(unit.value)
                    .accessibilityAddTraits(unit.isPlayer ? .isButton : [])
                    .accessibilityAction { onActivate(unit.id) }
            }
        }
    }
}
