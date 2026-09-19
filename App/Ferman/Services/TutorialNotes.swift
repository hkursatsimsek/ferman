import SwiftUI
import TipKit

/// The first three fronts teach by pencil notes left on the table (G13, FERMAN-PLAN §6): a short line
/// where the player is about to act, never a modal. TipKit keeps track of which notes were read and
/// closed or acted on; which note a screen shows is decided by the front it's on, not by TipKit rules.
///
/// Wording follows the brief's calm officer (§7) and CLAUDE.md's word list — orders, slips, write.
enum TutorialNotes {
    /// Called once at launch, before any note is shown. `-uiTestSandbox` hides the notes so screen tests
    /// start from the same layout; `-uiTestTips` starts from a fresh datastore instead, so the notes
    /// behave for real — TipKit's own show-all override would bring a closed note straight back.
    static func configure(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) {
        do {
            let freshNotes = arguments.contains("-uiTestTips")
            if freshNotes || defaults.bool(forKey: resetKey) {
                try Tips.resetDatastore()
                defaults.set(false, forKey: resetKey)
            }
            if arguments.contains("-uiTestSandbox"), !freshNotes {
                Tips.hideAllTipsForTesting()
            }
            try Tips.configure([.displayFrequency(.immediate)])
        } catch {
            // Notes are a help, never a requirement: without them the game plays the same.
        }
    }

    /// Ayarlar' "notları yeniden göster": TipKit can only clear its records before it's configured, so
    /// the notes come back from the next launch.
    static let resetKey = "settings.resetTutorialNotes"
}

/// A note whose words `PencilNoteStyle` sets itself: TipKit's own title and message come with a font and
/// limits a style can't override (the title drew in the system face, and the accessibility audit found it
/// clipped).
nonisolated protocol PencilNote: Tip {
    var heading: LocalizedStringResource { get }
    var line: LocalizedStringResource { get }
}

extension PencilNote {
    nonisolated var title: Text { Text(heading) }
    nonisolated var message: Text? { Text(line) }
    nonisolated var options: [any TipOption] { [MaxDisplayCount(3)] }
}

/// 1. cephe, army setup: the first thing a new player has to do.
nonisolated struct DeployNote: PencilNote {
    var id: String { "note.front1.deploy" }
    var heading: LocalizedStringResource { "Birliklerini diz." }
    var line: LocalizedStringResource { "Tepsiden bir birim seç, sonra alttaki bölgende bir kareye dokun." }
}

/// 1. cephe, orders: nothing can be written here — the point is to watch the default order at work.
nonisolated struct DefaultOrderNote: PencilNote {
    var id: String { "note.front1.default" }
    var heading: LocalizedStringResource { "Emirsiz birlik ne yapar?" }
    var line: LocalizedStringResource { "Varsayılan emri uygular: İLERLE. Savaşı başlat ve izle." }
}

/// 2. cephe, orders: one slip, one condition.
nonisolated struct FirstOrderNote: PencilNote {
    var id: String { "note.front2.first-order" }
    var heading: LocalizedStringResource { "İlk emrini yaz." }
    var line: LocalizedStringResource { "Okçular yakın dövüşte ezilir. “Emir ekle”: düşman yaklaşınca GERİ ÇEKİL. Mesafeyi kadranla ayarla." }
}

/// 3. cephe, orders: two slips, and the order they're read in.
nonisolated struct PriorityNote: PencilNote {
    var id: String { "note.front3.priority" }
    var heading: LocalizedStringResource { "Pusulalar yukarıdan okunur." }
    var line: LocalizedStringResource { "Koşulu tutan ilk emir uygulanır, altındakilere sıra gelmez. Sırayı sürükleyerek değiştir." }
}

/// 3. cephe, battle: the evaluating pen in the strip.
nonisolated struct PenNote: PencilNote {
    var id: String { "note.front3.pen" }
    var heading: LocalizedStringResource { "Bir figüre dokun." }
    var line: LocalizedStringResource { "Kalem onun emirlerini yukarıdan okur ve tutan ilk emirde durur." }
}
