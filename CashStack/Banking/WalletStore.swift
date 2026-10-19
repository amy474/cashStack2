import SwiftUI
import Combine

/// The wallet: one linked account at a time, shown as a pile of cash. Several
/// banks can be linked, but only the selected account's money is in the pile
/// and only that account is debited when you pay.
@MainActor
final class WalletStore: ObservableObject {

    enum Phase: Equatable {
        case loading
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var accounts: [LinkedAccount] = []
    /// The one account whose money is in the pile and pays at the till.
    @Published private(set) var selectedAccountID: String?
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

    /// Where spare change goes and how much of it may. Edited in place by the
    /// settings sheet.
    @Published var spareChange = SpareChangeSettings()
    /// Every piece that has gone in a jar, newest first. Undoing one removes it.
    @Published private(set) var drops: [JarDrop] = []
    /// The drop the undo toast is offering to take back.
    @Published private(set) var lastDrop: JarDrop?

    /// Coins in the tip jar for the payment in progress. Kept apart from what
    /// was handed over: the bill is the bill, and the tip is on top of it.
    @Published private(set) var tipPieces: [Denomination] = []
    var tipMinor: Int { tipPieces.reduce(0) { $0 + $1.minor } }

    private var sources: [BankDataSource]
    /// Which source each account came from, so a payment goes to the right bank.
    private var owners: [String: BankDataSource] = [:]
    /// What each bank last said, before any practice spending.
    @Published private(set) var bankMinor: [String: Int] = [:]
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isRefreshing = false
    /// The last attempt to read the banks failed, so an empty wallet means
    /// "couldn't reach them", not "nothing connected".
    @Published private(set) var loadFailed = false

    /// Real banks, read-only: paying and the jars are practice, and the
    /// chosen account is remembered between launches.
    let isLive: Bool

    init(sources: [BankDataSource] = DemoBanks.sources(), isLive: Bool = false) {
        self.sources = sources
        self.isLive = isLive
        if isLive { selectedAccountID = UserDefaults.standard.string(forKey: Preference.selectedAccountID) }
    }

    // MARK: Derived

    var selectedAccount: LinkedAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    /// What is in the pile: the selected account's available balance.
    var walletMinor: Int { selectedAccount?.availableMinor ?? 0 }

    /// How far practice payments and jars have taken the pile below what the
    /// bank says. Always zero in the demo, where the money "really" moves.
    var practiceSpentMinor: Int {
        guard isLive, let id = selectedAccountID, let bank = bankMinor[id] else { return 0 }
        return max(0, bank - walletMinor)
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

    /// Swap one piece of money for the same value in smaller pieces. The scene
    /// has already decided the split is allowed and animated it, so this just
    /// keeps the wallet's own record in step.
    func split(_ denomination: Denomination) {
        let pieces = Money.split(denomination)
        guard !pieces.isEmpty, let index = pile.firstIndex(of: denomination) else { return }
        pile.remove(at: index)
        pile.append(contentsOf: pieces)
    }

    /// Re-break the balance into the fewest possible pieces.
    func tidyPile() {
        pile = Money.items(ofMinor: walletMinor)
    }

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
        loadFailed = false
        var merged: [(LinkedAccount, BankDataSource)] = []
        for source in sources {
            do {
                try await source.connect()
                merged.append(contentsOf: try await source.accounts().map { ($0, source) })
            } catch {
                loadFailed = true
                errorMessage = isLive ? error.localizedDescription
                                      : "\(source.institution.name): \(error.localizedDescription)"
            }
        }
        adopt(merged)
        phase = .ready
    }

