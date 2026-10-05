import SwiftUI
import Combine

/// The wallet: every linked bank merged into one pile of cash.
@MainActor
final class WalletStore: ObservableObject {

    enum Phase: Equatable {
        case loading
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var accounts: [LinkedAccount] = []
    @Published private(set) var history: [CashTransaction] = []

    /// The actual pieces of money in the wallet right now. This is the source of
    /// truth for both views — after paying with a £20 for a £4.45 coffee you are
    /// genuinely carrying the change, not a freshly tidied breakdown.
    @Published private(set) var pile: [Denomination] = []

    @Published private(set) var request: PaymentRequest?
    @Published private(set) var tenderedMinor: Int = 0
    /// What has physically been handed over, so cancelling can give it back.
    private var tenderedPieces: [Denomination] = []
    private var settlement: Task<Void, Never>?

    /// How long the negative "this is your change" figure is held on screen
    /// before the payment settles and the change falls back in.
    static let settleDelay: Duration = .milliseconds(1_100)
    @Published private(set) var lastSettlement: CashTransaction?
    @Published var errorMessage: String?

    private var sources: [BankDataSource]

    init(sources: [BankDataSource] = DemoBanks.sources()) {
        self.sources = sources
    }

    // MARK: Derived

    /// What is in the pile: every included account added together.
    var walletMinor: Int {
        accounts.filter(\.isIncluded).reduce(0) { $0 + $1.availableMinor }
    }

    var totalLinkedMinor: Int {
        accounts.reduce(0) { $0 + $1.availableMinor }
    }

    /// The pile grouped by denomination, biggest first — what the sorted view
    /// and the physics scene both read.
    var stacks: [MoneyStack] {
        let counts = Dictionary(grouping: pile, by: \.minor).mapValues(\.count)
        return Denomination.all.compactMap { denomination in
            guard let count = counts[denomination.minor], count > 0 else { return nil }
            return MoneyStack(denomination: denomination, count: count)
        }
    }

    var pileMinor: Int { pile.reduce(0) { $0 + $1.minor } }

    var pieceCount: Int { pile.count }

    var notes: [MoneyStack] { stacks.filter { $0.denomination.kind == .note } }
    var coins: [MoneyStack] { stacks.filter { $0.denomination.kind == .coin } }

    /// Changes whenever the physical contents change, so the scene knows to resync.
    var pileSignature: String {
        stacks.map { "\($0.denomination.minor)x\($0.count)" }.joined(separator: ",")
    }

    /// Re-break the balance into the fewest possible pieces.
    func tidyPile() {
        pile = Money.items(ofMinor: walletMinor)
    }

    var includedAccounts: [LinkedAccount] { accounts.filter(\.isIncluded) }

    /// The headline figure during a payment: what is still owed, counting down
    /// as money is handed over, and going negative once the merchant has been
    /// overpaid — at which point it is the change coming back.
    var outstandingMinor: Int {
        guard let request else { return 0 }
        return request.amountMinor - tenderedMinor
    }

    var isSettling: Bool { outstandingMinor <= 0 && request != nil }

    /// The change on its way back, once the merchant has been overpaid.
    var changeDueMinor: Int { max(0, -outstandingMinor) }

    // MARK: Loading

    func load() async {
        phase = .loading
        var merged: [LinkedAccount] = []
        for source in sources {
            do {
                try await source.connect()
                merged.append(contentsOf: try await source.accounts())
            } catch {
                errorMessage = "\(source.institution.name): \(error.localizedDescription)"
            }
        }
        accounts = merged.sorted { $0.availableMinor > $1.availableMinor }
        tidyPile()
        phase = .ready
    }

    /// Link another institution at runtime — the hook a real "add your bank"
    /// flow would call once consent comes back.
    func link(_ source: BankDataSource) async {
        sources.append(source)
        do {
            try await source.connect()
            accounts.append(contentsOf: try await source.accounts())
            accounts.sort { $0.availableMinor > $1.availableMinor }
            tidyPile()
        } catch {
            errorMessage = "\(source.institution.name): \(error.localizedDescription)"
        }
    }

    func setIncluded(_ included: Bool, for accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].isIncluded = included
        tidyPile()
    }

    // MARK: Paying

    func beginRequest(_ request: PaymentRequest) {
        settlement?.cancel()
        self.request = request
        tenderedMinor = 0
        tenderedPieces = []
        lastSettlement = nil
    }

    /// What tapping "Pay at till" does: the till rings up one of its menu items.
    func beginDemoRequest() {
        beginRequest(DemoTill.ringUp())
    }

    /// Back out. Anything already handed over drops back into the wallet.
    func cancelRequest() {
        settlement?.cancel()
        settlement = nil
        pile.append(contentsOf: tenderedPieces)
        tenderedPieces = []
        tenderedMinor = 0
        request = nil
    }

    /// Hand one note or coin to the merchant. Once the amount is covered the
    /// figure at the top goes negative and sits there for a beat — long enough
    /// to read as change — before the payment settles. Handing over more in the
    /// meantime simply pushes it further negative and restarts the beat.
    func tender(_ denomination: Denomination) {
        guard request != nil else { return }
        tenderedMinor += denomination.minor
        tenderedPieces.append(denomination)
        if let index = pile.firstIndex(of: denomination) { pile.remove(at: index) }

        guard outstandingMinor <= 0 else { return }
        settlement?.cancel()
        settlement = Task { [weak self] in
            try? await Task.sleep(for: WalletStore.settleDelay)
            guard !Task.isCancelled else { return }
            await self?.settle()
        }
    }

    /// Take the money, bank the spend, and hand back the change.
    func settle() async {
        guard let request, tenderedMinor >= request.amountMinor else { return }
        settlement = nil

        let changeMinor = tenderedMinor - request.amountMinor
        let debited = await debitIncluded(request.amountMinor)

        let transaction = CashTransaction(merchant: request.merchant,
                                          amountMinor: request.amountMinor,
                                          tenderedMinor: tenderedMinor,
                                          changeMinor: changeMinor,
                                          date: Date(),
                                          accounts: debited)
        history.insert(transaction, at: 0)
        lastSettlement = transaction

        self.request = nil
        tenderedMinor = 0
        tenderedPieces = []

        pile.append(contentsOf: Money.items(ofMinor: changeMinor))
        // Belt and braces: the pile must always add up to the available balance.
        if pileMinor != Money.cashable(walletMinor) { tidyPile() }
    }

    /// Spread the spend across the included accounts, fullest first.
    private func debitIncluded(_ minor: Int) async -> [String] {
        var remaining = minor
        var touched: [String] = []

        for account in accounts.filter(\.isIncluded).sorted(by: { $0.availableMinor > $1.availableMinor }) {
            guard remaining > 0 else { break }
            let take = min(remaining, account.availableMinor)
            guard take > 0 else { continue }

            if let source = sources.first(where: { $0.institution.id == account.institution.id }) {
                do {
                    try await source.debit(accountID: account.id, minor: take)
                } catch {
                    errorMessage = error.localizedDescription
                    continue
                }
            }
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index].availableMinor -= take
            }
            touched.append("\(account.institution.name) \(account.nickname)")
            remaining -= take
        }
        return touched
    }

    // MARK: Demo helpers

    /// Put the demo back to its starting state.
    func reset() async {
        settlement?.cancel()
        sources = DemoBanks.sources()
        history = []
        request = nil
        tenderedMinor = 0
        tenderedPieces = []
        lastSettlement = nil
        await load()
    }
}
