import FermanCore
import FermanReplay
import SpriteKit
import SwiftUI

/// Hosts `BattleScene` in SwiftUI. `BattleView` (F1.5) composes this with the
/// top bar, trigger bars and speed control; this file only wires the scene up.
struct BattleSceneView: View {
    let map: BattleMap
    let timeline: ReplayTimeline
    let clock: ReplayClock
    var onUnitTapped: ((UnitID) -> Void)?

    @State private var scene: BattleScene

    init(map: BattleMap, timeline: ReplayTimeline, clock: ReplayClock, onUnitTapped: ((UnitID) -> Void)? = nil) {
        self.map = map
        self.timeline = timeline
        self.clock = clock
        self.onUnitTapped = onUnitTapped
        _scene = State(initialValue: BattleScene(map: map, timeline: timeline, clock: clock))
    }

    var body: some View {
        // Locks the view's own aspect ratio to the map's before SpriteKit ever scales anything, so
        // the letterboxed sand table lands centered (SwiftUI centers a smaller child in its parent
        // by default) instead of pinned to whichever corner `SKScene.anchorPoint` happens to place
        // the scene's origin at.
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .onAppear { scene.onUnitTapped = onUnitTapped }
            .aspectRatio(CGFloat(map.width) / CGFloat(map.height), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