    /// Take a fresh set of accounts from the bank. Any practice spending is
    /// forgotten: the pile goes back to what the bank says.
    private func adopt(_ merged: [(LinkedAccount, BankDataSource)]) {
        owners = Dictionary(merged.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        accounts = merged.map(\.0).sorted { $0.availableMinor > $1.availableMinor }
        bankMinor = Dictionary(accounts.map { ($0.id, $0.availableMinor) }, uniquingKeysWith: { first, _ in first })
        lastRefreshed = Date()
        // Keep the account the user picked; otherwise start with the first
        // bank's account rather than whichever happens to hold the most.
        if selectedAccount == nil { selectedAccountID = merged.first?.0.id }
        rememberSelection()
        tidyPile()
    }

    /// Ask the banks for the latest balances. Not mid-payment: the money in
    /// the hand came out of the balance as it was.
    func refreshFromBank() async {
        guard request == nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let merged = await readAll({ try await $0.refresh() }), request == nil else { return }
        adopt(merged)
    }

    /// Put the pile back to the bank balance without asking the bank again.
    func discardPractice() {
        guard request == nil else { return }
        for index in accounts.indices {
            if let bank = bankMinor[accounts[index].id] { accounts[index].availableMinor = bank }
        }
        tidyPile()
    }

    /// Accounts that just came back from connecting a bank.
    func connected(_ linked: [LinkedAccount]) async {
        if let first = linked.first, selectedAccount == nil { selectedAccountID = first.id }
        await refreshQuietly()
    }

    /// Reload without the loading screen, keeping the pile on show.
    func refreshQuietly() async {
        guard request == nil, let merged = await readAll({ try await $0.accounts() }), request == nil else { return }
        adopt(merged)
    }

    /// Every source's accounts, or nil (with the error on show) if any failed.
    private func readAll(_ read: (BankDataSource) async throws -> [LinkedAccount]) async -> [(LinkedAccount, BankDataSource)]? {
        var merged: [(LinkedAccount, BankDataSource)] = []
        for source in sources {
            do {
                merged.append(contentsOf: try await read(source).map { ($0, source) })
            } catch {
                errorMessage = error.localizedDescription
                loadFailed = true
                return nil
            }
        }
        loadFailed = false
        return merged
    }

    private func rememberSelection() {
        guard isLive else { return }
        UserDefaults.standard.set(selectedAccountID, forKey: Preference.selectedAccountID)
    }

    /// Link another institution at runtime — the hook a real "add your bank"
    /// flow would call once consent comes back.
    func link(_ source: BankDataSource) async {
        sources.append(source)
        do {
            try await source.connect()
            let linked = try await source.accounts()
            for account in linked {
                owners[account.id] = source
                bankMinor[account.id] = account.availableMinor
            }
            accounts.append(contentsOf: linked)
            accounts.sort { $0.availableMinor > $1.availableMinor }
            tidyPile()
        } catch {
            errorMessage = "\(source.institution.name): \(error.localizedDescription)"
        }
    }

    /// Swap the pile over to another account. Not allowed mid-payment: the
    /// money already handed over came out of the account that was selected.
    func select(_ accountID: String) {
        guard request == nil, accountID != selectedAccountID,
              accounts.contains(where: { $0.id == accountID }) else { return }
        selectedAccountID = accountID
        rememberSelection()
        tidyPile()
    }

    // MARK: Paying

    func beginRequest(_ request: PaymentRequest) {
        settlement?.cancel()
        self.request = request
        tenderedMinor = 0
        tenderedPieces = []
        tipPieces = []
        lastSettlement = nil
    }

    /// What tapping "Pay at till" does: the till rings up one of its menu items.
    /// UI tests can pin it to one merchant with `-till "Pocket Coffee"`.
    func beginDemoRequest() {
        if let name = UserDefaults.standard.string(forKey: "till"),
           let item = DemoTill.menu.first(where: { $0.merchant == name }) {
            beginRequest(DemoTill.ringUp(item))
        } else {
            beginRequest(DemoTill.ringUp())
        }
    }

    /// Back out. Anything already handed over, and anything in the tip jar,
    /// drops back into the wallet.
    func cancelRequest() {
        settlement?.cancel()
        settlement = nil
        pile.append(contentsOf: tenderedPieces)
        pile.append(contentsOf: tipPieces)
        tenderedPieces = []
        tipPieces = []
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

    /// Take the money and the tip, bank the spend, and hand back the change.
    func settle() async {
        guard let request, tenderedMinor >= request.amountMinor else { return }
        settlement = nil

        let changeMinor = tenderedMinor - request.amountMinor
        let tips = tipPieces
        let payer = selectedAccountID
        let debited = await debitSelected(request.amountMinor + tips.reduce(0) { $0 + $1.minor })

        let transaction = CashTransaction(merchant: request.merchant,
                                          amountMinor: request.amountMinor,
                                          tenderedMinor: tenderedMinor,
                                          changeMinor: changeMinor,
                                          date: Date(),
                                          accounts: debited,
                                          accountID: payer,
                                          acceptsTips: request.acceptsTips,
                                          tipPieces: tips)
        history.insert(transaction, at: 0)
        lastSettlement = transaction

        self.request = nil
        tenderedMinor = 0
        tenderedPieces = []
        tipPieces = []

        pile.append(contentsOf: Money.items(ofMinor: changeMinor))
        // Belt and braces: the pile must always add up to the available balance.
        if pileMinor != Money.cashable(walletMinor) { tidyPile() }
    }

    /// Take the spend from the selected account — the only one whose money
    /// was in the pile to hand over.
    private func debitSelected(_ minor: Int) async -> [String] {
        guard let account = selectedAccount, minor > 0 else { return [] }

        if let source = owners[account.id] {
            do {
                try await source.debit(accountID: account.id, minor: minor)
            } catch {
                errorMessage = error.localizedDescription
                return []
            }
        }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].availableMinor -= minor
        }
        return ["\(account.institution.name) \(account.nickname)"]
    }

