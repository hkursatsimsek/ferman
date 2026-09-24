// The launch screen's wordmark (G15): "FERMAN" in the bundled Archivo SemiBold, spaced like the home
// screen's wordmark, paper-coloured on transparency. A launch screen can't use the app's fonts, so the
// word ships as an image. macOS only, no dependencies; the same input writes the same bytes.
//
//     swift Tools/launch/wordmark.swift App/Ferman/Fonts/Archivo-SemiBold.ttf \
//         App/Ferman/Assets.xcassets/LaunchWordmark.imageset

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let word = "FERMAN"
let pointSize: CGFloat = 34
/// `HomeView`'s wordmark tracking.
let tracking: CGFloat = 9
let paper = CGColor(srgbRed: 0xD6 / 255, green: 0xD0 / 255, blue: 0xC2 / 255, alpha: 1)

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift wordmark.swift <font.ttf> <LaunchWordmark.imageset>\n".utf8))
    exit(64)
}
let fontURL = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = URL(fileURLWithPath: CommandLine.arguments[2])

guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
    let descriptor = descriptors.first
else {
    FileHandle.standardError.write(Data("could not read \(fontURL.path)\n".utf8))
    exit(1)
}
let font = CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): paper,
    NSAttributedString.Key(kCTKernAttributeName as String): tracking,
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: attributes))
var ascent: CGFloat = 0
var descent: CGFloat = 0
var leading: CGFloat = 0
// The last letter's tracking is trailing space, not ink.
let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading)) - tracking
let size = CGSize(width: ceil(width), height: ceil(ascent + descent))

func render(scale: Int) -> CGImage? {
    guard
        let context = CGContext(
            data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setShouldAntialias(true)
    context.textPosition = CGPoint(x: 0, y: descent)
    CTLineDraw(line, context)
    return context.makeImage()
}

try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var entries: [String] = []
for scale in [2, 3] {
    let name = "LaunchWordmark@\(scale)x.png"
    guard let image = render(scale: scale),
        let destination = CGImageDestinationCreateWithURL(
            folder.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    entries.append(#"    { "filename" : "\#(name)", "idiom" : "universal", "scale" : "\#(scale)x" }"#)
}
let contents =
    "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(folder.path) (\(Int(size.width))×\(Int(size.height)) pt)")
