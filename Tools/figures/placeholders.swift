// Placeholder unit art (D25): top-down cast miniatures drawn with Core Graphics, written into the app's
// asset catalog under the exact names the Blender renders will later overwrite, so swapping the art never
// touches code. macOS only, no dependencies.
//
//     swift Tools/figures/placeholders.swift App/Ferman/Assets.xcassets/Units.spriteatlas
//
// Every figure image is a square canvas with the base centred and the figure facing up (+Y on screen,
// D24). Directions below are in canvas points, y growing downward, so "forward" is negative y.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasPoints: CGFloat = 48
let scales: [Int] = [2, 3]

let unitTypes = ["mizrakci", "okcu", "suvari", "kalkan"]
let poses = ["base", "strike", "brace", "fallen"]

struct Palette {
    let light: CGColor
    let mid: CGColor
    let dark: CGColor
    let rim: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let brass = Palette(light: rgb(0xE6C987), mid: rgb(0xA8843F), dark: rgb(0x5A431E), rim: rgb(0xD2B06A))
let iron = Palette(light: rgb(0xB3ADA5), mid: rgb(0x6F6963), dark: rgb(0x34302C), rim: rgb(0x938D86))
let ink = rgb(0x0F161B)
let teams: [(name: String, palette: Palette, octagonalBase: Bool)] = [
    ("brass", brass, false), ("iron", iron, true),
]

// MARK: - Drawing helpers

/// A cast-metal surface lit from straight above: brightest in the middle of each shape, falling off
/// to its edges, so the highlight stays right however the sprite is rotated.
func fillMetal(_ context: CGContext, _ path: CGPath, _ palette: Palette, outline: CGFloat = 1.1) {
    let box = path.boundingBoxOfPath
    let center = CGPoint(x: box.midX, y: box.midY)
    let radius = max(box.width, box.height) * 0.62
    context.saveGState()
    context.addPath(path)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [palette.light, palette.mid, palette.dark] as CFArray,
        locations: [0, 0.55, 1])
    {
        context.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
            options: [.drawsAfterEndLocation])
    }
    context.restoreGState()
    context.addPath(path)
    context.setStrokeColor(ink.copy(alpha: 0.9) ?? ink)
    context.setLineWidth(outline)
    context.strokePath()
}

func ellipse(_ center: CGPoint, _ width: CGFloat, _ height: CGFloat) -> CGPath {
    CGPath(
        ellipseIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
        transform: nil)
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    ellipse(center, radius * 2, radius * 2)
}