    // MARK: Spare change — the jars

    /// The jars that come out when a piece is picked up, in order.
    var visibleJars: [CoinJar] {
        CoinJar.allCases.filter { !spareChange.hiddenJars.contains($0) }
    }

    /// Whether picking this piece up should bring the jars out at all.
    func jarsTake(_ denomination: Denomination) -> Bool {
        !visibleJars.isEmpty && (denomination.kind == .coin || spareChange.notesAllowed)
    }

    var savingsAccount: LinkedAccount? {
        accounts.first { $0.id == spareChange.savingsAccountID }
    }

    /// Where a jar's money goes, once one has been chosen.
    func destination(of jar: CoinJar) -> String? {
        switch jar {
        case .invest: spareChange.investment?.ticker
        case .donate: spareChange.charity?.name
        case .save:   savingsAccount.map { "\($0.institution.name) \($0.nickname)" }
        }
    }

    /// Why this jar will not take that piece right now, or nil if it will. A
    /// jar with nowhere to send money yet still takes it — it asks where first.
    func refusal(_ jar: CoinJar, for denomination: Denomination?) -> String? {
        if jar == .save, let savings = spareChange.savingsAccountID, savings == selectedAccountID {
            return "You're paying from it"
        }
        guard let denomination else { return nil }
        if denomination.kind == .note && !spareChange.notesAllowed { return "Coins only" }
        if let left = jarAllowanceLeftMinor, denomination.minor > left {
            return left < Money.smallestPiece ? "Daily limit reached"
                                              : "Only \(Money.formatShort(minor: left)) left today"
        }
        return nil
    }

    var droppedTodayMinor: Int {
        drops.filter { Calendar.current.isDateInToday($0.date) }
             .reduce(0) { $0 + $1.denomination.minor }
    }

    /// What can still go in the jars today, or nil when there is no limit.
    var jarAllowanceLeftMinor: Int? {
        spareChange.dailyLimitMinor.map { max(0, $0 - droppedTodayMinor) }
    }

