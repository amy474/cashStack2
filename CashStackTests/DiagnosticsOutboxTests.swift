import Foundation
import Testing
@testable import CashStack

/// Crash reports wait on disk until the server has them.
@Suite("Crash report outbox")
struct DiagnosticsOutboxTests {

    private let folder = FileManager.default.temporaryDirectory
        .appending(path: "outbox-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func outbox(_ server: StubServer) -> DiagnosticsOutbox {
        DiagnosticsOutbox(folder: folder, endpoint: server.base.appending(path: "v1/diagnostics"), config: server.configuration())
    }

    private func waiting() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private func report(_ n: Int) -> Data { Data(#"{"crashDiagnostics":[{"n":\#(n)}]}"#.utf8) }

    @Test("Sent reports are deleted; the server gets them as written, without a token")
    func sends() async throws {
        let server = StubServer { _ in (202, ["received": 1]) }
        let outbox = outbox(server)
        await outbox.keep(report(1))
        try await Task.sleep(for: .milliseconds(3))   // so "oldest" means something
        await outbox.keep(report(2))
        await outbox.sendAll()

        #expect(waiting().isEmpty)
        #expect(server.requests.map(\.path) == ["/v1/diagnostics", "/v1/diagnostics"])
        #expect(server.requests.first?.body == report(1), "Oldest first")
        #expect(server.requests.allSatisfy { $0.header("Authorization") == nil })
        #expect(server.requests.first?.header("X-CashStack-Build") == String(AppConfig.build))
    }

    @Test("While the server can't take them, reports wait for next time")
    func waitsWhenDown() async {
        let server = StubServer { _ in (503, ["error": "maintenance", "message": "Back soon."]) }
        let outbox = outbox(server)
        await outbox.keep(report(1))
        await outbox.keep(report(2))
        await outbox.sendAll()

        #expect(waiting().count == 2)
        #expect(server.requests.count == 1, "It stops at the first one that can't go")
    }

    @Test("Offline, reports wait too")
    func waitsOffline() async {
        let server = StubServer { _ in throw URLError(.notConnectedToInternet) }
        let outbox = outbox(server)
        await outbox.keep(report(1))
        await outbox.sendAll()
        #expect(waiting().count == 1)
    }

    @Test("A report the server refuses outright is dropped")
    func dropsRefused() async {
        let server = StubServer { _ in (400, ["error": "invalid_request", "message": "Nope."]) }
        let outbox = outbox(server)
        await outbox.keep(report(1))
        await outbox.sendAll()
        #expect(waiting().isEmpty)
    }

    @Test("Only the newest twenty are kept")
    func keepsTwenty() async throws {
        let server = StubServer { _ in (202, nil) }
        let outbox = outbox(server)
        for n in 0..<25 {
            await outbox.keep(report(n))
            try await Task.sleep(for: .milliseconds(3))   // distinct timestamps in the names
        }
        let kept = waiting()
        #expect(kept.count == 20)
        #expect(kept.first == String(decoding: report(5), as: UTF8.self))
        #expect(kept.last == String(decoding: report(24), as: UTF8.self))
    }
}
