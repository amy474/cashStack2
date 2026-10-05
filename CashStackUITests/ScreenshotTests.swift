import XCTest

/// Walks the app through its main states and attaches a screenshot of each —
/// handy for App Store shots and for eyeballing the design after a change.
final class ScreenshotTests: XCTestCase {

    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]

    func testCaptureEveryScreen() {
        let app = XCUIApplication()
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

        let accounts = app.buttons["2 of 3"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 8))
        accounts.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("8-accounts", app)
    }

    /// Double tap breaks a piece into smaller money, right where it lay.
    func testCaptureSplit() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))

        // Narrow the wallet to one $100 note so the break is easy to read.
        app.buttons["2 of 3"].tap()
        app.switches["include-wattle-everyday"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["3 pieces of cash · 1 bank"].waitForExistence(timeout: 6))
        Thread.sleep(forTimeInterval: 3.0)
        capture("10-before-split", app)

        let note = app.otherElements
            .matching(NSPredicate(format: "label == %@", "$100 note")).firstMatch
        XCTAssertTrue(note.exists)
        note.doubleTap()
        Thread.sleep(forTimeInterval: 2.5)
        capture("11-after-split", app)
    }

    /// Catches a note in mid-air, above the pay line and behind the top glass.
    func testCaptureMidSwipe() {
        let app = XCUIApplication()
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
