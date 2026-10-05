import SwiftUI
import UIKit

@main
struct CashStackApp: App {
    @StateObject private var wallet = WalletStore()

    init() {
        Self.applyChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(wallet)
                .preferredColorScheme(.light)
                .tint(Theme.ink)
        }
    }

    /// Sheets get UIKit navigation bars, so they need telling about the
    /// rounded type and the hairline rule.
    private static func applyChrome() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = Theme.uiGround
        bar.shadowColor = Theme.uiInk
        bar.titleTextAttributes = [
            .font: Theme.uiRounded(17, .semibold),
            .foregroundColor: Theme.uiInk
        ]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar

        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: Theme.uiRounded(16, .semibold), .foregroundColor: Theme.uiInk], for: .normal)
    }
}
