import Foundation
import LocalAuthentication
import Security

/// The refresh token is the one long-lived secret on the phone, and the
/// Keychain is the only place it is written. With the lock on, the item can
/// only be read after Face ID (or the passcode) — enforced by the Secure
/// Enclave, not by a screen drawn over the app. It never leaves this device:
/// no iCloud Keychain, no backups.
enum Keychain {

    private static let service = "com.bokscot.cashstack.session"
    private static let account = "refresh-token"

    enum Failure: Error {
        case unavailable(OSStatus)
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Replace the stored token. Deleting first means a protected item never
    /// has to be authenticated just to be overwritten.
    static func save(_ token: String, requireUserPresence: Bool) throws {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        if requireUserPresence {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
                throw Failure.unavailable(errSecParam)
            }
            item[kSecAttrAccessControl as String] = access
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.unavailable(status) }
    }

    /// Read the token. A protected item needs `context` to have been through
    /// Face ID already; without one, a protected read fails rather than prompting.
    static func read(using context: LAContext? = nil) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let ctx = context ?? {
            let silent = LAContext()
            silent.interactionNotAllowed = true
            return silent
        }()
        query[kSecUseAuthenticationContext as String] = ctx
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether there is a session on this phone, without asking for Face ID.
    static var hasSession: Bool {
        var query = base
        let silent = LAContext()
        silent.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = silent
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // A protected item answers "interaction not allowed" — it is there.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

/// Face ID, Touch ID or the passcode — whatever the phone has.
enum DeviceLock {

    /// Whether this phone can lock the app at all (it has a passcode).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID", "Touch ID" or "your passcode", for buttons and copy.
    static var name: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "your passcode"
        }
    }

    /// Ask the owner to prove it's them. The returned context has been
    /// evaluated, so a Keychain read with it won't prompt a second time.
    static func authenticate(reason: String) async -> LAContext? {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { return nil }
            return context
        } catch {
            return nil
        }
    }
}
