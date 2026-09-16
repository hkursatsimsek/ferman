import SwiftUI

enum BattleSpeed: Int, CaseIterable {
    case x1 = 1
    case x2 = 2
    case x4 = 4
}

/// SpeedControl — 1×/2×/4× segmented control from the battle screen's top bar.
struct SpeedControl: View {
    @Binding var selection: BattleSpeed

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BattleSpeed.allCases, id: \.self) { speed in
                let isSelected = speed == selection
                Button {
                    selection = speed
                } label: {
                    Text("\(speed.rawValue)×")
                        .font(.custom("Archivo-Medium", size: 13))
                        .foregroundStyle(isSelected ? Color.ink : Color.paper.opacity(0.5))
                        .padding(.horizontal, FermanSpacing.sm - 3)
                        .padding(.vertical, FermanSpacing.xs - 2)
                        .background(isSelected ? Color.brass : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.paper.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("SpeedControl", traits: .sizeThatFitsLayout) {
    SpeedControl(selection: .constant(.x2))
        .padding()
        .background(Color.slate)
}
