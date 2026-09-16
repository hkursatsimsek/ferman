import SwiftUI

extension View {
    /// Order card at rest — a flat drop plus a soft float (token reference 1b, "normal").
    func fermanCardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 2)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 8)
    }

    /// Order card lifted for a drag — the paper rises off the stack (1b, "sürükleniyor").
    func fermanDraggingShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 2)
            .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 14)
    }

    /// Order card while its parameter dial is open (1d).
    func fermanEditingShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 2)
            .shadow(color: .black.opacity(0.55), radius: 15, x: 0, y: 14)
    }

    /// Primary button and other elevated brass controls.
    func fermanButtonShadow() -> some View {
        self.shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 6)
    }

    /// Bottom sheet and parameter dial popovers rising off the table.
    func fermanSheetShadow() -> some View {
        self.shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: -4)
    }

    /// Reference-card float used only in design previews (token page).
    func fermanFloatShadow() -> some View {
        self.shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 18)
    }
}
