import FermanCore
import SpriteKit

/// One pooled node per unit, created once when `BattleScene` learns the
/// roster from the event stream and reused for the rest of the replay —
/// no per-frame node creation (F1.4's "kare başına tahsis yok").
final class UnitNode: SKNode {
    let unitID: UnitID
    private let shape: SKShapeNode
    private let selectionRing: SKShapeNode

    static let radius: CGFloat = 10

    init(unitID: UnitID, team: Team) {
        self.unitID = unitID
        shape = SKShapeNode(circleOfRadius: Self.radius)
        shape.fillColor = team == .player ? Self.brassColor : Self.ironColor
        shape.strokeColor = .clear
        shape.lineWidth = 0

        selectionRing = SKShapeNode(circleOfRadius: Self.radius + 3)
        selectionRing.fillColor = .clear
        selectionRing.strokeColor = Self.brassColor
        selectionRing.lineWidth = 2
        selectionRing.isHidden = true

        super.init()
        addChild(shape)
        addChild(selectionRing)
        name = Self.nodeName(for: unitID)
        zPosition = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UnitNode does not support archiving")
    }

    var isSelected: Bool {
        get { !selectionRing.isHidden }
        set { selectionRing.isHidden = !newValue }
    }

    static func nodeName(for unitID: UnitID) -> String {
        "unit-\(unitID.rawValue)"
    }

    private static let brassColor = SKColor(red: 0x9A / 255, green: 0x7B / 255, blue: 0x3F / 255, alpha: 1)
    private static let ironColor = SKColor(red: 0x6C / 255, green: 0x66 / 255, blue: 0x60 / 255, alpha: 1)
}
