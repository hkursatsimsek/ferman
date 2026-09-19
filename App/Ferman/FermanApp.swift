//
//  FermanApp.swift
//  Ferman
//
//  Created by Hamza Kürşat Şimşek on 15.09.2026.
//

import SwiftUI

@main
struct FermanApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TutorialNotes.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.audio, AudioService.shared)
        }
        // The war room's ambience runs while the game is in front, under every screen (ART-DIRECTION §7).
        .onChange(of: scenePhase, initial: true) { _, phase in
            AudioService.shared.setAmbience(phase == .active)
        }
    }
}
