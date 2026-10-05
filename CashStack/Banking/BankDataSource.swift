import Foundation

/// Everything the wallet needs from one bank. Each linked institution is a
/// separate data source, which is what makes multi-bank aggregation work: the
/// wallet holds a list of these and merges whatever they return.
///
/// A production build adds one conforming type per aggregation route — an
/// Open Banking AISP (TrueLayer, Plaid, Yapily…) or a bank's own API — and the
/// rest of the app is unchanged, because nothing above this protocol knows
/// where a balance came from.
protocol BankDataSource: AnyObject {
    var institution: Institution { get }
    /// Kick off consent / authorisation for this institution.
    func connect() async throws
    /// Current accounts and available balances.
    func accounts() async throws -> [LinkedAccount]
    /// Reduce the available balance after money has been handed over.
    func debit(accountID: String, minor: Int) async throws
}

enum BankError: LocalizedError {
    case notConnected
    case unknownAccount
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .notConnected:       "That bank isn't connected yet."
        case .unknownAccount:     "That account no longer exists."
        case .insufficientFunds:  "Not enough available balance."
        }
    }
}

/// Demo source. Holds balances in memory and answers with a short delay so the
/// loading states are real rather than decorative.
final class DemoBankDataSource: BankDataSource {

    let institution: Institution
    private var seeded: [LinkedAccount]
    private var isConnected = false
    private let latency: Duration

    init(institution: Institution, accounts: [LinkedAccount], latency: Duration = .milliseconds(420)) {
        self.institution = institution
        self.seeded = accounts
        self.latency = latency
    }

    func connect() async throws {
        try? await Task.sleep(for: latency)
        isConnected = true
    }

    func accounts() async throws -> [LinkedAccount] {
        guard isConnected else { throw BankError.notConnected }
        try? await Task.sleep(for: latency)
        return seeded
    }

    func debit(accountID: String, minor: Int) async throws {
        guard let index = seeded.firstIndex(where: { $0.id == accountID }) else {
            throw BankError.unknownAccount
        }
        guard seeded[index].availableMinor >= minor else { throw BankError.insufficientFunds }
        seeded[index].availableMinor -= minor
    }
}

enum DemoBanks {

    static func sources() -> [BankDataSource] {
        [
            DemoBankDataSource(institution: .wattle, accounts: [
                LinkedAccount(id: "wattle-everyday", institution: .wattle,
                              nickname: "Everyday", maskedNumber: "•••• 4417",
                              availableMinor: 18_740, isIncluded: true)
            ]),
            DemoBankDataSource(institution: .rosella, accounts: [
                LinkedAccount(id: "rosella-spend", institution: .rosella,
                              nickname: "Spending", maskedNumber: "•••• 9032",
                              availableMinor: 10_025, isIncluded: true)
            ], latency: .milliseconds(620)),
            DemoBankDataSource(institution: .meridian, accounts: [
                LinkedAccount(id: "meridian-saver", institution: .meridian,
                              nickname: "Savings", maskedNumber: "•••• 1180",
                              availableMinor: 120_500, isIncluded: false)
            ], latency: .milliseconds(300))
        ]
    }

    /// The institution offered by "Link another bank".
    static func extraSource() -> BankDataSource {
        DemoBankDataSource(institution: .boab, accounts: [
            LinkedAccount(id: "boab-joint", institution: .boab,
                          nickname: "Joint", maskedNumber: "•••• 7725",
                          availableMinor: 4_310, isIncluded: true)
        ])
    }
}
