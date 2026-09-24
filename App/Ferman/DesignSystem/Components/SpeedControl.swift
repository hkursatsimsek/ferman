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
        // Each segment is a full 44 pt target around a compact pill (accessibility audit, G15).
        HStack(spacing: 0) {
            ForEach(BattleSpeed.allCases, id: \.self) { speed in
                let isSelected = speed == selection
                Button {
                    selection = speed
                } label: {
                    // The brass fills the whole target, not a pill inside it: the audit samples the
                    // element's frame, and ink on a small pill inside dark glass read as ink on dark.
                    Text("\(speed.rawValue)×")
                        .font(.custom("Archivo-Medium", size: 15))
                        .foregroundStyle(isSelected ? Color.ink : Color.paper)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(isSelected ? Color.brass : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background(Color.paper.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("SpeedControl", traits: .sizeThatFitsLayout) {
    SpeedControl(selection: .constant(.x2))
        .padding()
        .background(Color.slate)
}
