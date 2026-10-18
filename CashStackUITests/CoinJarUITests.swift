import XCTest

/// Spare change: coins dropped into the invest, donate and save jars, and into
/// the tip jar while paying. As with paying, which coin ends up under the
/// thumb is down to how the pile settled, so these assert the arithmetic —
/// whatever went in came off the balance — rather than naming a coin. And
/// since a note lying across a coin gets picked up instead (and turned away
/// by the jar), a drop that does not land is tried again with the next coin.
final class CoinJarUITests: XCTestCase {

    private var app: XCUIApplication!

    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Pin the till to a café, so there is always a tip jar.
        app.launchArguments = ["-till", "Pocket Coffee"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)   // let the pile fall and settle
    }

    // MARK: Jars

    func testAnEmptyJarAsksWhereTheMoneyGoesThenTakesTheCoin() {
        let before = balance()
        let fund = app.buttons["pick-OZ200"]
        XCTAssertTrue(dropACoin(on: jar(column: 0)) { fund.waitForExistence(timeout: 3) },
                      "The invest jar has no fund yet, so dropping a coin in asks for one")
        fund.tap()

        let receipt = app.staticTexts["dropReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.label.hasSuffix("invested in OZ200"), receipt.label)
        let value = pieceValue(receipt.label)
        XCTAssertGreaterThan(value, 0)
        XCTAssertEqual(balance(), before - value, "The coin came off the balance")

        app.buttons["undoDrop"].tap()
        XCTAssertEqual(balance(), before, "Undo puts it back")
    }

    func testOnceAJarKnowsWhereToSendMoneyACoinGoesStraightIn() {
        let before = balance()
        let charity = app.buttons["pick-wildlife"]
        XCTAssertTrue(dropACoin(on: jar(column: 1)) { charity.waitForExistence(timeout: 3) })
        charity.tap()
        XCTAssertTrue(app.staticTexts["dropReceipt"].waitForExistence(timeout: 5))
        let firstValue = pieceValue(app.staticTexts["dropReceipt"].label)
        let afterFirst = balance()
        XCTAssertEqual(afterFirst, before - firstValue)
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(dropACoin(on: jar(column: 1)) { balanceFalls(below: afterFirst) },
                      "The second coin goes straight in")
        XCTAssertFalse(charity.exists, "without asking again")
        let receipt = app.staticTexts["dropReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.label.hasSuffix("donated to Wildlife Rescue Network"), receipt.label)
        XCTAssertEqual(balance(), before - firstValue - pieceValue(receipt.label))
    }

    func testNotesStayOutOfTheJarsUnlessAllowed() {
        let before = balance()
        // A note with no coin lying on it, so the thumb really does pick up a note.
        let coinFrames = coins.flatMap { money($0) }.map(\.frame)
        guard let note = notes.flatMap({ money($0) })
            .filter({ note in !coinFrames.contains { $0.contains(CGPoint(x: note.frame.midX, y: note.frame.midY)) } })
            .max(by: { $0.frame.midY < $1.frame.midY }) else { return XCTFail("no notes") }
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: jar(column: 0), withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertFalse(app.buttons["pick-OZ200"].waitForExistence(timeout: 2),
                       "A note is not offered the jars")
        XCTAssertEqual(balance(), before, "and nothing moved")
    }

    /// The sorted view's menu does the same thing without any dragging.
    func testTheSortedViewCanSaveACoinWithoutDragging() {
        app.buttons["Sorted"].tap()
        let menu = app.buttons["jarMenu-20c"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()

        let savings = app.buttons["pick-meridian-saver"]
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pick-wattle-everyday"].exists,
                       "The account the wallet is paying from is not offered")
        savings.tap()

        let receipt = app.staticTexts["dropReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertEqual(receipt.label, "20c saved to Meridian Savings")
        XCTAssertEqual(app.staticTexts["sortedTotal"].label, "$187.20")

        // Saving moves money between your own accounts: it lands in Meridian.
        app.buttons["accountsButton"].tap()
        let meridian = app.buttons["select-meridian-saver"]
        XCTAssertTrue(meridian.waitForExistence(timeout: 5))
        XCTAssertTrue(meridian.label.contains("$1,205.20"), meridian.label)
    }

    // MARK: Tipping

    func testATipGoesOnTopOfTheBill() {
        let before = balance()
        app.buttons["Pay at till"].tap()
        let jar = app.buttons["tipJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 5), "A café puts a tip jar out")
        let asked = cents(app.staticTexts["askedAmount"].label)

        XCTAssertTrue(dropACoin(on: middle(of: jar)) { label(of: jar) { $0.contains("in it") } },
                      "A coin dropped on the tip jar goes in it")
        let tip = cents(jar.label)
        XCTAssertGreaterThan(tip, 0)
        XCTAssertEqual(cents(app.staticTexts["outstandingAmount"].label), asked,
                       "The tip does not count towards the bill")

        payOff()
        let detail = app.staticTexts["receiptDetail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue(detail.label.hasSuffix("tip"), detail.label)
        XCTAssertEqual(balance(), before - asked - tip, "The bill and the tip both came off")
    }

    func testSomeOfTheChangeCanGoInTheTipJar() {
        let before = balance()
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["askedAmount"].waitForExistence(timeout: 5))
        let asked = cents(app.staticTexts["askedAmount"].label)
        payOff()

        // The receipt holds the tip jar out while the change lands.
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10))
        let jar = app.buttons["tipJar"]
        XCTAssertTrue(jar.waitForExistence(timeout: 3))
        // Let the change land first, or the thumb reaches for a coin mid-fall.
        // Holding a coin pauses the receipt, so there is time.
        Thread.sleep(forTimeInterval: 2.0)

        let detail = app.staticTexts["receiptDetail"]
        XCTAssertTrue(dropACoin(on: middle(of: jar)) { label(of: detail) { $0.hasSuffix("tip") } },
                      "A coin from the change goes in the receipt's tip jar")
        let tip = cents(String(detail.label.split(separator: "·").last ?? ""))
        XCTAssertGreaterThan(tip, 0)
        XCTAssertEqual(balance(), before - asked - tip)
    }

    // MARK: Helpers

    /// The wallet header comes back once the jars have stepped aside.
    private func balance() -> Int {
        let figure = app.staticTexts["walletBalance"]
        XCTAssertTrue(figure.waitForExistence(timeout: 6))
        return cents(figure.label)
    }

    /// Where one of the jars will be. They only appear once something is held,
    /// so aim by the header's layout: a row of three, their middles about
    /// 103pt below the Jars button's.
    private func jar(column: Int) -> XCUICoordinate {
        let button = app.buttons["jarsButton"].frame
        let jarWidth = (app.frame.width - 36 - 20) / 3
        let x = 18 + jarWidth / 2 + CGFloat(column) * (jarWidth + 10)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: button.midY + 103))
    }

    private func middle(of element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// Hold a coin, drag it to the target and let go — then, if it did not
    /// land, try the next coin. Coins with no note across them go first,
    /// lowest first, clear of the glass header.
    private func dropACoin(on target: @autoclosure () -> XCUICoordinate, until landed: () -> Bool) -> Bool {
        for attempt in 0..<4 {
            let noteFrames = notes.flatMap { money($0) }.map(\.frame)
            let all = coins.flatMap { money($0) }.sorted { $0.frame.midY > $1.frame.midY }
            let covered: (XCUIElement) -> Bool = { coin in
                noteFrames.contains { $0.contains(CGPoint(x: coin.frame.midX, y: coin.frame.midY)) }
            }
            let candidates = all.filter { !covered($0) } + all.filter(covered)
            guard !candidates.isEmpty else { return false }
            candidates[attempt % candidates.count].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.45, thenDragTo: target(), withVelocity: .slow, thenHoldForDuration: 0.5)
            if landed() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Poll an element's label for a few seconds.
    private func label(of element: XCUIElement, _ matches: (String) -> Bool) -> Bool {
        for _ in 0..<12 {
            if element.exists, matches(element.label) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func balanceFalls(below minor: Int) -> Bool {
        for _ in 0..<12 {
            let figure = app.staticTexts["walletBalance"]
            if figure.exists, cents(figure.label) < minor { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func money(_ label: String) -> [XCUIElement] {
        app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
    }

    private func lowestPiece(of labels: [String]) -> XCUIElement? {
        labels.flatMap { money($0) }.max { $0.frame.midY < $1.frame.midY }
    }

    /// Keep handing over the biggest note to hand until the bill is covered.
    private func payOff() {
        for _ in 0..<8 {
            let label = app.staticTexts["outstandingAmount"]
            guard label.exists, cents(label.label) > 0 else { return }
            guard let piece = lowestPiece(of: notes) ?? lowestPiece(of: coins) else { return }
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    /// "$287.65" -> 28765
    private func cents(_ label: String) -> Int {
        Int(label.filter(\.isNumber)) ?? 0
    }

    /// The value of the piece named at the start of a line: "50c …" or "$2 …".
    private func pieceValue(_ line: String) -> Int {
        let word = String(line.prefix { $0 != " " })
        let digits = Int(word.filter(\.isNumber)) ?? 0
        return word.hasSuffix("c") ? digits : digits * 100
    }
}
