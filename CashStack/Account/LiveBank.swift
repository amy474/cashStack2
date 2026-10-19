import AuthenticationServices
import SwiftUI

/// Real banks, through the CashStack API and Basiq. Read-only: the Consumer
/// Data Right lets CashStack see balances, not move money, so paying at the
/// till and the jars are practice here — `debit` and `credit` change nothing
/// at the bank, and the next refresh puts the real balance back.
final class LiveBankDataSource: BankDataSource {

    let institution = Institution(id: "live", name: "Your bank", mark: "•", tint: Theme.ink)
    let movesMoney = false
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Consent happens in the onboarding and accounts screens, not here.
    func connect() async throws {}

    func accounts() async throws -> [LinkedAccount] {
        let response: AccountsResponse = try await api.get("v1/accounts")
        return response.accounts.map(LinkedAccount.init)
    }

    func refresh() async throws -> [LinkedAccount] {
        let response: AccountsResponse = try await api.post("v1/accounts/refresh")
        return response.accounts.map(LinkedAccount.init)
    }

    func debit(accountID: String, minor: Int) async throws {}
    func credit(accountID: String, minor: Int) async throws {}
}

extension LinkedAccount {
    init(_ account: APIAccount) {
        self.init(id: account.id,
                  institution: Institution(account.institution),
                  nickname: account.name,
                  maskedNumber: account.maskedNumber,
                  availableMinor: max(0, account.availableMinor),
                  lastUpdated: account.lastUpdated)
    }
}

extension Institution {
    /// A real bank, drawn the same way as the demo ones: its initial in a
    /// hairline circle, filled with the bank's own colour when Basiq has one.
    init(_ institution: APIInstitution) {
        self.init(id: institution.id,
                  name: institution.name,
                  mark: String(institution.name.prefix(1)).uppercased(),
                  tint: institution.color.flatMap(Color.init(hex:)) ?? Institution.fallbackTint(for: institution.id))
    }

    private static let palette: [UInt32] = [0x7A3BFF, 0xFF2E93, 0x00C2FF, 0x16DE7F, 0xFFB800, 0xFF5A1F]

    static func fallbackTint(for id: String) -> Color {
        let index = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF } % palette.count
        return Color(rgb: palette[index])
    }
}

extension Color {
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb: value)
    }
}

// MARK: - Connecting a bank

/// One trip through Basiq's consent screens: ask the server for a consent
/// link, open it in a private system web sheet, catch the redirect back to
/// cashstack://, then wait for the bank's accounts to arrive.
struct BankLink {

    enum Outcome: Equatable {
        case connected([LinkedAccount])
        /// The sheet was closed before finishing. Not an error.
        case cancelled
        case failed(String)
    }

    let api: APIClient

    func run(_ action: String = "connect",
             with web: WebAuthenticationSession) async -> Outcome {
        struct Start: Encodable { let action: String }
        do {
            let session: ConsentSession = try await api.post("v1/consent/sessions", body: Start(action: action))
            let callback: URL
            do {
                // Ephemeral: the bank's pages share no cookies with Safari.
                callback = try await web.authenticate(using: session.url,
                                                      callbackURLScheme: session.callbackScheme,
                                                      preferredBrowserSession: .ephemeral)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return .cancelled
            }
            let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let id = query.first(where: { $0.name == "session" })?.value else {
                return .failed("That took too long and the link expired. Try connecting again.")
            }

            // Basiq fetches accounts in the background; the server waits up to
            // ~25 seconds a go. Most banks are done in a few.
            var result: ConsentResult = try await api.post("v1/consent/sessions/\(id)/wait")
            for _ in 0..<3 where result.status == "pending" {
                result = try await api.post("v1/consent/sessions/\(id)/wait")
            }
            switch result.status {
            case "ready":
                return .connected(result.accounts.map(LinkedAccount.init))
            case "cancelled":
                return .cancelled
            case "pending":
                return .failed("Your bank is still sending your accounts. They'll appear shortly.")
            default:
                let failure = result.failures.first
                return .failed([failure?.title, failure?.detail].compactMap { $0 }.joined(separator: ". "))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
