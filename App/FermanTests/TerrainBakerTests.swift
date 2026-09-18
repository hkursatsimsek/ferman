import CoreGraphics
import FermanCore
import Testing

@testable import Ferman

struct TerrainBakerTests {
    /// 5 columns x 3 rows: water down column 2, a hill, forest and rubble on the rest.
    private static func map() throws -> BattleMap {
        try BattleMap(terrainRows: ["H.W.F", "..W.R", "..W.."], zoneRows: ["P...E", "P...E", "P...E"])
    }

    private static let projection = BoardProjection(mapWidth: 5, mapHeight: 3, pointsPerCell: 32, rimCells: 0.75)

    private static func bake(scale: CGFloat = 2) throws -> CGImage {
        try #require(TerrainBaker.bake(map: try map(), projection: projection, pixelsPerPoint: scale))
    }

    @Test
    func theImageCoversTheWholeBoardAtTheRequestedDensity() throws {
        let image = try Self.bake(scale: 2)
        #expect(image.width == Int(Self.projection.boardSize.width * 2))
        #expect(image.height == Int(Self.projection.boardSize.height * 2))
    }

    /// Placement jitter is hashed from cell coordinates: the same map is the same picture every time.
    @Test
    func bakingIsReproducible() throws {
        #expect(try Pixels(Self.bake()).bytes == Pixels(Self.bake()).bytes)
    }

    @Test
    func waterIsDarkerThanOpenSand() throws {
        let pixels = try Pixels(Self.bake())
        let water = Self.projection.viewRect(column: 2, row: 1)
        let open = Self.projection.viewRect(column: 1, row: 1)
        #expect(pixels.luminance(atPoint: CGPoint(x: water.midX, y: water.midY), scale: 2)
            < pixels.luminance(atPoint: CGPoint(x: open.midX, y: open.midY), scale: 2) - 0.1)
    }

    @Test
    func theRimIsDarkerThanTheSand() throws {
        let pixels = try Pixels(Self.bake())
        let field = Self.projection.fieldRect
        let rim = CGPoint(x: field.minX / 2, y: field.midY)
        let open = Self.projection.viewRect(column: 1, row: 1)
        #expect(pixels.luminance(atPoint: rim, scale: 2) < pixels.luminance(atPoint: CGPoint(x: open.midX, y: open.midY), scale: 2))
    }
}

/// An image's RGBA bytes, top row first — the same orientation as `BoardProjection`'s view space.
private struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        bytes = buffer
    }

    /// Rec. 709 luma in 0...1 at a point in view space (points, y down).
    func luminance(atPoint point: CGPoint, scale: CGFloat) -> Double {
        let x = min(max(Int(point.x * scale), 0), width - 1)
        let y = min(max(Int(point.y * scale), 0), height - 1)
        let offset = (y * width + x) * 4
        return (0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1]) + 0.0722 * Double(bytes[offset + 2]))
            / 255
    }
}
