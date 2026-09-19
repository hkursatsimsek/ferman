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
    var onUnitTapped: ((UnitID) -> Void)?

    @State private var scene: BattleScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        config: BattleConfig, timeline: ReplayTimeline, clock: ReplayClock, onUnitTapped: ((UnitID) -> Void)? = nil
    ) {
        self.config = config
        self.timeline = timeline
        self.clock = clock
        self.onUnitTapped = onUnitTapped
        _scene = State(initialValue: BattleScene(config: config, timeline: timeline, clock: clock))
    }

    var body: some View {
        // Locks the view's own aspect ratio to the (upright, D26) board's before SpriteKit ever
        // scales anything, so the sand table lands centered (SwiftUI centers a smaller child in its
        // parent by default) instead of pinned to whichever corner `SKScene.anchorPoint` happens to
        // place the scene's origin at.
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .onAppear {
                scene.onUnitTapped = onUnitTapped
                scene.reduceMotion = reduceMotion
            }
            .onChange(of: reduceMotion) { _, newValue in scene.reduceMotion = newValue }
            .aspectRatio(BoardProjection.table(for: config.map).aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
