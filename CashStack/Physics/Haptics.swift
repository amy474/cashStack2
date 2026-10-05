import UIKit

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare(); medium.prepare(); rigid.prepare()
    }

    static func tap()     { light.impactOccurred(intensity: 0.7) }
    static func grab()    { medium.impactOccurred(intensity: 0.9) }
    static func arm()     { rigid.impactOccurred(intensity: 0.6) }
    static func success() { notice.notificationOccurred(.success) }
}
