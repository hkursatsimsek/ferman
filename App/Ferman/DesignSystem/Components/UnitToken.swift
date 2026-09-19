import FermanCore
import SwiftUI

enum UnitTokenSize: Equatable {
    /// On a placement grid: the figure keeps the battle's proportion to its cell (a 48pt canvas on a
    /// 32pt cell), so a unit looks the same placed as it does fighting (D24).
    case onTable(cellSize: CGFloat)
    case tray
    case result
    /// Beside a label in a tab or chip.
    case chip

    /// Side of the square canvas the figure is drawn in (base centred, weapons reaching out).
    var canvas: CGFloat {
        switch self {
        case .onTable(let cellSize): cellSize * UnitArt.canvasPoints / BoardProjection.scenePointsPerCell
        case .tray: 64
        case .result: 48
        case .chip: 30
        }
    }
}

/// BirimJetonu — a cast-metal miniature seen from above, told apart by silhouette: the spearman's
/// long spear, the archer's bow and quiver, the horse, the broad shield (D24). The player's figures
/// stand on round brass bases, the enemy's on octagonal iron ones — never colour alone.
///
/// Decorative to VoiceOver: whoever places a token names the unit in its own label.
struct UnitToken: View {
    let type: UnitTypeID
    var team: Team = .player
    let size: UnitTokenSize
    var pose: UnitPose = .base
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // The lamp is above the screen here: the shadow falls a little down, clear of the base.
            Image(decorative: UnitArt.shadowName(type: type, fallen: pose == .fallen))
                .resizable()
                .offset(y: size.canvas * 0.04)
            Image(decorative: UnitArt.imageName(type: type, team: team, pose: pose))
                .resizable()
            if isSelected {
                Image(decorative: UnitArt.selectionRingName)
                    .resizable()
            }
        }
        .frame(width: size.canvas, height: size.canvas)
        .accessibilityHidden(true)
    }
}

#Preview("UnitToken", traits: .sizeThatFitsLayout) {
    VStack(spacing: FermanSpacing.md) {
        HStack(spacing: FermanSpacing.md) {
            ForEach(["mizrakci", "okcu", "suvari", "kalkan"] as [UnitTypeID], id: \.self) { type in
                UnitToken(type: type, size: .tray)
            }
        }
        HStack(spacing: FermanSpacing.md) {
            ForEach(["mizrakci", "okcu", "suvari", "kalkan"] as [UnitTypeID], id: \.self) { type in
                UnitToken(type: type, team: .enemy, size: .tray)
            }
        }
        HStack(spacing: FermanSpacing.md) {
            UnitToken(type: "okcu", size: .onTable(cellSize: 26))
            UnitToken(type: "okcu", size: .tray, isSelected: true)
            UnitToken(type: "kalkan", size: .result, pose: .brace)
            UnitToken(type: "suvari", team: .enemy, size: .result, pose: .fallen)
        }
    }
    .padding()
    .background(Color.sand)
}
