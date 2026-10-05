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

    static let uiGround    = UIColor.white
    static let uiInk       = UIColor.black

    /// Every line in the app is this thin.
    static let hairline: CGFloat = 1
    static let line: CGFloat     = 1.5

    static let radiusChip: CGFloat  = 100
    static let radiusCard: CGFloat  = 18

    // MARK: Type — rounded sans, always
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold,     design: .rounded) }
    static func title(_ size: CGFloat)   -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat)    -> Font { .system(size: size, weight: .medium,   design: .rounded) }
    static func mono(_ size: CGFloat)    -> Font { .system(size: size, weight: .semibold, design: .rounded) }

    static func uiRounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
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
