import SwiftUI
import UIKit

/// Visual language: white ground, black hairline detail, round sans type,
/// bright money with a holographic sheen.
enum Theme {

    // MARK: Ground & ink
    static let ground      = Color.white
    static let ink         = Color.black
    static let inkSoft     = Color.black.opacity(0.45)
    static let inkFaint    = Color.black.opacity(0.12)

    /// Money coming back to you. Dark enough to clear 3:1 on white at display
    /// sizes, bright enough to still read as the green of a hundred.
    static let credit      = Color(rgb: 0x00A651)

    static let uiGround    = UIColor.white
    static let uiInk       = UIColor.black

    /// Every line in the app is this thin.
    static let hairline: CGFloat = 1
    static let line: CGFloat     = 1.5

    static let radiusChip: CGFloat  = 100
    static let radiusCard: CGFloat  = 18

    // MARK: Type — Satoshi throughout

    /// The five Satoshi faces bundled with the app, by PostScript name.
    enum Face: String {
        case light   = "Satoshi-Light"
        case regular = "Satoshi-Regular"
        case medium  = "Satoshi-Medium"
        case bold    = "Satoshi-Bold"
        case black   = "Satoshi-Black"

        /// Nearest Satoshi face for a UIKit weight.
        static func matching(_ weight: UIFont.Weight) -> Face {
            switch weight {
            case .ultraLight, .thin, .light: .light
            case .regular:                   .regular
            case .medium, .semibold:         .medium
            case .heavy, .black:             .black
            default:                         .bold
            }
        }
    }

    static func display(_ size: CGFloat) -> Font { font(.bold, size) }
    static func title(_ size: CGFloat)   -> Font { font(.medium, size) }
    static func body(_ size: CGFloat)    -> Font { font(.regular, size) }
    static func label(_ size: CGFloat)   -> Font { font(.bold, size) }

    static func font(_ face: Face, _ size: CGFloat) -> Font {
        .custom(face.rawValue, size: size, relativeTo: .body)
    }

    static func uiFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont(name: Face.matching(weight).rawValue, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >>  8) & 0xFF) / 255,
            blue:  CGFloat( rgb        & 0xFF) / 255,
            alpha: 1
        )
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}

extension Color {
    init(rgb: UInt32) { self.init(UIColor(rgb: rgb)) }
}

/// A 1pt black hairline, used for every divider and outline in the chrome.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(height: Theme.hairline)
    }
}
