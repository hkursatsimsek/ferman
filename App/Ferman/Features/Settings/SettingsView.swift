import SwiftUI

/// Ayarlar — a short sheet of paper, not a settings app: two choices and a line on what follows the
/// system instead.
struct SettingsView: View {
    @State var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FermanSpacing.lg) {
                Toggle(isOn: $model.soundEnabled) {
                    Text(String(localized: "Ses"))
                        .font(FermanFont.sectionTitle())
                        .foregroundStyle(Color.paper)
                }
                .tint(Color.brass)

                VStack(alignment: .leading, spacing: FermanSpacing.sm) {
                    Text(String(localized: "Savaş şu hızda başlasın"))
                        .font(FermanFont.sectionTitle())
                        .foregroundStyle(Color.paper)
                    SpeedControl(selection: $model.defaultSpeed)
                }

                // Once asked for, the button gives way to a line saying when — rather than sitting there
                // disabled, which SwiftUI fades below readable contrast (G12).
                if model.tutorialNotesWillReturn {
                    Text(String(localized: "İlk üç cephenin kalem notları, oyunu bir sonraki açışında yeniden görünecek."))
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.paper.opacity(0.8))
                } else {
                    Button(String(localized: "Öğretici notlarını yeniden göster")) {
                        model.showTutorialNotesAgain()
                    }
                    .buttonStyle(FermanButton.Outline())
                }

                Text(String(localized: "Titreşim ve azaltılmış hareket, cihazının kendi ayarlarına uyar."))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.7))
            }
            .padding(FermanSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.ink)
        .navigationTitle(String(localized: "Ayarlar"))
    }
}

#Preview("SettingsView") {
    NavigationStack {
        SettingsView(model: SettingsModel())
    }
    .preferredColorScheme(.dark)
}
