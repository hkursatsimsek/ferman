import Foundation
import Observation

struct HomeMenuRow: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

/// AnaMenü (design brief §4.1). Only "Seferberlik" leads anywhere in Faz 1 — Arena (F4.x/F5.x),
/// Emir Kütüphanesi (F4.8) and Ayarlar don't exist yet, so their rows are shown per the brief's
/// mockup but disabled rather than wired to invented data.
@Observable
@MainActor
final class HomeModel {
    let campaignSubtitle: String
    let secondaryRows: [HomeMenuRow]

    init(nextFront: CampaignFront?) {
        if let nextFront {
            campaignSubtitle = String(localized: "\(nextFront.id). cephe")
        } else {
            campaignSubtitle = String(localized: "Tüm cepheler geçildi")
        }
        secondaryRows = [
            HomeMenuRow(
                id: "arena", title: String(localized: "Arena"), subtitle: String(localized: "3 maç bekliyor")),
            HomeMenuRow(id: "library", title: String(localized: "Emir Kütüphanesi"), subtitle: ""),
            HomeMenuRow(id: "settings", title: String(localized: "Ayarlar"), subtitle: ""),
        ]
    }
}
