import XCTest

/// Walks the app through its main states and attaches a screenshot of each —
/// handy for App Store shots and for eyeballing the design after a change.
final class ScreenshotTests: XCTestCase {

    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]

    func testCaptureEveryScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        capture("1-loose", app)

        app.buttons["Sorted"].tap()
        Thread.sleep(forTimeInterval: 2.0)
        capture("2-sorted", app)
        app.buttons["Loose"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        // The till rings something up by itself.
        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("3-asking", app)

        // Pay some of it with a coin — the figure counts down.
        handOverLowest(of: coins, app)
        Thread.sleep(forTimeInterval: 1.2)
        capture("4-part-paid", app)

        // Overpay with a note — the figure goes negative, showing the change due.
        handOverLowest(of: notes, app)
        Thread.sleep(forTimeInterval: 0.75)
        capture("5-negative-change", app)

        Thread.sleep(forTimeInterval: 1.5)
        capture("6-receipt", app)

        // Whatever the till asked for, make sure it is paid before moving on.
        for _ in 0..<6 where app.staticTexts["outstandingAmount"].exists {
            handOverLowest(of: notes + coins, app)
            Thread.sleep(forTimeInterval: 1.5)
        }

        Thread.sleep(forTimeInterval: 3.0)
        capture("7-change-landed", app)

        let accounts = app.buttons["accountsButton"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 8))
        accounts.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("8-accounts", app)
    }

    /// Double tap breaks a piece into smaller money, right where it lay.
    func testCaptureSplit() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))

        // Switch to an account holding one $100 note so the break is easy to read.
        app.buttons["accountsButton"].tap()
        app.buttons["select-rosella-spend"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["3 pieces of cash · Rosella"].waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 3.0)
        capture("10-before-split", app)

        let note = app.otherElements
            .matching(NSPredicate(format: "label == %@", "$100 note")).firstMatch
        XCTAssertTrue(note.exists)
        note.doubleTap()
        Thread.sleep(forTimeInterval: 2.5)
        capture("11-after-split", app)
    }

    /// A big balance: $80,000 as bricks, a brick broken into bundles, the
    /// sorted view, and the change from paying for a book with a brick.
    func testCaptureBundles() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-account", "meridian-nest-egg", "-till", "Paperbark Books"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        capture("12-bricks", app)

        let brick = app.otherElements
            .matching(NSPredicate(format: "label == %@", "$10,000 bundle")).allElementsBoundByIndex
            .max(by: { $0.frame.midY < $1.frame.midY })
        brick?.doubleTap()
        Thread.sleep(forTimeInterval: 2.5)
        capture("13-brick-broken", app)

        app.buttons["Sorted"].tap()
        Thread.sleep(forTimeInterval: 2.0)
        capture("14-sorted-bundles", app)
        app.buttons["Loose"].tap()
        app.buttons["Tidy the pile into the fewest pieces"].tap()
        Thread.sleep(forTimeInterval: 3.0)

        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        handOverLowest(of: ["$10,000 bundle"], app)
        Thread.sleep(forTimeInterval: 6.0)
        capture("15-change-from-a-brick", app)
    }

    /// Catches a note in mid-air, above the pay line and behind the top glass.
    func testCaptureMidSwipe() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let pieces = notes.flatMap { label in
            app.otherElements.matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
        }
        guard let piece = pieces.max(by: { $0.frame.midY < $1.frame.midY }) else {
            return XCTFail("no notes in the pile")
        }

        let shot = expectation(description: "mid-swipe")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.2) {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "9-mid-swipe"
            image.lifetime = .keepAlways
            self.add(image)
            shot.fulfill()
        }

        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 3.0)

        wait(for: [shot], timeout: 15)
    }

    /// Spare change: the jars as a coin is held over them, the jar asking where
    /// its money goes, the undo toast, the settings, and both tip jars.
    func testCaptureCoinJars() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-till", "Pocket Coffee"]
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        capture("12-jar-hint", app)

        // Hold a coin over the invest jar and catch it there.
        let jarY = app.buttons["jarsButton"].frame.midY + 103
        let investX = 18 + (app.frame.width - 56) / 6
        let shot = expectation(description: "over-the-jar")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.4) {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "13-coin-over-jar"
            image.lifetime = .keepAlways
            self.add(image)
            shot.fulfill()
        }
        lowest(of: coins, app)?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45,
                   thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: investX, dy: jarY)),
                   withVelocity: .slow, thenHoldForDuration: 2.5)
        wait(for: [shot], timeout: 15)

        XCTAssertTrue(app.buttons["pick-OZ200"].waitForExistence(timeout: 5))
        capture("14-choose-a-fund", app)
        app.buttons["pick-OZ200"].tap()
        XCTAssertTrue(app.staticTexts["dropReceipt"].waitForExistence(timeout: 5))
        capture("15-undo-toast", app)

        app.buttons["jarsButton"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture("16-jar-settings", app)
        app.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        let tipJar = app.buttons["tipJar"]
        lowest(of: coins, app)?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: tipJar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 1.0)
        capture("17-tip-while-paying", app)

        // Hand over notes until the bill is covered and the receipt comes up.
        for _ in 0..<6 where !app.staticTexts["receiptHeadline"].exists {
            guard app.staticTexts["outstandingAmount"].exists else { break }
            handOverLowest(of: notes, app)
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10))
        capture("18-tip-from-change", app)
    }

    private func lowest(of labels: [String], _ app: XCUIApplication) -> XCUIElement? {
        labels.flatMap { label in
            app.otherElements.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        }
        .max(by: { $0.frame.midY < $1.frame.midY })
    }

    /// Swipe up whichever of these is lying lowest on screen — low enough to be
    /// clear of the glass header, where a tap would land on the chrome instead.
    private func handOverLowest(of labels: [String], _ app: XCUIApplication) {
        let pieces = labels.flatMap { label in
            app.otherElements.matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
        }
        guard let piece = pieces.max(by: { $0.frame.midY < $1.frame.midY }) else { return }
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
