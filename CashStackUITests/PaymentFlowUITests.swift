import XCTest

/// Drives the real gestures. The pile is a SpriteKit scene, but every piece of
/// money is named after its denomination, which puts it in the accessibility
/// tree — so a test can pick up a particular note the way a person would.
final class PaymentFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]
    private var byValue: [String] { notes + coins }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20),
                      "The wallet should finish loading and offer the till")
        Thread.sleep(forTimeInterval: 2.5)   // let the pile fall and settle
    }

    // MARK: The wallet

    func testWalletLoadsWithCashFromEveryIncludedBank() {
        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 10))
        XCTAssertEqual(balance.label, "$287.65", "Two demo accounts added together")
        XCTAssertTrue(app.staticTexts["10 pieces of cash · 2 banks"].exists)
    }

    func testTheBalanceIsBrokenIntoRealAustralianCash() {
        // $287.65 = 2x$100 + $50 + $20 + $10 + $5 + $2 + 50c + 10c + 5c
        XCTAssertEqual(money("$100 note").count, 2)
        XCTAssertEqual(money("$50 note").count, 1)
        XCTAssertEqual(money("$20 note").count, 1)
        XCTAssertEqual(money("$5 note").count, 1)
        XCTAssertEqual(money("50c coin").count, 1)
        XCTAssertEqual(money("5c coin").count, 1)
        XCTAssertEqual(money("1c coin").count, 0, "Australia has no 1c piece")
        XCTAssertEqual(money("2c coin").count, 0, "Australia has no 2c piece")
    }

    // MARK: Paying

    func testTheTillRingsUpAnAmountByItself() {
        app.buttons["Pay at till"].tap()

        let asked = app.staticTexts["askedAmount"]
        XCTAssertTrue(asked.waitForExistence(timeout: 5),
                      "Tapping the till should produce an amount without the user picking one")
        let amount = cents(asked.label)
        XCTAssertGreaterThan(amount, 0)
        XCTAssertEqual(amount % 5, 0, "Cash amounts settle in 5c steps")

        // The headline figure starts at the full amount still owed.
        XCTAssertEqual(cents(app.staticTexts["outstandingAmount"].label), amount)
    }

    func testTheAmountCountsDownAsMoneyIsHandedOver() {
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)

        // Reach for a coin lying low in the pile: low enough to be clear of the
        // glass header, and small enough that it cannot cover the bill. Which
        // piece actually ends up under the finger is still down to what is
        // lying on top of what, so the assertions are about the arithmetic
        // rather than about any particular coin.
        guard let coin = lowestPiece(of: coins) else {
            return XCTFail("The wallet should have some coins in it")
        }
        handOver(coin)

        // The piece flies off the top before it registers, so wait for the
        // tally rather than sleeping a fixed amount — reading early also keeps
        // this well clear of the settle delay.
        var tendered = 0
        for _ in 0..<30 where tendered == 0 {
            guard app.staticTexts["tenderedAmount"].exists else { break }
            tendered = cents(app.staticTexts["tenderedAmount"].label)
        }
        XCTAssertGreaterThan(tendered, 0, "Money handed over is counted")

        let outstanding = cents(app.staticTexts["outstandingAmount"].label)
        if tendered < asked {
            XCTAssertEqual(outstanding, asked - tendered,
                           "The figure counts down by exactly what was handed over")
            XCTAssertLessThan(outstanding, asked, "And it is lower than it started")
        } else {
            XCTAssertLessThanOrEqual(outstanding, 0,
                                     "A piece big enough to cover the bill takes it to nothing")
        }
    }

    func testOverpayingTurnsTheAmountNegative() {
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)

        payOff()

        // Once the merchant has had more than they asked for, the figure goes
        // negative — that is the change on its way back — and holds there for a
        // beat before the payment settles.
        var sawNegative = false
        var seen = 0
        var tendered = 0
        for _ in 0..<25 where !sawNegative {
            let figure = app.staticTexts["outstandingAmount"]
            guard figure.exists else { break }
            seen = cents(figure.label)
            tendered = cents(app.staticTexts["tenderedAmount"].label)
            if seen < 0 { sawNegative = true }
        }
        XCTAssertTrue(sawNegative, "Overpaying should show the change as a negative amount")
        XCTAssertEqual(seen, asked - tendered, "The negative figure is the change due")
    }

    func testPayingSettlesAndTheChangeFallsBackIn() {
        let before = cents(app.staticTexts["walletBalance"].label)

        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)

        payOff()

        let receipt = app.staticTexts["receiptHeadline"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10),
                      "Swiping money above the line should settle the payment")

        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 6))
        XCTAssertEqual(cents(balance.label), before - asked,
                       "The spend comes off the linked accounts")

        // The change physically arrives: the pile still adds up to the balance.
        Thread.sleep(forTimeInterval: 3.5)
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(cents(app.staticTexts["sortedTotal"].label), before - asked,
                       "The cash on hand matches the new balance")
    }

    func testAskingToPayFromTheSortedViewBringsBackTheLoosePile() {
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))

        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))

        // The money has to be draggable, so the pile must be back.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(money("$100 note").isEmpty,
                       "Paying from the sorted view should switch back to the loose pile")
        payOff()
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10))
    }

    func testCancellingGivesTheMoneyBack() {
        let before = cents(app.staticTexts["walletBalance"].label)
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))

        guard let piece = lowestPiece(of: byValue) else { return XCTFail("empty wallet") }
        handOver(piece)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertGreaterThan(cents(app.staticTexts["tenderedAmount"].label), 0,
                             "Something was handed over")

        app.buttons["Cancel payment"].tap()

        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(cents(balance.label), before, "Nothing was spent")
        XCTAssertTrue(app.staticTexts["10 pieces of cash · 2 banks"].waitForExistence(timeout: 6),
                      "And every piece is back in the wallet")
    }

    // MARK: Breaking money up

    func testDoubleTappingBreaksANoteIntoSmallerMoney() {
        narrowToOneNote()

        // A $100 becomes two $50s.
        money("$100 note").first!.doubleTap()
        Thread.sleep(forTimeInterval: 1.8)
        XCTAssertEqual(money("$100 note").count, 0, "the note is gone")
        XCTAssertEqual(money("$50 note").count, 2, "and two $50s have taken its place")
        XCTAssertEqual(app.staticTexts["walletBalance"].label, "$100.25",
                       "same money, smaller pieces")
        XCTAssertTrue(app.staticTexts["4 pieces of cash · 1 bank"].waitForExistence(timeout: 4),
                      "one piece became two and nothing else was disturbed")

        // A $50 becomes two $20s and a $10.
        money("$50 note").first!.doubleTap()
        Thread.sleep(forTimeInterval: 1.8)
        XCTAssertEqual(money("$50 note").count, 1)
        XCTAssertEqual(money("$20 note").count, 2)
        XCTAssertEqual(money("$10 note").count, 1)
        XCTAssertEqual(app.staticTexts["walletBalance"].label, "$100.25")
        XCTAssertTrue(app.staticTexts["6 pieces of cash · 1 bank"].waitForExistence(timeout: 4))
    }

    /// Cut the wallet down to $100.25 — one $100 note, a 20c and a 5c — so
    /// whichever piece is under the thumb is not in doubt.
    private func narrowToOneNote() {
        app.buttons["2 of 3"].tap()
        let everyday = app.switches["include-wattle-everyday"]
        XCTAssertTrue(everyday.waitForExistence(timeout: 5))
        everyday.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["3 pieces of cash · 1 bank"].waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertEqual(money("$100 note").count, 1)
    }

    // MARK: Sorted

    func testSortedViewCountsTheSameCash() {
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sortedTotal"].label, "$287.65")
        XCTAssertEqual(app.staticTexts["sortedPieces"].label, "10 pieces")
        XCTAssertTrue(app.staticTexts["section-Notes"].exists)
        XCTAssertTrue(app.staticTexts["section-Coins"].exists)
    }

    // MARK: Accounts

    func testTurningOffAnAccountTakesItsCashOutOfTheWallet() {
        app.buttons["2 of 3"].tap()
        let everyday = app.switches["include-wattle-everyday"]
        XCTAssertTrue(everyday.waitForExistence(timeout: 5))

        everyday.tap()
        app.buttons["Done"].tap()

        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(balance.label, "$100.25", "Only the remaining bank's cash is in the pile")
    }

    func testLinkingAnotherBankAddsItsCashToTheSamePile() {
        app.buttons["2 of 3"].tap()
        app.buttons["Link another bank"].tap()
        XCTAssertTrue(app.staticTexts["$330.75"].waitForExistence(timeout: 10),
                      "A fourth institution's balance merges into the wallet")
        app.buttons["Done"].tap()
    }

    // MARK: Helpers

    private func money(_ label: String) -> [XCUIElement] {
        app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
    }

    /// "$287.65" -> 28765, "−$11.05" -> -1105
    private func cents(_ label: String) -> Int {
        let value = Int(label.filter(\.isNumber)) ?? 0
        return label.hasPrefix("−") || label.hasPrefix("-") ? -value : value
    }

    /// The piece lying lowest on screen — well clear of the glass header, where
    /// a tap would land on the chrome instead of the pile.
    private func lowestPiece(of labels: [String]) -> XCUIElement? {
        labels.flatMap { money($0) }.max { $0.frame.midY < $1.frame.midY }
    }

    /// Tap and hold a piece of money, then swipe it to the top of the phone.
    private func handOver(_ label: String) {
        let piece = money(label).first
        XCTAssertNotNil(piece, "Expected a \(label) in the pile")
        handOver(piece!)
    }

    private func handOver(_ piece: XCUIElement) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    /// Keep handing over the biggest note to hand until the bill is covered.
    private func payOff() {
        for _ in 0..<8 {
            let label = app.staticTexts["outstandingAmount"]
            guard label.exists, cents(label.label) > 0 else { return }
            guard let piece = lowestPiece(of: notes) ?? lowestPiece(of: coins) else { return }
            handOver(piece)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
}
