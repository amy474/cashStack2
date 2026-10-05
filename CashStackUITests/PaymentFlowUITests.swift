import XCTest

/// Drives the real gestures. The pile is a SpriteKit scene, but every piece of
/// money is named after its denomination, which puts it in the accessibility
/// tree — so a test can pick up a particular note the way a person would.
final class PaymentFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Biggest first — what the tests reach for when handing money over.
    private let byValue = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note",
                           "$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]

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

        // Hand over the smallest piece there is, so the bill is nowhere near covered.
        guard let smallest = byValue.reversed().first(where: { !money($0).isEmpty }) else {
            return XCTFail("The wallet should have some coins in it")
        }
        handOver(smallest)
        Thread.sleep(forTimeInterval: 1.0)

        let outstanding = cents(app.staticTexts["outstandingAmount"].label)
        let tendered = cents(app.staticTexts["tenderedAmount"].label)
        XCTAssertGreaterThan(tendered, 0, "Money handed over is counted")
        XCTAssertEqual(outstanding, asked - tendered, "The amount owed counts down")
        XCTAssertGreaterThan(outstanding, 0, "A single coin should not cover the bill")
    }

    func testOverpayingTurnsTheAmountNegative() {
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)

        // A $100 note covers anything on the till's menu.
        handOver("$100 note")

        // The figure goes negative — that is the change on its way back — and
        // holds there for a beat before the payment settles.
        var sawNegative = false
        var seen = 0
        for _ in 0..<25 where !sawNegative {
            let label = app.staticTexts["outstandingAmount"]
            guard label.exists else { break }
            seen = cents(label.label)
            if seen < 0 { sawNegative = true }
        }
        XCTAssertTrue(sawNegative, "Overpaying should show the change as a negative amount")
        XCTAssertEqual(seen, asked - 10_000, "Negative figure equals the change due")
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
        handOver("$100 note")
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10))
    }

    func testCancellingGivesTheMoneyBack() {
        let before = cents(app.staticTexts["walletBalance"].label)
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))

        handOver("$5 note")
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Cancel payment"].tap()

        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(cents(balance.label), before, "Nothing was spent")
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertFalse(money("$5 note").isEmpty, "The note handed over comes back")
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

    /// Tap and hold a piece of money, then swipe it to the top of the phone.
    private func handOver(_ label: String) {
        let piece = money(label).first
        XCTAssertNotNil(piece, "Expected a \(label) in the pile")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        piece!.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    /// Keep handing over the biggest note to hand until the bill is covered.
    private func payOff() {
        for _ in 0..<8 {
            let label = app.staticTexts["outstandingAmount"]
            guard label.exists, cents(label.label) > 0 else { return }
            guard let piece = byValue.first(where: { !money($0).isEmpty }) else { return }
            handOver(piece)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
}