    /// This month's total for one jar, for the jar faces and the settings sheet.
    func monthTotal(_ jar: CoinJar) -> Int {
        drops.filter { $0.jar == jar && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
             .reduce(0) { $0 + $1.denomination.minor }
    }

    /// Drop one piece in a jar: out of the pile, off the selected account and,
    /// when saving, into the savings account. False if the jar refused it.
    @discardableResult
    func drop(_ denomination: Denomination, into jar: CoinJar) -> Bool {
        guard refusal(jar, for: denomination) == nil,
              let destination = destination(of: jar),
              let from = selectedAccountID,
              takeFromPile(denomination) else { return false }

        let to = jar == .save ? spareChange.savingsAccountID : nil
        post(denomination.minor, to: from, debit: true)
        if let to { post(denomination.minor, to: to, debit: false) }

        let drop = JarDrop(jar: jar, denomination: denomination, destination: destination,
                           fromAccountID: from, toAccountID: to, date: Date())
        drops.insert(drop, at: 0)
        lastDrop = drop
        return true
    }

    /// Take a piece back out of a jar. Invested and donated coins wait in a
    /// pool until the market opens or the 1st comes round, so until then
    /// they can still come home.
    func undo(_ drop: JarDrop) {
        guard let index = drops.firstIndex(where: { $0.id == drop.id }) else { return }
        drops.remove(at: index)
        if lastDrop?.id == drop.id { lastDrop = nil }

        post(drop.denomination.minor, to: drop.fromAccountID, debit: false)
        if let to = drop.toAccountID { post(drop.denomination.minor, to: to, debit: true) }
        if drop.fromAccountID == selectedAccountID { pile.append(drop.denomination) }
        if pileMinor != Money.cashable(walletMinor) { tidyPile() }
    }

    func dismissLastDrop() {
        lastDrop = nil
    }

    // MARK: Spare change — tipping

    /// Why the tip jar will not take that piece, or nil if it will.
    func tipRefusal(for denomination: Denomination, alreadyTipped: Int) -> String? {
        if denomination.kind == .note && !spareChange.notesAllowed { return "Coins only" }
        if let cap = spareChange.tipCapMinor, alreadyTipped + denomination.minor > cap {
            return alreadyTipped + Money.smallestPiece > cap ? "Tip limit reached"
                                                             : "Over your \(Money.formatShort(minor: cap)) limit"
        }
        return nil
    }

    /// The tip jar is out while paying, at places that take tips.
    var showsTipJarWhilePaying: Bool {
        request?.acceptsTips == true && spareChange.tipWhilePaying
    }

    /// Drop a coin in the tip jar while paying. It does not count towards the
    /// bill, and is taken along with it when the payment settles.
    @discardableResult
    func tip(_ denomination: Denomination) -> Bool {
        guard showsTipJarWhilePaying,
              tipRefusal(for: denomination, alreadyTipped: tipMinor) == nil,
              takeFromPile(denomination) else { return false }
        tipPieces.append(denomination)
        return true
    }

    /// Take the last coin back out of the tip jar before the payment settles.
    func takeBackTip() {
        guard let last = tipPieces.popLast() else { return }
        pile.append(last)
    }

    /// Whether a settled payment's receipt holds the tip jar out, so some of
    /// the change can go straight back in it.
    func offersTipFromChange(_ transaction: CashTransaction) -> Bool {
        transaction.acceptsTips && spareChange.tipFromChange
            && transaction.accountID != nil && transaction.accountID == selectedAccountID
    }

    /// Drop a coin from the change in the tip jar, after the payment settled.
    @discardableResult
    func tip(_ denomination: Denomination, after transactionID: CashTransaction.ID) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == transactionID }),
              offersTipFromChange(history[index]),
              let account = history[index].accountID,
              tipRefusal(for: denomination, alreadyTipped: history[index].tipMinor) == nil,
              takeFromPile(denomination) else { return false }
        post(denomination.minor, to: account, debit: true)
        history[index].tipPieces.append(denomination)
        return true
    }

    /// Take the last tip back off a settled payment while its receipt is up.
    func takeBackTip(after transactionID: CashTransaction.ID) {
        guard let index = history.firstIndex(where: { $0.id == transactionID }),
              let account = history[index].accountID,
              let last = history[index].tipPieces.popLast() else { return }
        post(last.minor, to: account, debit: false)
        if account == selectedAccountID { pile.append(last) }
        if pileMinor != Money.cashable(walletMinor) { tidyPile() }
    }

    func transaction(_ id: CashTransaction.ID?) -> CashTransaction? {
        history.first { $0.id == id }
    }

    // MARK: Spare change — moving money

    /// One piece of this denomination out of the pile, if there is one.
    private func takeFromPile(_ denomination: Denomination) -> Bool {
        guard let index = pile.firstIndex(of: denomination) else { return false }
        pile.remove(at: index)
        return true
    }

    /// Move a balance straight away, so the pile and the figure at the top
    /// stay in step, then tell the account's bank.
    private func post(_ minor: Int, to accountID: String, debit: Bool) {
        guard minor > 0, let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].availableMinor += debit ? -minor : minor
        guard let source = owners[accountID] else { return }
        Task {
            do {
                if debit { try await source.debit(accountID: accountID, minor: minor) }
                else     { try await source.credit(accountID: accountID, minor: minor) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Demo helpers

    /// Put the demo back to its starting state.
    func reset() async {
        guard !isLive else { return }
        settlement?.cancel()
        sources = DemoBanks.sources()
        selectedAccountID = nil
        history = []
        request = nil
        tenderedMinor = 0
        tenderedPieces = []
        tipPieces = []
        lastSettlement = nil
        spareChange = SpareChangeSettings()
        drops = []
        lastDrop = nil
        await load()
    }
}
