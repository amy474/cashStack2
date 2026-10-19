import Foundation
import MetricKit

/// MetricKit hands the app a report after it crashes, hangs, or uses too much
/// CPU or disk — for a crash, on the next launch. Each report is written to
/// Caches straight away and sent to POST /v1/diagnostics, and the file is only
/// deleted once the server has it, so a crash on the train still arrives.
///
/// Reports go without a token or anything else about the person: a crash in
/// the demo or before sign-in counts too, and none can be tied to anyone.
/// MetricKit's reports hold call stacks, the app and iOS versions and the
/// iPhone model — no balances, names or account details.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = CrashReporter()

    private let outbox = DiagnosticsOutbox()

    func start() {
        MXMetricManager.shared.add(self)
        let outbox = outbox
        Task.detached(priority: .utility) { await outbox.sendAll() }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.map { $0.jsonRepresentation() }
        Log.diagnostics.notice("MetricKit delivered \(reports.count, privacy: .public) diagnostic report(s)")
        let outbox = outbox
        Task.detached(priority: .utility) {
            for report in reports { await outbox.keep(report) }
            await outbox.sendAll()
        }
    }
}

/// Reports waiting to reach the server, one file each, named so they sort
/// oldest first. Only the newest twenty are kept.
actor DiagnosticsOutbox {

    private let folder: URL
    private let endpoint: URL
    private let session: URLSession
    private let keepAtMost = 20
    private var sending = false

    init(folder: URL? = nil,
         endpoint: URL = AppConfig.apiBaseURL.appending(path: "v1/diagnostics"),
         config: URLSessionConfiguration = .ephemeral) {
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
        self.endpoint = endpoint
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "X-CashStack-Build": String(AppConfig.build),
            "X-CashStack-Version": AppConfig.marketingVersion,
        ]
        session = URLSession(configuration: config)
    }

    func keep(_ report: Data) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = String(format: "%.0f-%@.json", Date().timeIntervalSince1970 * 1000, UUID().uuidString)
            try report.write(to: folder.appending(path: name), options: .atomic)
        } catch {
            Log.diagnostics.error("Couldn't keep a diagnostic report: \(error.localizedDescription, privacy: .public)")
        }
        let waiting = queued()
        for old in waiting.dropLast(keepAtMost) { try? FileManager.default.removeItem(at: old) }
    }

    /// Send everything waiting, oldest first. Stops at the first report the
    /// server can't take right now (offline, rate-limited, down) and tries
    /// again next launch; one the server refuses outright is dropped.
    func sendAll() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        for file in queued() {
            guard let body = try? Data(contentsOf: file) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            guard let (_, response) = try? await session.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else {
                Log.diagnostics.notice("Server unreachable; keeping diagnostic reports for later")
                return
            }
            switch status {
            case 200..<300:
                Log.diagnostics.notice("Sent a diagnostic report")
                try? FileManager.default.removeItem(at: file)
            case 400, 413:
                Log.diagnostics.error("Server refused a diagnostic report (\(status, privacy: .public)); dropping it")
                try? FileManager.default.removeItem(at: file)
            default:
                Log.diagnostics.notice("Server answered \(status, privacy: .public); keeping diagnostic reports for later")
                return
            }
        }
    }

    private func queued() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
