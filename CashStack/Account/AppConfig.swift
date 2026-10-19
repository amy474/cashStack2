import Foundation

/// Where the app's server is, and which wallet it opens into.
enum AppConfig {

    /// The CashStack API: the Mac's own server in Debug builds, Fly in Release
    /// (`CASHSTACK_API_URL` in the build settings). A Debug build can be
    /// pointed elsewhere with `-apiBaseURL https://…`.
    static var apiBaseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #endif
        let configured = Bundle.main.object(forInfoDictionaryKey: "CashStackAPIURL") as? String
        return configured.flatMap(URL.init(string:)) ?? URL(string: "https://cashstack-api.fly.dev")!
    }

    /// The public page that explains how to stop sharing bank data.
    static var dataSharingURL: URL { apiBaseURL.appending(path: "data-sharing") }

    /// Development sign-in skips Apple. It only exists in Debug builds, and
    /// the server only honours it when started with DEV_LOGIN=1.
    static var offersDevelopmentSignIn: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Things the app remembers between launches. None of it is secret — the
/// session lives in the Keychain — and all of it is cleared on sign-out.
enum Preference {
    /// The made-up banks instead of real ones. The UI tests launch with `-demo YES`.
    static let demo = "demo"
    /// Whether reading the session needs Face ID (or the passcode).
    static let lockWithFaceID = "lockWithFaceID"
    /// The Face ID question has been answered, one way or the other.
    static let lockDecided = "lockDecided"
    /// Onboarding is finished; open straight into the wallet.
    static let onboarded = "onboarded"
    /// The real account whose money fills the pile.
    static let selectedAccountID = "selectedAccountID"
    /// Set on first launch, so a reinstall can be told apart from a relaunch.
    static let installed = "installed"

    static func clearAccount() {
        for key in [lockWithFaceID, lockDecided, onboarded, selectedAccountID] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
