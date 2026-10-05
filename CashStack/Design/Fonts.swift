import CoreText
import UIKit

/// Satoshi ships inside the app bundle and is registered at launch, so the
/// faces are available to SwiftUI, to UIKit chrome, and to the CoreGraphics
/// code that draws the notes and coins.
enum Fonts {

    private static let faces: [Theme.Face] = [.light, .regular, .medium, .bold, .black]

    static func register() {
        let urls = faces.compactMap { face in
            Bundle.main.url(forResource: face.rawValue, withExtension: "otf")
        }

        guard !urls.isEmpty else {
            assertionFailure("Satoshi is missing from the bundle — check Resources/Fonts")
            return
        }

        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, done in
            // A face that is already registered is not a problem worth shouting about.
            if done, CFArrayGetCount(errors) > 0 {
                print("Font registration finished with \(CFArrayGetCount(errors)) notice(s)")
            }
            return true
        }
    }

    /// True once every face resolves — used by the tests to catch a missing file.
    static var isReady: Bool {
        faces.allSatisfy { UIFont(name: $0.rawValue, size: 12) != nil }
    }
}
