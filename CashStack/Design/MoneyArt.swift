import UIKit
import SpriteKit

/// Draws the notes and coins. Everything is generated at runtime so there are
/// no image assets to ship and the art stays crisp at any size.
enum MoneyArt {

    private static var imageCache: [Int: UIImage] = [:]
    private static var textureCache: [Int: SKTexture] = [:]

    static func image(for denomination: Denomination) -> UIImage {
        if let cached = imageCache[denomination.minor] { return cached }
        let image = denomination.kind == .note ? drawNote(denomination) : drawCoin(denomination)
        imageCache[denomination.minor] = image
        return image
    }

    static func texture(for denomination: Denomination) -> SKTexture {
        if let cached = textureCache[denomination.minor] { return cached }
        let texture = SKTexture(image: image(for: denomination))
        texture.filteringMode = .linear
        textureCache[denomination.minor] = texture
        return texture
    }

    // MARK: - Notes

    private static func drawNote(_ d: Denomination) -> UIImage {
        let size = d.size
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 3

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let corner: CGFloat = 9
            let body = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let shape = UIBezierPath(roundedRect: body, cornerRadius: corner)

            // Bright ground, with a soft two-tone wash so the foil has something to sit on.
            cg.saveGState()
            shape.addClip()
            let light = d.tint.mixed(with: .white, 0.30)
            let deep  = d.tint.mixed(with: UIColor(rgb: 0x101010), 0.10)
            drawLinearGradient(cg, from: light, to: deep,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: size.width, y: size.height))

            // Hairline guilloche: thin repeated rules, the fintech-engraving nod.
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
            cg.setLineWidth(0.6)
            var y: CGFloat = 6
            while y < size.height {
                cg.move(to: CGPoint(x: 2, y: y))
                cg.addLine(to: CGPoint(x: size.width - 2, y: y - 6))
                y += 5
            }
            cg.strokePath()

            // Foil panel on the right — where the holographic shine concentrates.
            let foil = CGRect(x: size.width - 30, y: 8, width: 20, height: size.height - 16)
            let foilPath = UIBezierPath(roundedRect: foil, cornerRadius: 5)
            UIColor.white.withAlphaComponent(0.55).setFill()
            foilPath.fill()
            UIColor.black.setStroke()
            foilPath.lineWidth = 1
            foilPath.stroke()
            cg.restoreGState()

            // Inner hairline frame.
            let frame = UIBezierPath(roundedRect: body.insetBy(dx: 4.5, dy: 4.5), cornerRadius: corner - 3)
            UIColor.black.withAlphaComponent(0.55).setStroke()
            frame.lineWidth = Theme.hairline
            frame.stroke()

            // Outer hairline.
            UIColor.black.setStroke()
            shape.lineWidth = Theme.line
            shape.stroke()

            // Value.
            let faceFont = Theme.uiFont(size.height * 0.46, .bold)
            let symbolFont = Theme.uiFont(size.height * 0.26, .bold)
            let faceWidth = d.face.size(withAttributes: [.font: faceFont]).width
            let symbolWidth = Money.symbol.size(withAttributes: [.font: symbolFont]).width
            let originX: CGFloat = 13
            let baseY = size.height * 0.5 - faceFont.lineHeight * 0.5

            Money.symbol.draw(at: CGPoint(x: originX, y: baseY + faceFont.lineHeight * 0.12),
                              withAttributes: [.font: symbolFont, .foregroundColor: UIColor.black])
            d.face.draw(at: CGPoint(x: originX + symbolWidth + 1, y: baseY),
                        withAttributes: [.font: faceFont, .foregroundColor: UIColor.black])

            // Wordmark, letterspaced small caps.
            let mark = NSAttributedString(string: "CASHSTACK", attributes: [
                .font: Theme.uiFont(6, .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.6),
                .kern: 1.6
            ])
            mark.draw(at: CGPoint(x: originX, y: size.height - 16))

            // Repeat of the value, small, bottom right of the printed area.
            let small = NSAttributedString(string: d.label, attributes: [
                .font: Theme.uiFont(9, .bold),
                .foregroundColor: UIColor.black
            ])
            small.draw(at: CGPoint(x: originX + faceWidth + symbolWidth + 8, y: size.height - 18))
        }
    }

    // MARK: - Coins

    private static func drawCoin(_ d: Denomination) -> UIImage {
        let diameter = d.size.width
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 3

        return UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
            let disc = UIBezierPath(ovalIn: rect)

            cg.saveGState()
            disc.addClip()
            drawLinearGradient(cg,
                               from: d.tint.mixed(with: .white, 0.38),
                               to: d.tint.mixed(with: UIColor(rgb: 0x101010), 0.14),
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: diameter, y: diameter))

            // Milled edge: short radial ticks.
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            cg.setLineWidth(0.8)
            let centre = CGPoint(x: diameter / 2, y: diameter / 2)
            let outer = diameter / 2 - 1.5
            for i in 0..<44 {
                let angle = CGFloat(i) / 44 * .pi * 2
                cg.move(to: CGPoint(x: centre.x + cos(angle) * (outer - 3.2),
                                    y: centre.y + sin(angle) * (outer - 3.2)))
                cg.addLine(to: CGPoint(x: centre.x + cos(angle) * outer,
                                       y: centre.y + sin(angle) * outer))
            }
            cg.strokePath()
            cg.restoreGState()

            // Inner hairline ring.
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5))
            UIColor.black.withAlphaComponent(0.55).setStroke()
            ring.lineWidth = Theme.hairline
            ring.stroke()

            // Outer hairline.
            UIColor.black.setStroke()
            disc.lineWidth = Theme.line
            disc.stroke()

            // Face value, centred.
            let font = Theme.uiFont(diameter * (d.face.count > 2 ? 0.30 : 0.36), .bold)
            let text = NSAttributedString(string: d.face, attributes: [
                .font: font, .foregroundColor: UIColor.black
            ])
            let bounds = text.size()
            text.draw(at: CGPoint(x: (diameter - bounds.width) / 2,
                                  y: (diameter - bounds.height) / 2))

        }
    }

    // MARK: - Helpers

    private static func drawLinearGradient(_ cg: CGContext, from: UIColor, to: UIColor,
                                           start: CGPoint, end: CGPoint) {
        let colors = [from.cgColor, to.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
    }
}
