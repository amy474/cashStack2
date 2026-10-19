import Foundation
import Testing
@testable import CashStack

/// The API client against a stub server: tokens, being told to update or
/// that the server is down, and having no network.
@Suite("API client")
struct APIClientTests {

    private static let me: [String: Any] = [
        "id": "user-1", "email": "someone@privaterelay.appleid.com",
        "bank": ["linked": false, "reachable": true, "consent": NSNull()],
    ]

    @Test("Every request says which build it is")
    func sendsBuild() async throws {
        let server = StubServer { _ in (200, ["minBuild": 0, "updateUrl": NSNull(), "maintenance": NSNull()]) }
        let api = APIClient(base: server.base, config: server.configuration())
        _ = try await api.status()
        let request = try #require(server.requests.first)
        #expect(request.header("X-CashStack-Build") == String(AppConfig.build))
        #expect(request.header("X-CashStack-Version") == AppConfig.marketingVersion)
    }

    @Test("An old build is told to update, with where to go")
    func updateRequired() async {
        let server = StubServer { _ in
            (426, ["error": "upgrade_required", "message": "Update it.", "updateUrl": "https://apps.apple.com/app/id1"])
        }
        let api = APIClient(base: server.base, config: server.configuration())
        let heard = Box<[ServiceNotice]>([])
        await api.observe { heard.value.append($0) }

        await #expect(throws: APIError.updateRequired(message: "Update it.")) {
            _ = try await api.signInForDevelopment()
        }
        #expect(heard.value == [.updateRequired(message: "Update it.", updateURL: URL(string: "https://apps.apple.com/app/id1"))])
    }

    @Test("Maintenance comes through with its message")
    func maintenance() async {
        let server = StubServer { _ in (503, ["error": "maintenance", "message": "Back by 9pm."]) }
        let api = APIClient(base: server.base, config: server.configuration())
        let heard = Box<[ServiceNotice]>([])
        await api.observe { heard.value.append($0) }

        await #expect(throws: APIError.maintenance(message: "Back by 9pm.")) {
            _ = try await api.signInForDevelopment()
        }
        #expect(heard.value == [.maintenance(message: "Back by 9pm.")])
    }

    @Test("An expired access token is swapped once, and the new refresh token kept")
    func refreshes() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/v1/auth/refresh":
                return (200, ["accessToken": "access-2", "refreshToken": "refresh-2", "expiresIn": 900])
            case "/v1/me":
                return request.header("Authorization") == "Bearer access-2"
                    ? (200, Self.me)
                    : (401, ["error": "unauthorized", "message": "Sign in again to continue."])
            default:
                return (404, ["error": "not_found", "message": "Nothing here."])
            }
        }
        let api = APIClient(base: server.base, config: server.configuration())
        let rotated = Box<[String]>([])
        await api.configure(onRotate: { rotated.value.append($0) }, onSignedOut: {})
        await api.restore(refreshToken: "refresh-1")

        let me: Me = try await api.get("v1/me")

        #expect(me.id == "user-1")
        #expect(rotated.value == ["refresh-2"])
        let refreshes = server.requests.filter { $0.path == "/v1/auth/refresh" }
        #expect(refreshes.count == 1)
        #expect(refreshes.first?.json?["refreshToken"] as? String == "refresh-1")
    }

    @Test("A refresh token the server won't take signs the person out")
    func signsOut() async {
        let server = StubServer { _ in (401, ["error": "session_expired", "message": "Sign in again to continue."]) }
        let api = APIClient(base: server.base, config: server.configuration())
        let signedOut = Box(false)
        await api.configure(onRotate: { _ in }, onSignedOut: { signedOut.value = true })
        await api.restore(refreshToken: "refresh-1")

        await #expect(throws: APIError.signedOut) {
            let _: Me = try await api.get("v1/me")
        }
        #expect(signedOut.value)
        #expect(await api.currentRefreshToken == nil, "Nothing is left in memory")
    }

    @Test("No network reads as offline, not as an error")
    func offline() async {
        let server = StubServer { _ in throw URLError(.notConnectedToInternet) }
        let api = APIClient(base: server.base, config: server.configuration())
        await #expect(throws: APIError.offline) {
            _ = try await api.status()
        }
    }
}

/// What the app does with the server's answer to GET /v1/status.
@MainActor
@Suite("Service status")
struct ServiceStatusTests {

    private func status(_ answer: Box<(Int, Any?)>) -> (ServiceStatus, APIClient, StubServer) {
        let server = StubServer { _ in answer.value }
        return (ServiceStatus(), APIClient(base: server.base, config: server.configuration()), server)
    }

    @Test("A build below the minimum is stopped, and maintenance follows the server")
    func followsTheServer() async {
        let answer = Box<(Int, Any?)>((200, ["minBuild": AppConfig.build + 1, "updateUrl": "https://apps.apple.com/app/id1", "maintenance": NSNull()]))
        let (status, api, server) = status(answer)
        await status.check(api)
        #expect(status.notice == .updateRequired(message: ServiceNotice.updateMessage, updateURL: URL(string: "https://apps.apple.com/app/id1")))

        answer.value = (200, ["minBuild": 0, "updateUrl": NSNull(), "maintenance": ["message": "Back soon."]])
        await status.check(api)
        #expect(status.notice == .maintenance(message: "Back soon."))

        answer.value = (200, ["minBuild": 0, "updateUrl": NSNull(), "maintenance": NSNull()])
        await status.check(api)
        #expect(status.notice == nil)
        withExtendedLifetime(server) {}
    }

    @Test("Offline, the app keeps what it last heard")
    func offlineKeepsNotice() async {
        let answer = Box<(Int, Any?)>((200, ["minBuild": 0, "updateUrl": NSNull(), "maintenance": ["message": "Back soon."]]))
        let (status, api, server) = status(answer)
        await status.check(api)
        let offline = StubServer { _ in throw URLError(.notConnectedToInternet) }
        await status.check(APIClient(base: offline.base, config: offline.configuration()))
        #expect(status.notice == .maintenance(message: "Back soon."))
        withExtendedLifetime(server) {}
    }
}
