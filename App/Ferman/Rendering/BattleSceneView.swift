import FermanCore
import FermanReplay
import SpriteKit
import SwiftUI

/// Hosts `BattleScene` in SwiftUI. `BattleView` (F1.5) composes this with the
/// top bar, trigger bars and speed control; this file only wires the scene up.
struct BattleSceneView: View {
    let config: BattleConfig
    let timeline: ReplayTimeline
    let clock: ReplayClock
    var onUnitTapped: ((UnitID?) -> Void)?
    var currentOrder: ((UnitID) -> OrderStack.Item?)?
    /// `nil` (the default) keeps the table silent — only the battle screen itself is heard.
    var audio: (any AudioPlaying)?
    var onPlayerOrder: (() -> Void)?

    @State private var scene: BattleScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        config: BattleConfig, timeline: ReplayTimeline, clock: ReplayClock, onUnitTapped: ((UnitID?) -> Void)? = nil,
        currentOrder: ((UnitID) -> OrderStack.Item?)? = nil, audio: (any AudioPlaying)? = nil,
        onPlayerOrder: (() -> Void)? = nil
    ) {
        self.config = config
        self.timeline = timeline
        self.clock = clock
        self.onUnitTapped = onUnitTapped
        self.currentOrder = currentOrder
        self.audio = audio
        self.onPlayerOrder = onPlayerOrder
        _scene = State(initialValue: BattleScene(config: config, timeline: timeline, clock: clock))
    }

    /// `-showsDrawCount YES`: SpriteKit's draw-call and node counters over the table — how G5's "the
    /// whole army in a few draw calls" is checked on a device or simulator.
    private static let debugOptions: SpriteView.DebugOptions =
        UserDefaults.standard.bool(forKey: "showsDrawCount") ? [.showsDrawCount, .showsNodeCount, .showsFPS] : []

    var body: some View {
        // Locks the view's own aspect ratio to the (upright, D26) board's before SpriteKit ever
        // scales anything, so the sand table lands centered (SwiftUI centers a smaller child in its
        // parent by default) instead of pinned to whichever corner `SKScene.anchorPoint` happens to
        // place the scene's origin at.
        SpriteView(scene: scene, options: [.ignoresSiblingOrder], debugOptions: Self.debugOptions)
            .onAppear {
                scene.onUnitTapped = onUnitTapped
                scene.currentOrder = currentOrder
                scene.audio = audio
                scene.onPlayerOrder = onPlayerOrder
                scene.reduceMotion = reduceMotion
            }
            .onChange(of: reduceMotion) { _, newValue in scene.reduceMotion = newValue }
            .aspectRatio(BoardProjection.table(for: config.map).aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
