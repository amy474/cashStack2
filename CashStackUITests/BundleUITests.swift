import XCTest

/// Big balances. The demo's Meridian Nest egg holds $80,000, which as loose
/// $100s would be eight hundred notes; the pile holds it as eight $10,000
/// bricks instead. The app is launched straight onto that account with
/// `-account meridian-nest-egg`, so the pile is nothing but bricks and any
/// piece under the thumb is a brick.
final class BundleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A bookshop: no tip jar at the top of the screen to catch a brick.
        app.launchArguments = ["-demo", "YES", "-account", "meridian-nest-egg", "-till", "Paperbark Books"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)   // let the pile fall and settle
    }

    func testABigBalanceComesAsAFewBricks() {
        XCTAssertEqual(app.staticTexts["walletBalance"].label, "$80,000.00")
        XCTAssertTrue(app.staticTexts["8 pieces of cash · Meridian"].waitForExistence(timeout: 6),
                      "Eight pieces, not eight hundred")
        XCTAssertEqual(money("$10,000 bundle").count, 8)
        XCTAssertEqual(money("$100 note").count, 0)
    }

    func testTheSortedViewListsBundlesAsTheirOwnRow() {
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["sortedTotal"].label, "$80,000.00")
        XCTAssertEqual(app.staticTexts["sortedPieces"].label, "8 pieces")
        XCTAssertTrue(app.staticTexts["section-Bundles"].exists)
        XCTAssertFalse(app.staticTexts["section-Notes"].exists)
        XCTAssertTrue(app.staticTexts["$10,000"].exists)
        XCTAssertTrue(app.staticTexts["bundle of 100 × $100"].exists)
        XCTAssertTrue(app.staticTexts["×8"].exists)
        XCTAssertFalse(app.buttons["jarMenu-$10,000"].exists, "A bundle is not spare change")
    }

    func testDoubleTappingBreaksABrickIntoBundlesAndABundleIntoNotes() {
        // A $10,000 brick becomes ten $1,000 bundles.
        guard let brick = lowest(money("$10,000 bundle")) else { return XCTFail("no bricks") }
        brick.doubleTap()
        XCTAssertTrue(app.staticTexts["17 pieces of cash · Meridian"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertEqual(money("$10,000 bundle").count, 7)
        XCTAssertEqual(money("$1,000 bundle").count, 10)
        XCTAssertEqual(app.staticTexts["walletBalance"].label, "$80,000.00", "same money, smaller pieces")

        // A $1,000 bundle becomes ten $100s. Reach for one no brick is lying
        // across, so the bundle is what the thumb lands on.
        let bricks = money("$10,000 bundle").map(\.frame)
        let clear = money("$1,000 bundle").filter { bundle in
            !bricks.contains { $0.contains(CGPoint(x: bundle.frame.midX, y: bundle.frame.midY)) }
        }
        guard let bundle = lowest(clear) else { return XCTFail("every bundle is under a brick") }
        bundle.doubleTap()
        XCTAssertTrue(app.staticTexts["26 pieces of cash · Meridian"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertEqual(money("$1,000 bundle").count, 9)
        XCTAssertEqual(money("$100 note").count, 10)
        XCTAssertEqual(app.staticTexts["walletBalance"].label, "$80,000.00")

        // Tidying straps it all back up into the fewest pieces.
        app.buttons["Tidy the pile into the fewest pieces"].tap()
        XCTAssertTrue(app.staticTexts["8 pieces of cash · Meridian"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(money("$10,000 bundle").count, 8)
        XCTAssertEqual(money("$100 note").count, 0)
    }

    func testABrickCanPayAndTheChangeComesBack() {
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)
        XCTAssertEqual(asked, 1_495)

        guard let brick = lowest(money("$10,000 bundle")) else { return XCTFail("no bricks") }
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        brick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)

        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10),
                      "A brick covers the bill and the payment settles")
        let balance = app.staticTexts["walletBalance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 6))
        XCTAssertEqual(cents(balance.label), 8_000_000 - asked)

        // $9,985.05 of change falls back in — strapped, since it is more than
        // a pocketful of $100s — and the pile still adds up to the balance.
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertEqual(money("$10,000 bundle").count, 7)
        XCTAssertEqual(money("$1,000 bundle").count, 9)
        app.buttons["Sorted"].tap()
        XCTAssertTrue(app.staticTexts["sortedTotal"].waitForExistence(timeout: 5))
        XCTAssertEqual(cents(app.staticTexts["sortedTotal"].label), 8_000_000 - asked)
    }

    // MARK: Helpers

    private func money(_ label: String) -> [XCUIElement] {
        app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
    }

    /// The piece lying lowest on screen, well clear of the glass header.
    private func lowest(_ pieces: [XCUIElement]) -> XCUIElement? {
        pieces.max { $0.frame.midY < $1.frame.midY }
    }

    /// "$287.65" -> 28765, "−$11.05" -> -1105
    private func cents(_ label: String) -> Int {
        let value = Int(label.filter(\.isNumber)) ?? 0
        return label.hasPrefix("−") || label.hasPrefix("-") ? -value : value
    }
}
