import SwiftUI
import SpriteKit

/// Hosts the physics pile.
struct CashSceneView: View {
    let scene: CashScene

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .background(Theme.ground)
    }
}
