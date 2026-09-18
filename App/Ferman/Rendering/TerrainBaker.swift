import CoreGraphics
import FermanCore

/// Paints a map's sand table once, into one image, for the battle (`SKTexture`) and army setup
/// (`Image`) alike — the table under the figures is the same picture on both screens.
///
/// Everything comes from the sand-table vocabulary (ART-DIRECTION §5): a cold lamp-lit sand bed in a
/// dark rim, hills drawn with Lehmann's slope hachures, model-tree tufts for forest, a dark resin
/// channel for water, loose stones for rubble, a barely-there cell grid. Placement jitter is hashed
/// from cell coordinates — no randomness, so the same map always bakes the same bytes.
///
/// `nonisolated`: pure Core Graphics, safe to run off the main actor.
nonisolated enum TerrainBaker {
    /// Pixels per scene point for the battle texture — about the density SpriteKit ends up drawing
    /// an upright board at on a phone.
    static let battlePixelsPerPoint: CGFloat = 2

    static func bake(map: BattleMap, projection: BoardProjection, pixelsPerPoint: CGFloat) -> CGImage? {
        let size = projection.boardSize
        let pixelWidth = Int((size.width * pixelsPerPoint).rounded())
        let pixelHeight = Int((size.height * pixelsPerPoint).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Points, origin top-left, y down — `BoardProjection`'s SwiftUI space, which `viewRect` speaks.
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        var painter = Painter(context: context, map: map, projection: projection)
        painter.paint()
        return context.makeImage()
    }
}

// MARK: - Palette

nonisolated private enum TablePalette {
    static let rimTop = color(0x24323A)
    static let rimBottom = color(0x121A1F)
    static let sandLit = color(0x7A8780)
    static let sand = color(0x5E6A63)
    static let sandEdge = color(0x454E49)
    static let ink = color(0x0F161B)
    static let paper = color(0xD6D0C2)
    static let treeLight = color(0x5B685F)
    static let treeDark = color(0x333F38)
    static let resin = color(0x1B272D)
    static let resinGlint = color(0x8FAAB2)
    static let stoneLight = color(0x847E77)
    static let stoneDark = color(0x57524C)

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Painter

nonisolated private struct Painter {
    let context: CGContext
    let map: BattleMap
    let projection: BoardProjection

    private var cell: CGFloat { projection.pointsPerCell }

    mutating func paint() {
        paintRim()
        paintSand()
        paintGrain()
        paintWater()
        paintHills()
        paintRubble()
        paintForest()
        paintGrid()
        paintFieldEdge()
    }

    private func terrain(column: Int, row: Int) -> Terrain? {
        guard let index = map.cellIndex(column: column, row: row) else { return nil }
        return map.terrain[index]
    }

    private func cells(of kind: Terrain) -> [(column: Int, row: Int)] {
        var result: [(column: Int, row: Int)] = []
        for row in 0..<map.height {
            for column in 0..<map.width where terrain(column: column, row: row) == kind {
                result.append((column, row))
            }
        }
        return result
    }

    /// A stable pseudo-random value in `0..<1` for a cell and a purpose (`salt`). SplitMix64's
    /// finaliser: cheap, well mixed, and the same on every run and platform.
    private func noise(_ column: Int, _ row: Int, _ salt: Int) -> CGFloat {
        var value = UInt64(bitPattern: Int64(column &* 73_856_093 ^ row &* 19_349_663 ^ salt &* 83_492_791))
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return CGFloat(value >> 11) / CGFloat(UInt64(1) << 53)
    }

    // MARK: Table

    private func paintRim() {
        let board = CGRect(origin: .zero, size: projection.boardSize)
        drawLinearGradient(
            in: board, colors: [TablePalette.rimTop, TablePalette.rimBottom],
            from: CGPoint(x: board.midX, y: board.minY), to: CGPoint(x: board.midX, y: board.maxY))
    }

    /// One lamp overhead, a little above the table's centre (brief §3.1): lit sand falling off to the
    /// shadowed edge, with the design mock's darker fourth stop at the very rim.
    private func paintSand() {
        let field = projection.fieldRect
        context.saveGState()
        context.clip(to: field)
        let center = CGPoint(x: field.midX, y: field.minY + field.height * 0.34)
        let radius = field.width * 0.7
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: (field.height * 0.5) / radius)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [TablePalette.sandLit, TablePalette.sand, TablePalette.sandEdge] as CFArray,
            // Locations must stay within 0...1 or Core Graphics returns no gradient at all — and the
            // sand silently isn't drawn. The dark edge stop sits a quarter past the lit falloff.
            locations: [0, 0.58, 1])
        {
            context.drawRadialGradient(
                gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius * 1.25,
                options: [.drawsAfterEndLocation])
        }
        context.restoreGState()
    }

    private func paintGrain() {
        context.saveGState()
        context.clip(to: projection.fieldRect)
        for row in 0..<map.height {
            for column in 0..<map.width {
                let rect = projection.viewRect(column: column, row: row)
                for grain in 0..<14 {
                    let point = CGPoint(
                        x: rect.minX + noise(column, row, grain * 2) * rect.width,
                        y: rect.minY + noise(column, row, grain * 2 + 1) * rect.height)
                    let radius = 0.3 + noise(column, row, grain + 101) * 0.5
                    let dark = noise(column, row, grain + 211) < 0.6
                    context.setFillColor(
                        dark
                            ? TablePalette.ink.copy(alpha: 0.10) ?? TablePalette.ink
                            : TablePalette.paper.copy(alpha: 0.07) ?? TablePalette.paper)
                    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                }
            }
        }
        context.restoreGState()
    }

    // MARK: Terrain

    private func paintWater() {
        let water = cells(of: .water)
        guard !water.isEmpty else { return }
        for cell in water {
            context.setFillColor(TablePalette.resin)
            context.fill(projection.viewRect(column: cell.column, row: cell.row))
        }
        // Banks: a dark edge wherever water meets land, lit on its near side.
        for cell in water {
            let rect = projection.viewRect(column: cell.column, row: cell.row)
            for (dc, dr, edge) in [(1, 0, CGRectEdge.minYEdge), (-1, 0, .maxYEdge), (0, -1, .minXEdge), (0, 1, .maxXEdge)]
            where terrain(column: cell.column + dc, row: cell.row + dr) != .water {
                let line = rect.divided(atDistance: 1.4, from: edge).slice
                context.setFillColor(TablePalette.ink.copy(alpha: 0.7) ?? TablePalette.ink)
                context.fill(line)
            }
            // Glints from the lamp on the resin.
            for glint in 0..<2 {
                let y = rect.minY + (0.3 + 0.4 * noise(cell.column, cell.row, 300 + glint)) * rect.height
                let x = rect.minX + noise(cell.column, cell.row, 310 + glint) * rect.width * 0.5
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: x + rect.width * 0.45, y: y), control: CGPoint(x: x + rect.width * 0.22, y: y - 1.6))
                context.addPath(path)
                context.setStrokeColor(TablePalette.resinGlint.copy(alpha: 0.22) ?? TablePalette.resinGlint)
                context.setLineWidth(0.8)
                context.strokePath()
            }
        }
    }

    /// Lehmann's hachures (1799): short strokes running down the slope, heavier where it's steeper —
    /// here, toward the edge of each hill.
    private func paintHills() {
        for blob in blobs(of: .hill) {
            let centers = blob.map { projection.viewRect(column: $0.column, row: $0.row) }
            let centroid = CGPoint(
                x: centers.map(\.midX).reduce(0, +) / CGFloat(centers.count),
                y: centers.map(\.midY).reduce(0, +) / CGFloat(centers.count))
            let reach = centers.map { hypot($0.midX - centroid.x, $0.midY - centroid.y) }.max().map { $0 + cell * 0.7 }
                ?? cell

            // A mound, not a tile: the raised crown catches more of the lamp and fades into the sand.
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    TablePalette.sandLit.copy(alpha: 0.55) ?? TablePalette.sandLit,
                    TablePalette.sandLit.copy(alpha: 0) ?? TablePalette.sandLit,
                ] as CFArray, locations: [0, 1])
            {
                context.drawRadialGradient(
                    gradient, startCenter: centroid, startRadius: 0, endCenter: centroid, endRadius: reach, options: [])
            }
            for (cellIndex, spot) in blob.enumerated() {
                let rect = centers[cellIndex].insetBy(dx: -cell * 0.35, dy: -cell * 0.35)
                for stroke in 0..<12 {
                    let point = CGPoint(
                        x: rect.minX + (CGFloat(stroke % 4) + 0.2 + 0.6 * noise(spot.column, spot.row, 400 + stroke))
                            * rect.width / 4,
                        y: rect.minY + (CGFloat(stroke / 4) + 0.2 + 0.6 * noise(spot.column, spot.row, 420 + stroke))
                            * rect.height / 3)
                    var direction = CGVector(dx: point.x - centroid.x, dy: point.y - centroid.y)
                    let distance = max(hypot(direction.dx, direction.dy), 0.001)
                    let steepness = min(1, distance / reach)
                    // Lehmann leaves a flat crown blank, and there's no slope past the foot.
                    guard steepness > 0.3, steepness < 0.98 else { continue }
                    direction = CGVector(dx: direction.dx / distance, dy: direction.dy / distance)
                    let length = 3 + 4 * steepness
                    context.move(to: point)
                    context.addLine(to: CGPoint(x: point.x + direction.dx * length, y: point.y + direction.dy * length))
                    context.setStrokeColor(
                        TablePalette.ink.copy(alpha: 0.12 + 0.2 * steepness) ?? TablePalette.ink)
                    context.setLineWidth(0.6 + 0.7 * steepness)
                    context.setLineCap(.round)
                    context.strokePath()
                }
            }
        }
    }

    private func paintRubble() {
        for spot in cells(of: .rubble) {
            let rect = projection.viewRect(column: spot.column, row: spot.row)
            for stone in 0..<7 {
                let center = CGPoint(
                    x: rect.minX + (0.15 + 0.7 * noise(spot.column, spot.row, 500 + stone)) * rect.width,
                    y: rect.minY + (0.15 + 0.7 * noise(spot.column, spot.row, 520 + stone)) * rect.height)
                let radius = 1.6 + 1.8 * noise(spot.column, spot.row, 540 + stone)
                let path = CGMutablePath()
                for corner in 0..<5 {
                    let angle = CGFloat(corner) / 5 * 2 * .pi + noise(spot.column, spot.row, 560 + stone * 5 + corner)
                    let length = radius * (0.7 + 0.3 * noise(spot.column, spot.row, 600 + stone * 5 + corner))
                    let point = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
                    if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                shadowed { context in
                    context.addPath(path)
                    context.setFillColor(stone % 2 == 0 ? TablePalette.stoneLight : TablePalette.stoneDark)
                    context.fillPath()
                }
                context.addPath(path)
                context.setStrokeColor(TablePalette.ink.copy(alpha: 0.45) ?? TablePalette.ink)
                context.setLineWidth(0.5)
                context.strokePath()
            }
        }
    }

    /// Model-railway trees: dark tufts with a lit top, each casting a small shadow on the sand.
    private func paintForest() {
        for spot in cells(of: .forest) {
            let rect = projection.viewRect(column: spot.column, row: spot.row)
            let count = 3 + Int(noise(spot.column, spot.row, 700) * 3)
            for tuft in 0..<count {
                let center = CGPoint(
                    x: rect.minX + (0.2 + 0.6 * noise(spot.column, spot.row, 710 + tuft)) * rect.width,
                    y: rect.minY + (0.2 + 0.6 * noise(spot.column, spot.row, 730 + tuft)) * rect.height)
                let radius = 4 + 3.5 * noise(spot.column, spot.row, 750 + tuft)
                let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                shadowed { context in
                    context.setFillColor(TablePalette.treeDark)
                    context.fillEllipse(in: circle)
                }
                context.saveGState()
                context.addEllipse(in: circle)
                context.clip()
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [TablePalette.treeLight, TablePalette.treeDark] as CFArray, locations: [0, 1])
                {
                    context.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: center.x, y: center.y - radius * 0.2), startRadius: 0,
                        endCenter: center, endRadius: radius, options: [])
                }
                context.restoreGState()
                context.addEllipse(in: circle)
                context.setStrokeColor(TablePalette.ink.copy(alpha: 0.35) ?? TablePalette.ink)
                context.setLineWidth(0.6)
                context.strokePath()
            }
        }
    }

    // MARK: Grid and edge

    private func paintGrid() {
        let field = projection.fieldRect
        context.setStrokeColor(TablePalette.ink.copy(alpha: 0.07) ?? TablePalette.ink)
        context.setLineWidth(0.6)
        var x = field.minX + cell
        while x < field.maxX - 0.5 {
            context.move(to: CGPoint(x: x, y: field.minY))
            context.addLine(to: CGPoint(x: x, y: field.maxY))
            x += cell
        }
        var y = field.minY + cell
        while y < field.maxY - 0.5 {
            context.move(to: CGPoint(x: field.minX, y: y))
            context.addLine(to: CGPoint(x: field.maxX, y: y))
            y += cell
        }
        context.strokePath()
    }

    /// The rim casts a short shadow onto the sand — the field sits a little below the table's edge.
    private func paintFieldEdge() {
        let field = projection.fieldRect
        let depth: CGFloat = 6
        for edge in [CGRectEdge.minXEdge, .maxXEdge, .minYEdge, .maxYEdge] {
            let band = field.divided(atDistance: depth, from: edge).slice
            let (start, end): (CGPoint, CGPoint) =
                switch edge {
                case .minXEdge: (CGPoint(x: band.minX, y: band.midY), CGPoint(x: band.maxX, y: band.midY))
                case .maxXEdge: (CGPoint(x: band.maxX, y: band.midY), CGPoint(x: band.minX, y: band.midY))
                case .minYEdge: (CGPoint(x: band.midX, y: band.minY), CGPoint(x: band.midX, y: band.maxY))
                case .maxYEdge: (CGPoint(x: band.midX, y: band.maxY), CGPoint(x: band.midX, y: band.minY))
                }
            drawLinearGradient(
                in: band, colors: [TablePalette.ink.copy(alpha: 0.38) ?? TablePalette.ink, TablePalette.ink.copy(alpha: 0) ?? TablePalette.ink],
                from: start, to: end)
        }
        context.setStrokeColor(TablePalette.rimTop.copy(alpha: 0.9) ?? TablePalette.rimTop)
        context.setLineWidth(1)
        context.stroke(field.insetBy(dx: -0.5, dy: -0.5))
    }

    // MARK: Helpers

    private func drawLinearGradient(in rect: CGRect, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)
        else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }

    /// Draws with a soft contact shadow straight under it — the lamp is overhead (ART-DIRECTION §3).
    private func shadowed(_ draw: (CGContext) -> Void) {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.5, color: TablePalette.ink.copy(alpha: 0.55))
        draw(context)
        context.restoreGState()
    }

    /// Connected groups of one terrain kind (4-neighbourhood), each in row-major order.
    private func blobs(of kind: Terrain) -> [[(column: Int, row: Int)]] {
        var seen = Set<Int>()
        var result: [[(column: Int, row: Int)]] = []
        for start in cells(of: kind) {
            guard let startIndex = map.cellIndex(column: start.column, row: start.row), !seen.contains(startIndex)
            else { continue }
            var blob: [(column: Int, row: Int)] = []
            var queue = [start]
            seen.insert(startIndex)
            while let current = queue.popLast() {
                blob.append(current)
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let next = (column: current.column + dc, row: current.row + dr)
                    guard terrain(column: next.column, row: next.row) == kind,
                        let index = map.cellIndex(column: next.column, row: next.row), !seen.contains(index)
                    else { continue }
                    seen.insert(index)
                    queue.append(next)
                }
            }
            result.append(blob.sorted { ($0.row, $0.column) < ($1.row, $1.column) })
        }
        return result
    }
}
