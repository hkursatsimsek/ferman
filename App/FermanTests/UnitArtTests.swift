import FermanContent
import FermanCore
import Testing
import UIKit

@testable import Ferman

/// Every unit the bundled catalog can field has its art (D24, D25): a missing image would draw an
/// empty square in battle and nothing in the tray, with no error anywhere.
@MainActor
struct UnitArtTests {
    private static let unitTypes: [UnitTypeID] = (try? ContentCatalog.bundled().units.map(\.id)) ?? []

    @Test
    func theBundledCatalogHasUnits() {
        #expect(!Self.unitTypes.isEmpty)
    }

    @Test(arguments: Team.allCases, UnitPose.allCases)
    func everyUnitTypeHasAFigure(team: Team, pose: UnitPose) throws {
        for type in Self.unitTypes {
            let name = UnitArt.imageName(type: type, team: team, pose: pose)
            let image = try #require(UIImage(named: name), "missing \(name)")
            #expect(image.size == CGSize(width: UnitArt.canvasPoints, height: UnitArt.canvasPoints), "\(name)")
        }
    }

    @Test(arguments: [false, true])
    func everyUnitTypeHasAShadow(fallen: Bool) {
        for type in Self.unitTypes {
            #expect(UIImage(named: UnitArt.shadowName(type: type, fallen: fallen)) != nil, "\(type)")
        }
    }

    @Test
    func theSelectionRingExists() {
        #expect(UIImage(named: UnitArt.selectionRingName) != nil)
    }

    @Test
    func namesFollowTypeMaterialAndPose() {
        #expect(UnitArt.imageName(type: "okcu", team: .player, pose: .base) == "okcu-brass-base")
        #expect(UnitArt.imageName(type: "kalkan", team: .enemy, pose: .fallen) == "kalkan-iron-fallen")
        #expect(UnitArt.shadowName(type: "suvari", fallen: true) == "shadow-suvari-fallen")
    }

    @Test
    func aTableTokenKeepsTheBattlesProportionToItsCell() {
        // 48pt canvas on a 32pt battle cell → 1.5× the cell anywhere else too.
        #expect(UnitTokenSize.onTable(cellSize: 20).canvas == 30)
    }
}
