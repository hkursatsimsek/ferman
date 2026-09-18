import FermanCore
import SwiftUI

/// Single reference page for every DesignSystem token and component (design brief §8, step 1).
/// Not a game screen — a working checkpoint for F1.2.
struct TokenReferenceView: View {
    @State private var speed: BattleSpeed = .x2
    @State private var dialValue = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FermanSpacing.xxl) {
                header
                colorSwatches
                typeScale
                radiusScale
                spacingScale
                orderCardStates
                otherComponents
                buttons
                sandTablePreview
            }
            .padding(FermanSpacing.lg)
        }
        .background(Color.ink)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xxs) {
            Text("Kum Masası")
                .font(FermanFont.screenTitle())
                .tracking(FermanFont.Tracking.screenTitle)
                .foregroundStyle(Color.paper)
            Text("Malzeme tokenları. Marka rengi yok: soğuk kum, ham kâğıt, oksitlenmiş pirinç, çiğ demir.")
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.65))
        }
    }

    private var colorSwatches: some View {
        let swatches: [(String, Color)] = [
            ("ink", .ink), ("slate", .slate), ("slateRaised", .slateRaised),
            ("sand", .sand), ("sandLit", .sandLit), ("paper", .paper),
            ("paperInk", .paperInk), ("brass", .brass), ("iron", .iron),
            ("spark", .spark), ("alarm", .alarm),
        ]
        return sectionLabel("Renk") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: FermanSpacing.xs), count: 4),
                spacing: FermanSpacing.xs
            ) {
                ForEach(swatches, id: \.0) { name, color in
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(color).frame(height: 48)
                        Text(name)
                            .font(.custom("Archivo-Medium", size: 12))
                            .foregroundStyle(Color.paper)
                            .padding(.horizontal, FermanSpacing.xs)
                            .padding(.top, FermanSpacing.xxs + 2)
                            .padding(.bottom, FermanSpacing.xxs + 2)
                    }
                    .background(Color.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.paper.opacity(0.14)))
                }
            }
        }
    }

    private var typeScale: some View {
        sectionLabel("Tip ölçeği") {
            VStack(alignment: .leading, spacing: FermanSpacing.sm) {
                Text("Cephe Yarıldı").font(FermanFont.screenTitle()).tracking(FermanFont.Tracking.screenTitle)
                Text("14. Cephe — Taş Geçit").font(FermanFont.sectionTitle()).tracking(FermanFont.Tracking.sectionTitle)
                Text("düşman 3 kareden yakınsa").font(FermanFont.orderCondition())
                Text("GERİ ÇEKİL").font(FermanFont.orderAction()).tracking(FermanFont.Tracking.orderAction)
                Text("Askerlerin emir almazsa düşmana doğru yürür.").font(FermanFont.body())
                Text("Sis — düşman kompozisyonu gizli").font(FermanFont.caption()).opacity(0.65)
            }
            .foregroundStyle(Color.paper)
        }
    }

    private var radiusScale: some View {
        sectionLabel("Köşe yarıçapı") {
            HStack(spacing: FermanSpacing.lg) {
                VStack {
                    RoundedRectangle(cornerRadius: FermanRadius.orderCard).fill(Color.paper).frame(
                        width: 52, height: 34)
                    Text("pusula 2pt")
                }
                VStack {
                    RoundedRectangle(cornerRadius: FermanRadius.panel).fill(Color.slateRaised).frame(
                        width: 52, height: 34)
                    Text("panel 14pt")
                }
                VStack {
                    RoundedRectangle(cornerRadius: FermanRadius.button).fill(Color.brass).frame(width: 52, height: 34)
                    Text("buton 8pt")
                }
                VStack {
                    UnitToken(type: "okcu", size: .tray)
                    Text("jeton")
                }
            }
            .font(FermanFont.caption())
            .foregroundStyle(Color.paper.opacity(0.7))
        }
    }

    private var spacingScale: some View {
        sectionLabel("Boşluk — 4pt tabanı") {
            HStack(alignment: .bottom, spacing: FermanSpacing.xs) {
                let scale: [CGFloat] = [
                    FermanSpacing.xxs, FermanSpacing.xs, FermanSpacing.sm, FermanSpacing.md,
                    FermanSpacing.lg, FermanSpacing.xl, FermanSpacing.xxl,
                ]
                ForEach(scale, id: \.self) { value in
                    VStack(spacing: FermanSpacing.xxs) {
                        Color.brass.frame(width: value, height: value)
                        Text("\(Int(value))").font(.system(size: 10)).foregroundStyle(Color.paper.opacity(0.5))
                    }
                }
            }
        }
    }

    private var orderCardStates: some View {
        sectionLabel("EmirPusulası") {
            OrderStack(items: [
                .init(priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal),
                .init(priority: 2, condition: "canım %35'in altındaysa", action: "SİPER AL", state: .dragging),
                .init(
                    priority: 1, condition: "düşman 3 kareden yakınsa", action: "GERİ ÇEKİL",
                    state: .triggered(count: 14)),
                .init(priority: 3, condition: "düşman okçuysa", action: "KUŞAT", state: .disabled),
                .init(priority: 4, condition: "başka durumda", action: "İLERLE", state: .isDefault),
            ])
        }
    }

    private var otherComponents: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xxl) {
            sectionLabel("BirimJetonu") {
                HStack(alignment: .bottom, spacing: FermanSpacing.md) {
                    UnitToken(type: "mizrakci", size: .onTable(cellSize: 26))
                    UnitToken(type: "okcu", size: .tray)
                    UnitToken(type: "suvari", size: .tray, isSelected: true)
                    UnitToken(type: "kalkan", team: .enemy, size: .result)
                }
            }
            sectionLabel("TetiklenmeÇubuğu") {
                VStack(spacing: FermanSpacing.sm) {
                    TriggerBar(priority: 1, fraction: 0.74, count: 14, isSpark: false)
                    TriggerBar(priority: 2, fraction: 0.42, count: 8, isSpark: true)
                    TriggerBar(priority: 3, fraction: 0, count: 0, isSpark: false)
                }
            }
            sectionLabel("BütçeGöstergesi") {
                VStack(spacing: FermanSpacing.md) {
                    BudgetMeter(label: "Bütçe", used: 248, total: 310)
                    BudgetMeter(label: "Aşım", used: 335, total: 310)
                }
            }
            sectionLabel("CepheBayrağı") {
                HStack(alignment: .bottom, spacing: FermanSpacing.lg) {
                    VStack {
                        FrontFlag(state: .cleared)
                        Text("geçildi")
                    }
                    VStack {
                        FrontFlag(state: .open)
                        Text("açık").foregroundStyle(Color(hex: 0xC2A05C))
                    }
                    VStack {
                        FrontFlag(state: .locked)
                        Text("kilitli")
                    }
                }
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.5))
            }
            sectionLabel("SpeedControl") {
                SpeedControl(selection: $speed)
            }
            sectionLabel("ParametreKadranı") {
                ParameterDial(label: "Mesafe", unit: "kare", value: $dialValue, range: 1...8)
                    .frame(maxWidth: 220)
            }
        }
    }

    private var buttons: some View {
        sectionLabel("BirincilButon ve türevleri") {
            VStack(spacing: FermanSpacing.md) {
                Button("Savaşı Başlat") {}.buttonStyle(FermanButton.Primary())
                Button("Savaşı Başlat") {}.buttonStyle(FermanButton.Primary()).disabled(true)
                Button("Klibi Paylaş") {}.buttonStyle(FermanButton.Outline())
                Button("Hazır emir setlerini gör") {}.buttonStyle(FermanButton.Chip())
                HStack {
                    Button("İzle") {}.buttonStyle(FermanButton.Ghost())
                    Button("Yaz") {}.buttonStyle(FermanButton.Ghost())
                    Spacer()
                }
            }
        }
    }

    private var sandTablePreview: some View {
        sectionLabel("KumMasası") {
            SandTable()
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: FermanRadius.button))
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: FermanSpacing.md) {
            Text(title.uppercased())
                .font(.custom("Archivo-Medium", size: 11))
                .tracking(0.6)
                .foregroundStyle(Color.paper.opacity(0.5))
            content()
        }
    }
}

#Preview("Token referans sayfası") {
    TokenReferenceView()
}
