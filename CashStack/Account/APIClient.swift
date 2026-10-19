import Foundation

// MARK: - What the server sends

struct TokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct SignInResult: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
    struct User: Decodable, Sendable { let id: String; let isNew: Bool }
}

struct APIInstitution: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let color: String?
}

struct APIAccount: Decodable, Hashable, Sendable {
    let id: String
    let connectionId: String?
    let institution: APIInstitution
    let name: String
    let maskedNumber: String
    let type: String
    let availableMinor: Int
    let balanceMinor: Int?
    let lastUpdated: Date?
}

struct AccountsResponse: Decodable, Sendable {
    let accounts: [APIAccount]
    let refreshed: Bool?
}

struct APIConnection: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let institution: APIInstitution
    let status: String
    let expiresAt: Date?
    let lastUsed: Date?
}

struct ConnectionsResponse: Decodable, Sendable {
    let connections: [APIConnection]
}

struct Me: Decodable, Sendable {
    let id: String
    let email: String?
    let bank: Bank
    struct Bank: Decodable, Sendable {
        let linked: Bool
        let reachable: Bool
        let consent: Consent?
    }
    struct Consent: Decodable, Sendable {
        let status: String
        let expiresAt: Date?
    }
}

struct ConsentSession: Decodable, Sendable {
    let id: String
    let url: URL
    let callbackScheme: String
}

struct ConsentResult: Decodable, Sendable {
    /// ready, pending, failed or cancelled.
    let status: String
    let failures: [Failure]
    let accounts: [APIAccount]
    struct Failure: Decodable, Sendable {
        let title: String
        let detail: String?
    }
}

// MARK: - Errors

enum APIError: LocalizedError, Equatable {
    /// The session is gone — signed out elsewhere, deleted, or expired.
    case signedOut
    /// The app is locked; nothing can be fetched until Face ID.
    case locked
    case offline
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "You've been signed out. Sign in again to continue."
        case .locked: "Unlock CashStack to continue."
        case .offline: "You're offline. Your balance will update when you're back."
        case .server(_, let message): message
        }
    }
}

// MARK: - Client

/// Talks to the CashStack API. Holds the short-lived access token in memory
/// only, swaps the refresh token for a new pair when it runs out, and hands
/// each new refresh token to `onRotate` to be written to the Keychain. Only
/// one refresh is ever in flight; everything else waits for it.
actor APIClient {

    private let base: URL
    private let session: URLSession
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var refreshToken: String?
    private var refreshing: Task<Void, Error>?

    /// The new refresh token after every sign-in or rotation.
    private var onRotate: (@Sendable (String) -> Void)?
    /// The server said the session is over.
    private var onSignedOut: (@Sendable () -> Void)?

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = precise.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(text)"))
        }
        return decoder
    }()

    init(base: URL = AppConfig.apiBaseURL) {
        self.base = base
        // No cookies, no cache, nothing written to disk by URLSession.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    func configure(onRotate: @escaping @Sendable (String) -> Void, onSignedOut: @escaping @Sendable () -> Void) {
        self.onRotate = onRotate
        self.onSignedOut = onSignedOut
    }

    // MARK: Session

    /// Start from a refresh token read out of the Keychain.
    func restore(refreshToken: String) {
        self.refreshToken = refreshToken
        accessToken = nil
        accessExpiry = .distantPast
    }

    /// Drop every token from memory — on lock and on sign-out.
    func forget() {
        refreshing?.cancel()
        refreshing = nil
        accessToken = nil
        refreshToken = nil
        accessExpiry = .distantPast
    }

    var currentRefreshToken: String? { refreshToken }

    private func adopt(access: String, refresh: String, expiresIn: Int) {
        accessToken = access
        refreshToken = refresh
        // Treat it as expired a little early, so it never lapses mid-request.
        accessExpiry = Date().addingTimeInterval(TimeInterval(expiresIn) - 60)
        onRotate?(refresh)
    }

    func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?, device: String) async throws -> SignInResult {
        struct Body: Encodable { let identityToken, rawNonce: String; let authorizationCode: String?; let device: String }
        let result: SignInResult = try await send("POST", "v1/auth/apple",
                                                  body: Body(identityToken: identityToken, rawNonce: rawNonce,
                                                             authorizationCode: authorizationCode, device: device),
                                                  authorized: false)
        adopt(access: result.accessToken, refresh: result.refreshToken, expiresIn: result.expiresIn)
        return result
    }

    func signInForDevelopment() async throws -> SignInResult {
        struct Body: Encodable { let name = "developer" }
        let result: SignInResult = try await send("POST", "v1/auth/dev", body: Body(), authorized: false)
        adopt(access: result.accessToken, refresh: result.refreshToken, expiresIn: result.expiresIn)
        return result
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessExpiry > Date() { return accessToken }
        try await refresh()
        guard let accessToken else { throw APIError.signedOut }
        return accessToken
    }

    private func refresh() async throws {
        if let refreshing { return try await refreshing.value }
        guard let token = refreshToken else { throw APIError.locked }
        let task = Task {
            struct Body: Encodable { let refreshToken: String }
            do {
                let pair: TokenPair = try await send("POST", "v1/auth/refresh", body: Body(refreshToken: token), authorized: false)
                adopt(access: pair.accessToken, refresh: pair.refreshToken, expiresIn: pair.expiresIn)
            } catch APIError.server(let code, _) where code == "session_expired" {
                forget()
                onSignedOut?()
                throw APIError.signedOut
            }
        }
        refreshing = task
        defer { refreshing = nil }
        try await task.value
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path, body: Optional<String>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send("POST", path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await send("DELETE", path)
    }

    func signOut() async {
        if refreshToken != nil, (try? await validAccessToken()) != nil {
            _ = try? await send("POST", "v1/auth/logout") as Empty
        }
        forget()
    }

    private struct Empty: Decodable {}
    private struct ErrorBody: Decodable { let error: String; let message: String }

    private func send<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        try await send(method, path, body: Optional<String>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, authorized: Bool = true) async throws -> T {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for attempt in 0..<2 {
            if authorized {
                request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
            }
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .cannotFindHost].contains(error.code) {
                throw APIError.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // A token revoked early: refresh once and go again.
            if status == 401 && authorized && attempt == 0 {
                accessToken = nil
                continue
            }
            guard (200..<300).contains(status) else {
                let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
                if status == 401 && authorized {
                    forget()
                    onSignedOut?()
                    throw APIError.signedOut
                }
                throw APIError.server(code: body?.error ?? "http_\(status)",
                                      message: body?.message ?? "Something went wrong. Try again.")
            }
            if status == 204 || data.isEmpty {
                return try Self.decoder.decode(T.self, from: Data("{}".utf8))
            }
            return try Self.decoder.decode(T.self, from: data)
        }
        throw APIError.signedOut
    }
}
