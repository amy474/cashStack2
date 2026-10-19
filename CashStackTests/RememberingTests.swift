import Foundation
import Testing
@testable import CashStack

/// What the real wallet keeps between launches, what the demo doesn't, and
/// what the wallet says when there's nothing to pile up.
@MainActor
@Suite("Remembering and empty states")
struct RememberingTests {

    private let defaults: UserDefaults = {
        let name = "cashstack-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()

    private func account(_ id: String, _ minor: Int) -> LinkedAccount {
        LinkedAccount(id: id, institution: .wattle, nickname: id.capitalized, maskedNumber: "•••• 0001", availableMinor: minor)
    }

    private func wallet(live: Bool, _ accounts: [LinkedAccount]? = nil) async -> WalletStore {
        let wallet = WalletStore(sources: [DemoBankDataSource(institution: .wattle,
                                                              accounts: accounts ?? [account("everyday", 18_740), account("savings", 120_500)],
                                                              latency: .zero)],
                                 isLive: live, defaults: defaults)
        await wallet.load()
        return wallet
    }

    // MARK: Jar settings

    @Test("The real wallet keeps its jar settings across a relaunch")
    func liveRemembers() async {
        let first = await wallet(live: true)
        first.spareChange.investment = Investment.catalogue[1]
        first.spareChange.charity = Charity.catalogue[2]
        first.spareChange.savingsAccountID = "savings"
        first.spareChange.hiddenJars = [.donate]
        first.spareChange.notesAllowed = true
        first.spareChange.dailyLimitMinor = nil
        first.spareChange.tipCapMinor = 200
        first.coachMarkSeen = true

        let second = await wallet(live: true)
        #expect(second.spareChange == first.spareChange)
        #expect(second.spareChange.dailyLimitMinor == nil, "No limit stays no limit, not the default")
        #expect(second.coachMarkSeen)
        #expect(second.destination(of: .save) == "Wattle Bank Savings")
    }

    @Test("The demo starts fresh every time")
    func demoForgets() async {
        let first = await wallet(live: false)
        first.spareChange.investment = Investment.catalogue[0]
        first.coachMarkSeen = true

        let second = await wallet(live: false)
        #expect(second.spareChange == SpareChangeSettings())
        #expect(!second.coachMarkSeen)
    }

    @Test("A fund that no longer exists comes back unchosen, and the rest still loads")
    func unknownFund() throws {
        let data = Data(#"{"investment":"GONE","charity":"wildlife","dailyLimitMinor":500}"#.utf8)
        let settings = try #require(SpareChangeSettings(stored: data))
        #expect(settings.investment == nil)
        #expect(settings.charity?.id == "wildlife")
        #expect(settings.dailyLimitMinor == 500)
        #expect(settings.tipCapMinor == SpareChangeSettings().tipCapMinor)
    }

    @Test("Signing out forgets the jar settings along with the account")
    func signOutForgets() async {
        let wallet = await wallet(live: true)
        wallet.spareChange.investment = Investment.catalogue[0]
        wallet.coachMarkSeen = true
        Preference.clearAccount(defaults)
        #expect(defaults.data(forKey: Preference.jarSettings) == nil)
        #expect(!defaults.bool(forKey: Preference.jarCoachSeen))
    }

    @Test("What went in the jars isn't kept: it was practice on this launch's balance")
    func dropsAreNotKept() async {
        let first = await wallet(live: true)
        first.spareChange.investment = Investment.catalogue[0]
        #expect(first.drop(.c20, into: .invest))
        let second = await wallet(live: true)
        #expect(second.drops.isEmpty)
        #expect(second.walletMinor == 18_740)
    }

    // MARK: Empty pile

    @Test("An account with money shows money, not an empty state")
    func notEmpty() async {
        #expect(await wallet(live: false).emptyPileReason == nil)
    }

    @Test("Nothing, less than 5c, and overdrawn each say why the pile is empty", arguments: [
        (0, EmptyPileReason.nothing),
        (3, EmptyPileReason.underFiveCents(3)),
        (-1_230, EmptyPileReason.overdrawn(-1_230)),
    ])
    func emptyReasons(minor: Int, reason: EmptyPileReason) async {
        let wallet = await wallet(live: false, [account("bills", minor)])
        #expect(wallet.pieceCount == 0)
        #expect(wallet.emptyPileReason == reason)
    }

    @Test("The words for each")
    func emptyCopy() {
        #expect(EmptyPileReason.underFiveCents(3).detail == "$0.03 can't be held as cash: the smallest coin is 5c.")
        #expect(EmptyPileReason.overdrawn(-1_230).detail == "This account is $12.30 below zero, so there's no cash to show.")
    }
}
