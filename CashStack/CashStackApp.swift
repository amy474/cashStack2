import SwiftUI
import UIKit

@main
struct CashStackApp: App {

    init() {
        Fonts.register()
        Self.applyChrome()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
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
            .font: Theme.uiFont(17, .semibold),
            .foregroundColor: Theme.uiInk
        ]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar

        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: Theme.uiFont(16, .semibold), .foregroundColor: Theme.uiInk], for: .normal)
    }
}

/// Which wallet to show: the demo's pretend banks, or — once signed in,
/// unlocked and onboarded — the person's real ones.
struct AppRoot: View {
    @StateObject private var session = SessionStore()
    @AppStorage(Preference.demo) private var demo = false
    @AppStorage(Preference.onboarded) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if demo {
                DemoWallet()
            } else {
                switch session.state {
                case .signedOut:
                    OnboardingFlow(signedIn: false)
                case .locked:
                    LockView()
                case .signedIn:
                    if onboarded {
                        LiveWallet(api: session.api)
                    } else {
                        OnboardingFlow(signedIn: true)
                    }
                }
            }
            if !demo && session.state == .signedIn && scenePhase != .active {
                PrivacyCover()
            }
        }
        .environmentObject(session)
        .onChange(of: scenePhase) { _, phase in session.scenePhaseChanged(phase) }
    }
}

private struct DemoWallet: View {
    @StateObject private var wallet = WalletStore()
    var body: some View {
        RootView().environmentObject(wallet)
    }
}

private struct LiveWallet: View {
    @StateObject private var wallet: WalletStore
    @Environment(\.scenePhase) private var scenePhase

    init(api: APIClient) {
        _wallet = StateObject(wrappedValue: WalletStore(sources: [LiveBankDataSource(api: api)], isLive: true))
    }

    var body: some View {
        RootView()
            .environmentObject(wallet)
            .onChange(of: scenePhase) { _, phase in
                // Coming back after a while: fetch what the bank says now.
                guard phase == .active, wallet.phase == .ready,
                      Date().timeIntervalSince(wallet.lastRefreshed ?? .distantPast) > 5 * 60 else { return }
                Task { await wallet.refreshQuietly() }
            }
    }
}
