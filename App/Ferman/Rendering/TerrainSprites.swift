import UIKit

/// The objects the sand table is dressed with — model trees and loose stones — rendered in Blender
/// with the figures (D25, `Tools/figures/figures.py`) and kept in `Assets.xcassets/Terrain`.
/// `TerrainBaker` lays them out; this only loads them.
nonisolated struct TerrainSprites: Sendable {
    struct Tree: Sendable {
        let image: CGImage
        let shadow: CGImage
    }

    let trees: [Tree]
    let stones: [CGImage]

    /// Side of a tree image's square canvas, and the crown's radius within it, in points.
    static let treeCanvasPoints: CGFloat = 24
    static let treeCrownPoints: CGFloat = 7
    /// Side of a stone cluster's square canvas, in points.
    static let stonesCanvasPoints: CGFloat = 12

    static let bundled = TerrainSprites(bundle: .main)

    init(bundle: Bundle) {
        func image(_ name: String) -> CGImage? {
            UIImage(named: name, in: bundle, with: nil)?.cgImage
        }
        trees = (0..<4).compactMap { variant in
            guard let tree = image("terrain-tree-\(variant)"), let shadow = image("terrain-tree-\(variant)-shadow")
            else { return nil }
            return Tree(image: tree, shadow: shadow)
        }
        stones = (0..<3).compactMap { image("terrain-stones-\($0)") }
    }
}
