import CoreMotion
import CoreGraphics
import Foundation

/// Reads the handset's gravity vector so the cash falls the way the phone is
/// held, and reports roll so the holographic foil catches the light.
///
/// Updates are delivered straight to the scene by closure — deliberately not
/// through `@Published`, which would re-render SwiftUI sixty times a second.
final class MotionManager {

    var onGravity: ((CGVector) -> Void)?
    var onRoll: ((Double) -> Void)?
    var onShake: (() -> Void)?

    private(set) var isLive = false

    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            isLive = true

            // CoreMotion and SpriteKit agree on y-up in portrait.
            onGravity?(CGVector(dx: data.gravity.x, dy: data.gravity.y))
            onRoll?(data.attitude.roll)

            let jolt = sqrt(data.userAcceleration.x * data.userAcceleration.x
                          + data.userAcceleration.y * data.userAcceleration.y
                          + data.userAcceleration.z * data.userAcceleration.z)
            if jolt > 1.5, Date().timeIntervalSince(lastShake) > 0.7 {
                lastShake = Date()
                onShake?()
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isLive = false
    }
}
