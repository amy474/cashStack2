import SwiftUI

/// Something the server needs this build to stop and show.
enum ServiceNotice: Equatable, Sendable {
    /// This build is older than the server's MIN_APP_BUILD.
    case updateRequired(message: String, updateURL: URL?)
    /// The server is switched off with MAINTENANCE_MESSAGE.
    case maintenance(message: String)

    static let updateMessage = "This version of CashStack is out of date. Update it to keep going."

    var isMaintenance: Bool {
        if case .maintenance = self { return true }
        return false
    }
}

/// What GET /v1/status says.
struct ServiceStatusResponse: Decodable, Sendable {
    let minBuild: Int
    let updateUrl: URL?
    let maintenance: Maintenance?
    struct Maintenance: Decodable, Sendable { let message: String }
}

/// Whether the server will talk to this build, and whether it's up. The
/// server can turn old builds away or switch the app off for maintenance
/// without a new release; this is how the app finds out — by asking at
/// launch and whenever it comes back to the front, and from any request the
/// server turns away along the way.
@MainActor
final class ServiceStatus: ObservableObject {

    @Published private(set) var notice: ServiceNotice?

    /// Set by a UI test, so a real server can't clear it.
    private var simulated = false

    init() {
        #if DEBUG
        // UI tests launch with `-serviceNotice update` or `-serviceNotice maintenance`.
        switch UserDefaults.standard.string(forKey: "serviceNotice") {
        case "update":
            notice = .updateRequired(message: ServiceNotice.updateMessage, updateURL: URL(string: "https://apps.apple.com"))
            simulated = true
        case "maintenance":
            notice = .maintenance(message: "We're upgrading CashStack. Back by 9pm.")
            simulated = true
        default:
            break
        }
        #endif
    }

    /// Ask the server. Offline, or if it doesn't answer, nothing changes.
    func check(_ api: APIClient) async {
        guard !simulated, let status = try? await api.status() else { return }
        if AppConfig.build < status.minBuild {
            heard(.updateRequired(message: ServiceNotice.updateMessage, updateURL: status.updateUrl))
        } else if let maintenance = status.maintenance {
            heard(.maintenance(message: maintenance.message))
        } else if notice != nil {
            Log.api.notice("Server is open to this build again")
            notice = nil
        }
    }

    /// A request was turned away, or the status check said so.
    func heard(_ notice: ServiceNotice) {
        guard !simulated, notice != self.notice else { return }
        switch notice {
        case .updateRequired: Log.api.notice("Server requires a newer build than \(AppConfig.build, privacy: .public)")
        case .maintenance: Log.api.notice("Server is down for maintenance")
        }
        self.notice = notice
    }
}
