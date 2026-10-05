import XCTest

/// Walks the app through its main states and attaches a screenshot of each —
/// handy for App Store shots and for eyeballing the design after a change.
final class ScreenshotTests: XCTestCase {

    func testCaptureEveryScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        capture("1-loose", app)

        app.buttons["Sorted"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("2-sorted", app)
        app.buttons["Loose"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("3-till", app)

        app.buttons["merchant-Clyde Cycles"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.0)
        capture("4-request", app)

        // £58.99: a £50 is not enough on its own, so the first swipe shows the
        // part-paid state and the second settles it.
        handOver("£50 note", app)
        Thread.sleep(forTimeInterval: 1.2)
        capture("5-part-paid", app)

        handOver("£20 note", app)
        Thread.sleep(forTimeInterval: 1.2)
        capture("6-receipt", app)
        Thread.sleep(forTimeInterval: 3.5)
        capture("7-change-landed", app)

        app.buttons["2 of 3"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("8-accounts", app)
    }

    private func handOver(_ label: String, _ app: XCUIApplication) {
        let piece = app.otherElements.matching(NSPredicate(format: "label == %@", label)).firstMatch
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
