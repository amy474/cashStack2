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
        // Every detail is a fraction of the note's height, so the design holds
        // together whatever size the money is drawn at.
        let h = size.height
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 3

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let corner = h * 0.128
            let body = CGRect(origin: .zero, size: size).insetBy(dx: h * 0.014, dy: h * 0.014)
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
            let step = h * 0.071
            var y = h * 0.086
            while y < size.height {
                cg.move(to: CGPoint(x: 2, y: y))
                cg.addLine(to: CGPoint(x: size.width - 2, y: y - h * 0.086))
                y += step
            }
            cg.strokePath()

            // Foil panel on the right — where the holographic shine concentrates.
            let foil = CGRect(x: size.width - h * 0.43, y: h * 0.114,
                              width: h * 0.286, height: size.height - h * 0.229)
            let foilPath = UIBezierPath(roundedRect: foil, cornerRadius: h * 0.071)
            UIColor.white.withAlphaComponent(0.55).setFill()
            foilPath.fill()
            UIColor.black.setStroke()
            foilPath.lineWidth = Theme.hairline
            foilPath.stroke()
            cg.restoreGState()

            // Inner hairline frame.
            let frame = UIBezierPath(roundedRect: body.insetBy(dx: h * 0.064, dy: h * 0.064),
                                     cornerRadius: corner - h * 0.043)
            UIColor.black.withAlphaComponent(0.55).setStroke()
            frame.lineWidth = Theme.hairline
            frame.stroke()

            // Outer hairline.
            UIColor.black.setStroke()
            shape.lineWidth = Theme.line
            shape.stroke()

            // Value.
            let faceFont = Theme.uiFont(h * 0.46, .bold)
            let symbolFont = Theme.uiFont(h * 0.26, .bold)
            let faceWidth = d.face.size(withAttributes: [.font: faceFont]).width
            let symbolWidth = Money.symbol.size(withAttributes: [.font: symbolFont]).width
            let originX = h * 0.186
            let baseY = size.height * 0.5 - faceFont.lineHeight * 0.5

            Money.symbol.draw(at: CGPoint(x: originX, y: baseY + faceFont.lineHeight * 0.12),
                              withAttributes: [.font: symbolFont, .foregroundColor: UIColor.black])
            d.face.draw(at: CGPoint(x: originX + symbolWidth + 1, y: baseY),
                        withAttributes: [.font: faceFont, .foregroundColor: UIColor.black])

            // Wordmark, letterspaced small caps.
            let mark = NSAttributedString(string: "CASHSTACK", attributes: [
                .font: Theme.uiFont(h * 0.086, .medium),
                .foregroundColor: UIColor.black.withAlphaComponent(0.6),
                .kern: h * 0.023
            ])
            mark.draw(at: CGPoint(x: originX, y: size.height - h * 0.229))

            // Repeat of the value, small, bottom right of the printed area.
            let small = NSAttributedString(string: d.label, attributes: [
                .font: Theme.uiFont(h * 0.129, .bold),
                .foregroundColor: UIColor.black
            ])
            small.draw(at: CGPoint(x: originX + faceWidth + symbolWidth + h * 0.114,
                                   y: size.height - h * 0.257))
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
            let edge = diameter * 0.026
            let rect = CGRect(x: edge, y: edge, width: diameter - edge * 2, height: diameter - edge * 2)
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
            let outer = diameter / 2 - diameter * 0.039
            let tick = diameter * 0.084
            for i in 0..<44 {
                let angle = CGFloat(i) / 44 * .pi * 2
                cg.move(to: CGPoint(x: centre.x + cos(angle) * (outer - tick),
                                    y: centre.y + sin(angle) * (outer - tick)))
                cg.addLine(to: CGPoint(x: centre.x + cos(angle) * outer,
                                       y: centre.y + sin(angle) * outer))
            }
            cg.strokePath()
            cg.restoreGState()

            // Inner hairline ring.
            let inset = diameter * 0.132
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
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