func octagon(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4 + .pi / 8
        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func stroked(_ from: CGPoint, _ to: CGPoint, width: CGFloat) -> CGPath {
    let line = CGMutablePath()
    line.move(to: from)
    line.addLine(to: to)
    return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

/// A thick curved band — a bow or a shield seen from above.
func arcBand(center: CGPoint, inner: CGFloat, outer: CGFloat, from start: CGFloat, to end: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
    path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
    path.closeSubpath()
    return path
}

func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

// MARK: - Figures

func drawBase(_ context: CGContext, _ palette: Palette, octagonal: Bool) {
    let origin = CGPoint.zero
    let base = octagonal ? octagon(origin, 9.6) : circle(origin, 8.8)
    fillMetal(context, base, Palette(light: palette.mid, mid: palette.dark, dark: palette.dark, rim: palette.rim))
    // The cast rim — the team material, and (with the base's outline) the only part of the figure
    // guaranteed to read against the sand (ART-DIRECTION §2).
    let rim = octagonal ? octagon(origin, 8.3) : circle(origin, 7.6)
    context.addPath(rim)
    context.setStrokeColor(palette.rim)
    context.setLineWidth(1.3)
    context.strokePath()
}

func drawSoldier(_ context: CGContext, _ palette: Palette, body: CGPoint, width: CGFloat = 13) {
    // Shoulders with a pauldron at each end, the head pushed forward past them. A head centred inside
    // a shoulder ellipse — same tone, concentric outlines — reads as an eye from above, not a soldier.
    fillMetal(context, ellipse(body, width, 5.6), palette)
    for side: CGFloat in [-1, 1] {
        fillMetal(
            context, circle(CGPoint(x: body.x + side * (width / 2 - 1.6), y: body.y + 0.3), 2.3), palette, outline: 0.8)
    }
    let head = CGPoint(x: body.x, y: body.y - 2.4)
    let helmet = Palette(light: palette.mid, mid: palette.dark, dark: palette.dark, rim: palette.rim)
    fillMetal(context, circle(head, 3.4), helmet, outline: 0.6)
    context.addPath(stroked(CGPoint(x: head.x, y: head.y - 3), CGPoint(x: head.x, y: head.y + 2.6), width: 1.2))
    context.setFillColor(palette.light)
    context.fillPath()
}

func drawSpearman(_ context: CGContext, _ palette: Palette, pose: String) {
    let lean: CGFloat = pose == "strike" ? -2 : 0
    let spearX: CGFloat = pose == "brace" ? 1.5 : 4
    let butt: CGFloat = pose == "brace" ? 5 : (pose == "strike" ? 4 : 9)
    let tip: CGFloat = pose == "base" ? -20 : -22
    fillMetal(context, circle(CGPoint(x: -5.8, y: -1 + lean), 3.6), palette)
    drawSoldier(context, palette, body: CGPoint(x: 0, y: 1.5 + lean), width: pose == "brace" ? 14 : 13)
    fillMetal(
        context, stroked(CGPoint(x: spearX, y: butt), CGPoint(x: spearX, y: tip + 3), width: 1.7), palette, outline: 0.8
    )
    fillMetal(
        context,
        polygon([
            CGPoint(x: spearX, y: tip - 1.5), CGPoint(x: spearX + 1.8, y: tip + 3),
            CGPoint(x: spearX - 1.8, y: tip + 3),
        ]), palette, outline: 0.8)
}

func drawArcher(_ context: CGContext, _ palette: Palette, pose: String) {
    // Quiver on the back, fletchings showing.
    fillMetal(
        context,
        polygon([CGPoint(x: -7.5, y: 3), CGPoint(x: -3.5, y: 2), CGPoint(x: -2, y: 11), CGPoint(x: -6, y: 11.8)]),
        palette)
    for offset: CGFloat in [-6, -4.6, -3.2] {
        context.addPath(circle(CGPoint(x: offset + 0.3, y: 2.6), 0.9))
    }
    context.setFillColor(rgb(0xD6D0C2, 0.9))
    context.fillPath()
    drawSoldier(context, palette, body: CGPoint(x: 0, y: 3), width: 11)
    // Bow: a wide "D" in front of the figure, reaching past the base — the archer's whole identity.
    let bowCenter = CGPoint(x: 0, y: 1)
    let bow = arcBand(center: bowCenter, inner: 10.4, outer: 12.6, from: degrees(208), to: degrees(332))
    fillMetal(context, bow, palette, outline: 0.9)
    let left = CGPoint(x: cos(degrees(208)) * 11.5, y: bowCenter.y + sin(degrees(208)) * 11.5)
    let right = CGPoint(x: cos(degrees(332)) * 11.5, y: bowCenter.y + sin(degrees(332)) * 11.5)
    let draw = CGPoint(x: 0, y: pose == "strike" ? 0.5 : -4.4)
    let string = CGMutablePath()
    string.addLines(between: [left, draw, right])
    context.addPath(string)
    context.setStrokeColor(rgb(0xD6D0C2, 0.85))
    context.setLineWidth(0.6)
    context.strokePath()
    fillMetal(context, stroked(draw, CGPoint(x: 0, y: -15.5), width: 1.2), palette, outline: 0.6)
}

func drawCavalry(_ context: CGContext, _ palette: Palette, pose: String) {
    let reach: CGFloat = pose == "strike" ? -2 : 0
    fillMetal(context, stroked(CGPoint(x: 0, y: 13), CGPoint(x: 0, y: 18.5), width: 2.6), palette, outline: 0.8)
    fillMetal(context, ellipse(CGPoint(x: 0, y: 3), 10, 21), palette)
    fillMetal(context, ellipse(CGPoint(x: 0, y: -10.5 + reach), 5.4, 10), palette)
    fillMetal(context, ellipse(CGPoint(x: 0, y: -15.5 + reach), 4.2, 4.6), palette)
    for side: CGFloat in [-1.6, 1.6] {
        fillMetal(context, ellipse(CGPoint(x: side, y: -7.2 + reach), 1.4, 2.6), palette, outline: 0.5)
    }
    drawSoldier(context, palette, body: CGPoint(x: 0, y: 2), width: 9)
    fillMetal(context, stroked(CGPoint(x: 4.8, y: 2), CGPoint(x: 6, y: -7), width: 1.3), palette, outline: 0.6)
}

func drawShieldBearer(_ context: CGContext, _ palette: Palette, pose: String) {
    let push: CGFloat = pose == "strike" ? -2.5 : 0
    let spread: CGFloat = pose == "brace" ? 16 : 0
    fillMetal(context, stroked(CGPoint(x: 5.5, y: 4), CGPoint(x: 7.5, y: -2), width: 1.3), palette, outline: 0.6)
    drawSoldier(context, palette, body: CGPoint(x: 0, y: 4), width: 13)
    let shield = arcBand(
        center: CGPoint(x: 0, y: 4 + push), inner: 8, outer: 13.2, from: degrees(200 - spread),
        to: degrees(340 + spread))
    fillMetal(context, shield, palette)
    fillMetal(context, circle(CGPoint(x: 0, y: -6.6 + push), 2.3), palette, outline: 0.7)
}

func drawFigure(_ context: CGContext, type: String, palette: Palette, pose: String) {
    switch type {
    case "mizrakci": drawSpearman(context, palette, pose: pose)
    case "okcu": drawArcher(context, palette, pose: pose)
    case "suvari": drawCavalry(context, palette, pose: pose)
    default: drawShieldBearer(context, palette, pose: pose)
    }
}

/// A miniature knocked over: the base seen edge-on at one end, the figure lying across the table,
/// dulled as if it had lost the lamp.
func drawFallen(_ context: CGContext, type: String, team: (name: String, palette: Palette, octagonalBase: Bool)) {
    let dull = Palette(light: team.palette.mid, mid: team.palette.dark, dark: team.palette.dark, rim: team.palette.mid)
    context.saveGState()
    context.translateBy(x: 0, y: 6)
    context.scaleBy(x: 1, y: 0.42)
    drawBase(context, dull, octagonal: team.octagonalBase)
    context.restoreGState()
    context.saveGState()
    context.translateBy(x: 0, y: -2)
    context.rotate(by: degrees(90))
    context.scaleBy(x: 0.85, y: 0.85)
    drawFigure(context, type: type, palette: dull, pose: "base")
    context.restoreGState()
}

// MARK: - Shadows and marks

func drawShadow(_ context: CGContext, type: String, fallen: Bool) {
    context.setFillColor(ink.copy(alpha: 0.55) ?? ink)
    context.setShadow(offset: .zero, blur: 3, color: ink.copy(alpha: 0.8))
    if fallen {
        context.addPath(ellipse(CGPoint(x: 0, y: 1), 30, 12))
    } else {
        context.addPath(circle(.zero, 10))
        switch type {
        case "mizrakci": context.addPath(stroked(CGPoint(x: 4, y: 0), CGPoint(x: 4, y: -21), width: 2.2))
        case "suvari": context.addPath(ellipse(CGPoint(x: 0, y: -1), 11, 34))
        case "kalkan":
            context.addPath(
                arcBand(center: CGPoint(x: 0, y: 4), inner: 8, outer: 13.6, from: degrees(200), to: degrees(340)))
        case "okcu":
            context.addPath(
                arcBand(center: CGPoint(x: 0, y: 1), inner: 10, outer: 13, from: degrees(208), to: degrees(332)))
        default: break
        }
    }
    context.fillPath()
}

func drawSelectionRing(_ context: CGContext) {
    context.addPath(circle(.zero, 13))
    context.setStrokeColor(ink.copy(alpha: 0.7) ?? ink)
    context.setLineWidth(3.2)
    context.strokePath()
    context.addPath(circle(.zero, 13))
    context.setStrokeColor(brass.rim)
    context.setLineWidth(1.6)
    context.strokePath()
}

// MARK: - Output

func render(_ draw: (CGContext) -> Void, scale: Int) -> CGImage? {
    let pixels = Int(canvasPoints) * scale
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Canvas points, origin at the centre, y down (so "forward" — up on screen — is negative y).
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: canvasPoints / 2, y: canvasPoints / 2)
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    draw(context)
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func writeImageSet(named name: String, in atlas: URL, _ draw: (CGContext) -> Void) throws {
    let folder = atlas.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var entries: [String] = []
    for scale in scales {
        guard let image = render(draw, scale: scale) else { throw CocoaError(.fileWriteUnknown) }
        let filename = "\(name)@\(scale)x.png"
        try writePNG(image, to: folder.appendingPathComponent(filename))
        entries.append(#"    { "filename" : "\#(filename)", "idiom" : "universal", "scale" : "\#(scale)x" }"#)
    }
    let contents =
        "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift placeholders.swift <path/to/Units.spriteatlas>\n".utf8))
    exit(64)
}
let atlas = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: atlas, withIntermediateDirectories: true)
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.appending("\n").write(
    to: atlas.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for type in unitTypes {
    for team in teams {
        for pose in poses {
            try writeImageSet(named: "\(type)-\(team.name)-\(pose)", in: atlas) { context in
                if pose == "fallen" {
                    drawFallen(context, type: type, team: team)
                } else {
                    drawBase(context, team.palette, octagonal: team.octagonalBase)
                    drawFigure(context, type: type, palette: team.palette, pose: pose)
                }
            }
        }
    }
    try writeImageSet(named: "shadow-\(type)", in: atlas) { drawShadow($0, type: type, fallen: false) }
    try writeImageSet(named: "shadow-\(type)-fallen", in: atlas) { drawShadow($0, type: type, fallen: true) }
}
try writeImageSet(named: "ring-selection", in: atlas) { drawSelectionRing($0) }
print("wrote placeholder unit art to \(atlas.path)")
