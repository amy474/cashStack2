import XCTest

/// Drives the real gestures. The pile is a SpriteKit scene, but every piece of
/// money is an accessibility element named after its denomination, so a test
/// can pick up a particular note the same way a person would.
final class PaymentFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20),
                      "The wallet should finish loading and offer the till")
        // Let the pile fall and settle before anything is picked up.
        Thread.sleep(forTimeInterval: 2.5)
    }

    func testWalletLoadsWithCashFromEveryIncludedBank() {
        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 10))
        XCTAssertEqual(balance.label, "£143.67", "Two demo accounts should be added together")
        XCTAssertTrue(app.staticTexts["10 pieces of cash · 2 banks"].exists)
    }

    func testTheBalanceIsBrokenIntoRealNotesAndCoins() {
        // £143.67 = 2x£50 + 2x£20 + £2 + £1 + 50p + 10p + 5p + 2p
        XCTAssertEqual(money(labelled: "£50 note").count, 2)
        XCTAssertEqual(money(labelled: "£20 note").count, 2)
        XCTAssertEqual(money(labelled: "£2 coin").count, 1)
        XCTAssertEqual(money(labelled: "50p coin").count, 1)
        XCTAssertEqual(money(labelled: "2p coin").count, 1)
    }

    func testHoldingAndSwipingANoteToTheTopPaysTheMerchant() {
        startRequest(named: "Pollen Coffee")
        XCTAssertEqual(app.staticTexts["requestAmount"].label, "£4.45")

        handOver(labelled: "£20 note")

        let receipt = app.staticTexts["receiptHeadline"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 6),
                      "Swiping a note above the line should settle the payment")
        XCTAssertEqual(receipt.label, "Paid £4.45 to Pollen Coffee")
    }

    func testChangeFallsBackIntoTheWallet() {
        let twentiesBefore = money(labelled: "£20 note").count

        startRequest(named: "Pollen Coffee")
        handOver(labelled: "£20 note")
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 6))

        // £143.67 less a £4.45 coffee.
        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 6))
        XCTAssertEqual(balance.label, "£139.22", "The spend comes off the linked accounts")

        // The £20 is gone and £15.55 of change has physically arrived.
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertEqual(money(labelled: "£20 note").count, twentiesBefore - 1)
        XCTAssertEqual(money(labelled: "£10 note").count, 1, "£15.55 change includes a £10")
        XCTAssertEqual(money(labelled: "£5 note").count, 1)
        XCTAssertEqual(money(labelled: "50p coin").count, 2, "one already held, one in the change")
    }

    func testSortedViewCountsTheSameCash() {
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sortedTotal"].label, "£143.67")
        XCTAssertEqual(app.staticTexts["sortedPieces"].label, "10 pieces")
        XCTAssertTrue(app.staticTexts["section-Notes"].exists)
        XCTAssertTrue(app.staticTexts["section-Coins"].exists)
    }

    func testTidyingRebuildsThePileIntoTheFewestPieces() {
        startRequest(named: "Pollen Coffee")
        handOver(labelled: "£20 note")
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 3.0)

        app.buttons["Tidy the pile into the fewest notes and coins"].tap()
        Thread.sleep(forTimeInterval: 2.5)

        // £139.22 tidied = 2x£50 + 1x£20 + 1x£10 + 1x£5 + 2x£2 + 1x£1 + 20p + 2p
        XCTAssertEqual(money(labelled: "£50 note").count, 2)
        XCTAssertEqual(money(labelled: "£20 note").count, 1)
        XCTAssertEqual(money(labelled: "50p coin").count, 0, "tidying consolidates the loose change")
    }

    func testTurningOffAnAccountTakesItsCashOutOfTheWallet() {
        app.buttons["2 of 3"].tap()
        let thistle = app.switches["include-thistle-current"]
        XCTAssertTrue(thistle.waitForExistence(timeout: 5))

        thistle.tap()
        app.buttons["Done"].tap()

        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(balance.label, "£47.25", "Only the remaining bank's cash is in the pile")
    }

    func testLinkingAnotherBankAddsItsCashToTheSamePile() {
        app.buttons["2 of 3"].tap()
        app.buttons["Link another bank"].tap()
        XCTAssertTrue(app.staticTexts["£186.77"].waitForExistence(timeout: 10),
                      "A fourth institution's balance merges into the wallet")
        app.buttons["Done"].tap()
    }

    // MARK: Helpers

    private func money(labelled label: String) -> [XCUIElement] {
        app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
    }

    private func startRequest(named merchant: String) {
        app.buttons["Pay at till"].tap()
        let cell = app.buttons["merchant-\(merchant)"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.staticTexts["requestAmount"].waitForExistence(timeout: 5))
    }

    /// Tap and hold a piece of money, then swipe it to the top of the phone.
    private func handOver(labelled label: String) {
        let piece = money(labelled: label).first
        XCTAssertNotNil(piece, "Expected a \(label) in the pile")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        piece!.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
    }
}
