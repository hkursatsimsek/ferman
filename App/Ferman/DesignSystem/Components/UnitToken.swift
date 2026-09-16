import SwiftUI

enum UnitTokenTeam {
    case brass
    case iron

    var gradient: RadialGradient {
        switch self {
        case .brass:
            RadialGradient(
                colors: [Color(hex: 0xC2A05C), Color(hex: 0x9A7B3F), Color(hex: 0x6B5426)],
                center: UnitPoint(x: 0.34, y: 0.28),
                startRadius: 0,
                endRadius: 30
            )
        case .iron:
            RadialGradient(
                colors: [Color(hex: 0x837D76), Color(hex: 0x6C6660), Color(hex: 0x4A453F)],
                center: UnitPoint(x: 0.34, y: 0.28),
                startRadius: 0,
                endRadius: 30
            )
        }
    }

    var ringColor: Color {
        switch self {
        case .brass: Color(hex: 0xC2A05C)
        case .iron: Color(hex: 0x837D76)
        }
    }
}

enum UnitTokenSize {
    case table
    case tray
    case result

    var diameter: CGFloat {
        switch self {
        case .table: 22
        case .tray: 44
        case .result: 34
        }
    }
}

/// BirimJetonu — a cast-metal figure. Silhouette only, no detail (design brief §4.3).
struct UnitToken: View {
    let team: UnitTokenTeam
    let size: UnitTokenSize
    var isSelected: Bool = false

    var body: some View {
        Circle()
            .fill(team.gradient)
            .overlay(
                Circle().strokeBorder(team.ringColor, lineWidth: isSelected ? 2 : 0)
                    .padding(isSelected ? -2 : 0)
            )
            .frame(width: size.diameter, height: size.diameter)
            .shadow(color: .black.opacity(0.5), radius: size == .table ? 2.5 : 3.5, x: 0, y: size == .table ? 3 : 4)
    }
}

#Preview("UnitToken", traits: .sizeThatFitsLayout) {
    HStack(alignment: .bottom, spacing: FermanSpacing.md) {
        UnitToken(team: .brass, size: .table)
        UnitToken(team: .brass, size: .tray)
        UnitToken(team: .brass, size: .tray, isSelected: true)
        UnitToken(team: .iron, size: .result)
    }
    .padding()
    .background(Color.ink)
}
