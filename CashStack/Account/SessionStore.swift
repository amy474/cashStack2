import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

/// Who is signed in, and whether the app is locked. The refresh token lives
/// in the Keychain (behind Face ID when the lock is on) and in memory only
/// while the app is unlocked; locking throws the in-memory copy away.
@MainActor
final class SessionStore: ObservableObject {

    enum State: Equatable {
        case signedOut
        case locked
        case signedIn
    }

    @Published private(set) var state: State
    @Published private(set) var lockEnabled: Bool
    @Published var errorMessage: String?

    let api: APIClient
    /// The nonce for the Sign in with Apple request in progress. Apple sees
    /// its hash; the server checks the token against this original.
    private var pendingNonce: String?
    private var backgroundedAt: Date?

    /// How long the app can sit in the background before it locks again.
    static let relockAfter: TimeInterval = 60

    init(api: APIClient = APIClient()) {
        self.api = api
        // The Keychain outlives a deleted app; UserDefaults doesn't. A fresh
        // install must not quietly pick up the last owner's session.
        if !UserDefaults.standard.bool(forKey: Preference.installed) {
            Keychain.delete()
            UserDefaults.standard.set(true, forKey: Preference.installed)
        }
        let locks = UserDefaults.standard.bool(forKey: Preference.lockWithFaceID)
        lockEnabled = locks

        if !Keychain.hasSession {
            state = .signedOut
        } else if locks {
            state = .locked
        } else if let token = Keychain.read() {
            state = .signedIn
            Task { await api.restore(refreshToken: token) }
        } else {
            state = .signedOut
        }

        Task {
            await api.configure(
                // Written straight away, not hopped to the main actor: the old
                // token is already spent, and losing the new one would sign
                // them out on next launch.
                onRotate: { token in
                    try? Keychain.save(token, requireUserPresence: UserDefaults.standard.bool(forKey: Preference.lockWithFaceID))
                },
                onSignedOut: {
                    Task { @MainActor [weak self] in self?.endSession(message: "You've been signed out. Sign in again to continue.") }
                })
        }
    }

    // MARK: Sign in with Apple

    /// Fill in the Apple request: email (Basiq needs one to set up the bank
    /// connection) and the hash of a fresh nonce.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                Log.session.error("Sign in with Apple failed: \((error as NSError).code, privacy: .public)")
                errorMessage = "Sign in with Apple didn't go through. Try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingNonce else {
                errorMessage = "Sign in with Apple didn't go through. Try again."
                return
            }
            do {
                _ = try await api.signInWithApple(
                    identityToken: identityToken,
                    rawNonce: nonce,
                    authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                    device: UIDevice.current.model)
                pendingNonce = nil
                state = .signedIn
                Log.session.notice("Signed in")
            } catch {
                Log.session.error("Server refused the Apple sign-in: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func signInForDevelopment() async {
        errorMessage = nil
        do {
            _ = try await api.signInForDevelopment()
            state = .signedIn
        } catch {
            errorMessage = "Development sign-in failed. Is the server running with DEV_LOGIN=1? (\(error.localizedDescription))"
        }
    }

    // MARK: The lock

    /// Turn the Face ID lock on or off. Turning it on rewrites the stored
    /// token behind Face ID; off rewrites it without.
    func setLock(_ enabled: Bool) async {
        if enabled {
            guard DeviceLock.isAvailable,
                  await DeviceLock.authenticate(reason: "Lock CashStack with \(DeviceLock.name)") != nil else { return }
        }
        UserDefaults.standard.set(true, forKey: Preference.lockDecided)
        guard let token = await api.currentRefreshToken else { return }
        do {
            try Keychain.save(token, requireUserPresence: enabled)
            UserDefaults.standard.set(enabled, forKey: Preference.lockWithFaceID)
            lockEnabled = enabled
        } catch {
            errorMessage = "This iPhone needs a passcode before CashStack can lock."
        }
    }

    func unlock() async {
        guard state == .locked else { return }
        guard let context = await DeviceLock.authenticate(reason: "Unlock your wallet") else { return }
        guard let token = Keychain.read(using: context) else {
            // The item is gone — the passcode was removed, which wipes it.
            endSession(message: "Sign in again to unlock CashStack.")
            return
        }
        await api.restore(refreshToken: token)
        state = .signedIn
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            defer { backgroundedAt = nil }
            guard state == .signedIn, lockEnabled, let since = backgroundedAt,
                  Date().timeIntervalSince(since) >= Self.relockAfter else { return }
            state = .locked
            Task { await api.forget() }
        default:
            break
        }
    }

    // MARK: Leaving

    func signOut() async {
        await api.signOut()
        endSession(message: nil)
    }

    /// Delete the CashStack account, the bank connections and everything
    /// Basiq holds. Throws if the server couldn't do it, so nothing is half-gone.
    func deleteAccount() async throws {
        try await api.delete("v1/me")
        await api.forget()
        endSession(message: nil)
    }

    private func endSession(message: String?) {
        Log.session.notice("Session ended\(message == nil ? "" : " by the server", privacy: .public)")
        Keychain.delete()
        Preference.clearAccount()
        lockEnabled = false
        state = .signedOut
        errorMessage = message
        Task { await api.forget() }
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
