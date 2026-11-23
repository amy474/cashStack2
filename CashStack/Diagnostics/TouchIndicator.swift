#if DEBUG
import UIKit

/// Draws a soft circle under every finger, for screen recordings: the touches
/// a UI test synthesises are otherwise invisible. Debug builds only, and only
/// when launched with `-showTouches YES`.
///
/// A recogniser on the app's window watches every touch without ever
/// recognising, so it never gets in the way of the pile or the buttons; the
/// circles are drawn in a window of their own that can't be touched.
enum TouchIndicator {

    private static var overlay: UIWindow?

    static func installIfAsked() {
        guard UserDefaults.standard.bool(forKey: "showTouches"), overlay == nil else { return }
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
                  let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else {
                // Not on screen yet: try again shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { installIfAsked() }
                return
            }
            let overlay = UIWindow(windowScene: scene)
            overlay.windowLevel = .alert + 10
            overlay.isUserInteractionEnabled = false
            overlay.backgroundColor = .clear
            overlay.rootViewController = UIViewController()
            overlay.rootViewController?.view.backgroundColor = .clear
            overlay.isHidden = false
            Self.overlay = overlay

            let watcher = Watcher(canvas: overlay)
            window.addGestureRecognizer(watcher)
        }
    }

    private final class Watcher: UIGestureRecognizer {
        private let canvas: UIView
        private var dots: [ObjectIdentifier: UIView] = [:]

        init(canvas: UIView) {
            self.canvas = canvas
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches {
                let dot = Self.makeDot()
                dot.center = touch.location(in: canvas)
                dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                canvas.addSubview(dot)
                UIView.animate(withDuration: 0.12) { dot.transform = .identity }
                dots[ObjectIdentifier(touch)] = dot
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches {
                dots[ObjectIdentifier(touch)]?.center = touch.location(in: canvas)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            for touch in touches {
                guard let dot = dots.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
                UIView.animate(withDuration: 0.25, animations: {
                    dot.alpha = 0
                    dot.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
                }, completion: { _ in dot.removeFromSuperview() })
            }
            // Every finger is up: step aside without ever having recognised.
            if dots.isEmpty { state = .failed }
        }

        // Never stopped by a button or the pile recognising first, so the
        // circle follows the finger all the way to lift-off…
        override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool { false }
        override func canPrevent(_ prevented: UIGestureRecognizer) -> Bool { false }

        // …and if UIKit resets it anyway, nothing is left on screen.
        override func reset() {
            super.reset()
            for dot in dots.values {
                UIView.animate(withDuration: 0.25, animations: { dot.alpha = 0 },
                               completion: { _ in dot.removeFromSuperview() })
            }
            dots.removeAll()
        }

        private static func makeDot() -> UIView {
            let size: CGFloat = 46
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            dot.isUserInteractionEnabled = false
            dot.layer.cornerRadius = size / 2
            dot.backgroundColor = UIColor(white: 0.55, alpha: 0.38)
            dot.layer.borderColor = UIColor(white: 1, alpha: 0.85).cgColor
            dot.layer.borderWidth = 2
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.18
            dot.layer.shadowRadius = 6
            dot.layer.shadowOffset = .zero
            return dot
        }
    }
}
#endif
