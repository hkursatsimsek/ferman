import SpriteKit
import UIKit

/// Small battle effects drawn once with Core Graphics — simple enough shapes that they don't need the
/// figure pipeline (`Tools/figures/`), and generated rather than shipped as images.
enum EffectTextures {
    /// The rule spark (brief §3.2): white streaks, tinted spark cyan by the sprite, added onto the table.
    static let spark: SKTexture = texture(size: 40) { context, size in
        let center = CGPoint(x: size / 2, y: size / 2)
        if let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1])
        {
            context.drawRadialGradient(
                glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.28, options: [])
        }
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineCap(.round)
        for ray in 0..<8 {
            let angle = CGFloat(ray) / 8 * 2 * .pi + .pi / 8
            let inner = size * (ray.isMultiple(of: 2) ? 0.16 : 0.2)
            let outer = size * (ray.isMultiple(of: 2) ? 0.48 : 0.36)
            context.setLineWidth(ray.isMultiple(of: 2) ? 1.6 : 1.1)
            context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.strokePath()
        }
    }

    /// An order's number, stamped like a small seal over the figure that just took it up (ART-DIRECTION §4).
    static func seal(ruleIndex: Int) -> SKTexture {
        let index = min(max(ruleIndex, 0), sealTextures.count - 1)
        return sealTextures[index]
    }

    private static let sealTextures: [SKTexture] = (1...12).map { number in
        texture(size: 20) { context, size in
            let disc = CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)
            context.setFillColor(UIColor(red: 0x0F / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 0.85).cgColor)
            context.fillEllipse(in: disc)
            context.setStrokeColor(UIColor(red: 0x6F / 255, green: 0xE3 / 255, blue: 0xF5 / 255, alpha: 1).cgColor)
            context.setLineWidth(1.4)
            context.strokeEllipse(in: disc.insetBy(dx: 0.7, dy: 0.7))
            let text = "\(number)" as NSString
            let font = UIFont(name: "ArchivoNarrow-SemiBold", size: 12) ?? .systemFont(ofSize: 12, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0xD6 / 255, green: 0xD0 / 255, blue: 0xC2 / 255, alpha: 1),
            ]
            let textSize = text.size(withAttributes: attributes)
            UIGraphicsPushContext(context)
            text.draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
            UIGraphicsPopContext()
        }
    }

    /// An arrow, pointing up like the figures (+Y), shaft of raw wood-grey with a pale fletching.
    static let arrow: SKTexture = texture(width: 4, height: 16) { context, _ in
        context.setFillColor(UIColor(red: 0x2A / 255, green: 0x26 / 255, blue: 0x22 / 255, alpha: 1).cgColor)
        context.fill(CGRect(x: 1.5, y: 3, width: 1, height: 11))
        context.move(to: CGPoint(x: 2, y: 0))
        context.addLine(to: CGPoint(x: 3.6, y: 3.4))
        context.addLine(to: CGPoint(x: 0.4, y: 3.4))
        context.closePath()
        context.fillPath()
        context.setFillColor(UIColor(red: 0xD6 / 255, green: 0xD0 / 255, blue: 0xC2 / 255, alpha: 1).cgColor)
        context.fill(CGRect(x: 0.4, y: 12.5, width: 3.2, height: 3))
    }

    static let arrowShadow: SKTexture = texture(width: 4, height: 16) { context, _ in
        context.setFillColor(UIColor(red: 0x0F / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 0.35).cgColor)
        context.fill(CGRect(x: 1.2, y: 1, width: 1.6, height: 14))
    }

    // MARK: -

    private static func texture(size: CGFloat, draw: (CGContext, CGFloat) -> Void) -> SKTexture {
        texture(width: size, height: size) { context, _ in draw(context, size) }
    }

    /// Drawn with UIKit's top-left origin; SpriteKit shows it upright, so "top" of the image is +Y.
    private static func texture(width: CGFloat, height: CGFloat, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
            draw($0.cgContext, CGSize(width: width, height: height))
        }
        return SKTexture(image: image)
    }
}
