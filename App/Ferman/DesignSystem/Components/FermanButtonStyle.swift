import SwiftUI

/// BirincilButon and its outline/ghost/chip siblings (design brief §5).
/// Only one primary per screen; the others are for secondary and inline actions.
enum FermanButton {
    struct Primary: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(FermanFont.buttonLabel())
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(isEnabled ? Color.ink : Color.paper.opacity(0.32))
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: FermanRadius.button))
                .modifier(EnabledShadow(isEnabled: isEnabled))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }

        @ViewBuilder
        private var background: some View {
            if isEnabled {
                // The lit brass (F1.13's contrast fix), not the shadowed one: ink on the old gradient
                // measured ~4.8:1 at the bottom of the button and the accessibility audit flagged it.
                LinearGradient(
                    colors: [Color(hex: 0xC2A05C), Color(hex: 0xA8873F)], startPoint: .top, endPoint: .bottom)
            } else {
                Color.paper.opacity(0.08)
            }
        }

        private struct EnabledShadow: ViewModifier {
            let isEnabled: Bool
            func body(content: Content) -> some View {
                if isEnabled {
                    AnyView(content.fermanButtonShadow())
                } else {
                    AnyView(content)
                }
            }
        }
    }

    struct Outline: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.custom("Archivo-Medium", size: 17))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color.paper.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: FermanRadius.button)
                        .strokeBorder(Color.paper.opacity(0.2), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }

    /// Small pill, used inline ("Yaz", "İzle").
    struct Ghost: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(FermanFont.chipLabel())
                .foregroundStyle(Color.brass)
                .padding(.horizontal, FermanSpacing.sm)
                .padding(.vertical, FermanSpacing.xxs)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.brass.opacity(0.5), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }

    /// A whole row as the button (menu rows, campaign pins). Draws the label exactly as given, also when
    /// disabled: `.plain` fades a disabled label to ~2.5:1 contrast, which made a locked row unreadable
    /// rather than merely unavailable (accessibility audit, G12). The row says it's locked in its own
    /// words and marks; `.disabled` still stops the tap and tells VoiceOver.
    struct Row: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }

    /// Larger outline chip, used for standalone secondary prompts ("Hazır emir setlerini gör").
    struct Chip: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.custom("PublicSans-Medium", size: 15))
                .foregroundStyle(Color(hex: 0xC2A05C))
                .padding(.horizontal, FermanSpacing.md + 2)
                .padding(.vertical, FermanSpacing.sm - 1)
                .overlay(
                    RoundedRectangle(cornerRadius: FermanRadius.button)
                        .strokeBorder(Color.brass.opacity(0.55), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

#Preview("Buton çeşitleri", traits: .sizeThatFitsLayout) {
    VStack(spacing: FermanSpacing.md) {
        Button("Savaşı Başlat") {}.buttonStyle(FermanButton.Primary())
        Button("Savaşı Başlat") {}.buttonStyle(FermanButton.Primary()).disabled(true)
        Button("Klibi Paylaş") {}.buttonStyle(FermanButton.Outline())
        Button("Hazır emir setlerini gör") {}.buttonStyle(FermanButton.Chip())
        HStack {
            Button("İzle") {}.buttonStyle(FermanButton.Ghost())
            Button("Yaz") {}.buttonStyle(FermanButton.Ghost())
        }
    }
    .padding()
    .frame(width: 320)
    .background(Color.ink)
}
