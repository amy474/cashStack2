import Foundation
import Testing
@testable import CashStack

/// The wallet's own bookkeeping: the pile always adds up to the selected
/// account, paying hands change back, and the jars and tip jar keep to their
/// rules. The UI tests drive the same things by hand; these check the sums.
@MainActor
@Suite("Wallet")
struct WalletStoreTests {

    private let everyday = LinkedAccount(id: "everyday", institution: .wattle, nickname: "Everyday",
                                         maskedNumber: "•••• 4417", availableMinor: 18_740)
    private let savings = LinkedAccount(id: "savings", institution: .meridian, nickname: "Savings",
                                        maskedNumber: "•••• 1180", availableMinor: 120_500)

    private func wallet() async -> WalletStore {
        let wallet = WalletStore(sources: [
            DemoBankDataSource(institution: .wattle, accounts: [everyday], latency: .zero),
            DemoBankDataSource(institution: .meridian, accounts: [savings], latency: .zero),
        ])
        await wallet.load()
        return wallet
    }

    private var paperback: PaymentRequest {
        PaymentRequest(merchant: "Paperbark Books", what: "Paperback", amountMinor: 1_495, reference: "AB0001")
    }

    private var flatWhites: PaymentRequest {
        PaymentRequest(merchant: "Pocket Coffee", what: "Two flat whites", amountMinor: 1_040, reference: "AB0002", acceptsTips: true)
    }

    // MARK: The pile

    @Test("The pile is the first account's balance, in cash")
    func pileMatchesBalance() async {
        let wallet = await wallet()
        #expect(wallet.selectedAccountID == "everyday")
        #expect(wallet.pileMinor == 18_740)
        #expect(wallet.pieceCount == 8)
    }

    @Test("Switching account swaps the pile over")
    func switching() async {
        let wallet = await wallet()
        wallet.select("savings")
        #expect(wallet.pileMinor == 120_500)
        #expect(wallet.bundles.isEmpty, "Twelve $100s stay loose")
    }

    @Test("Breaking a note up keeps the total")
    func splitting() async {
        let wallet = await wallet()
        wallet.split(.n100)
        #expect(wallet.pileMinor == 18_740)
        #expect(wallet.notes.first { $0.denomination == .n50 }?.count == 3)
    }

    // MARK: Paying

    @Test("Paying $14.95 with a $20 leaves a $5 and a 5c of change in the pile")
    func payingWithChange() async {
        let wallet = await wallet()
        wallet.beginRequest(paperback)
        wallet.tender(.n20)
        #expect(wallet.outstandingMinor == -505)
        await wallet.settle()

        #expect(wallet.walletMinor == 18_740 - 1_495)
        #expect(wallet.pileMinor == wallet.walletMinor)
        #expect(wallet.history.first?.changeMinor == 505)
        #expect(wallet.coins.first { $0.denomination == .c5 }?.count == 1)
    }

    @Test("Cancelling hands everything back")
    func cancelling() async {
        let wallet = await wallet()
        wallet.beginRequest(paperback)
        wallet.tender(.n10)
        wallet.cancelRequest()
        #expect(wallet.request == nil)
        #expect(wallet.pileMinor == 18_740)
        #expect(wallet.walletMinor == 18_740)
    }

    @Test("The account can't change mid-payment")
    func noSwitchingMidPayment() async {
        let wallet = await wallet()
        wallet.beginRequest(paperback)
        wallet.select("savings")
        #expect(wallet.selectedAccountID == "everyday")
    }

    // MARK: Jars

    @Test("Jars take coins, not notes or bundles, unless notes are allowed")
    func jarsTakeCoins() async {
        let wallet = await wallet()
        #expect(wallet.refusal(.invest, for: .c200) == nil)
        #expect(wallet.refusal(.invest, for: .n5) == "Coins only")
        #expect(wallet.refusal(.invest, for: .b1000) == "Not spare change")
        wallet.spareChange.notesAllowed = true
        #expect(wallet.refusal(.invest, for: .n5) == nil)
        #expect(wallet.refusal(.invest, for: .b1000) == "Not spare change")
    }

    @Test("The daily limit counts every jar together")
    func dailyLimit() async {
        let wallet = await wallet()
        wallet.spareChange.investment = Investment.catalogue[0]
        wallet.spareChange.dailyLimitMinor = 220
        // The pile holds a $2 and two 20c coins.
        #expect(wallet.drop(.c200, into: .invest))
        #expect(wallet.jarAllowanceLeftMinor == 20)
        #expect(wallet.refusal(.donate, for: .c50) == "Only $0.20 left today")
        #expect(wallet.drop(.c20, into: .invest))
        #expect(wallet.refusal(.invest, for: .c5) == "Daily limit reached")
        #expect(!wallet.drop(.c20, into: .invest))
    }

    @Test("Saving can't go to the account you're paying from")
    func saveJar() async {
        let wallet = await wallet()
        wallet.spareChange.savingsAccountID = "everyday"
        #expect(wallet.refusal(.save, for: .c20) == "You're paying from it")
        wallet.spareChange.savingsAccountID = "savings"
        #expect(wallet.drop(.c20, into: .save))
        #expect(wallet.walletMinor == 18_740 - 20)
        #expect(wallet.accounts.first { $0.id == "savings" }?.availableMinor == 120_500 + 20)
    }

    @Test("Taking a coin back out of a jar puts everything back")
    func undo() async throws {
        let wallet = await wallet()
        wallet.spareChange.charity = Charity.catalogue[0]
        #expect(wallet.drop(.c20, into: .donate))
        #expect(wallet.walletMinor == 18_740 - 20)
        let drop = try #require(wallet.lastDrop)
        wallet.undo(drop)
        #expect(wallet.walletMinor == 18_740)
        #expect(wallet.pileMinor == 18_740)
        #expect(wallet.drops.isEmpty)
    }

    // MARK: Tipping

    @Test("A tip goes on top of the bill, and comes back if the payment is cancelled")
    func tipping() async {
        let wallet = await wallet()
        wallet.beginRequest(flatWhites)
        #expect(wallet.tip(.c200))
        #expect(wallet.outstandingMinor == 1_040, "The figure counting down is still the bill")
        wallet.cancelRequest()
        #expect(wallet.pileMinor == 18_740)
    }

    @Test("A tip is taken with the bill")
    func tipSettles() async {
        let wallet = await wallet()
        wallet.beginRequest(flatWhites)
        #expect(wallet.tip(.c200))
        wallet.tender(.n20)
        await wallet.settle()
        #expect(wallet.walletMinor == 18_740 - 1_040 - 200)
        #expect(wallet.history.first?.tipMinor == 200)
        #expect(wallet.pileMinor == wallet.walletMinor)
    }

    @Test("Tips stop at the cap, and a café is the only place with a tip jar")
    func tipCap() async {
        let wallet = await wallet()
        #expect(wallet.tipRefusal(for: .c200, alreadyTipped: 200) == nil)
        #expect(wallet.tipRefusal(for: .c200, alreadyTipped: 400) == "Over your $5 limit")
        #expect(wallet.tipRefusal(for: .c5, alreadyTipped: 500) == "Tip limit reached")
        wallet.beginRequest(paperback)
        #expect(!wallet.showsTipJarWhilePaying)
        #expect(!wallet.tip(.c200))
    }
}
