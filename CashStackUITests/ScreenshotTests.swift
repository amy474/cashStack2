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
        Thread.sleep(forTimeInterval: 2.0)
        capture("2-sorted", app)
        app.buttons["Loose"].tap()
        Thread.sleep(forTimeInterval: 1.0)

        // The till rings something up by itself.
        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("3-asking", app)

        // Pay some of it — the figure counts down.
        handOver("$5 note", app)
        Thread.sleep(forTimeInterval: 1.2)
        capture("4-part-paid", app)

        // Overpay — the figure goes negative, showing the change due.
        handOver("$100 note", app)
        Thread.sleep(forTimeInterval: 0.75)
        capture("5-negative-change", app)

        Thread.sleep(forTimeInterval: 1.5)
        capture("6-receipt", app)
        Thread.sleep(forTimeInterval: 3.5)
        capture("7-change-landed", app)

        app.buttons["2 of 3"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture("8-accounts", app)
    }

    /// Catches a note in mid-air, above the pay line and behind the top glass.
    func testCaptureMidSwipe() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)
        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 1.5)

        let piece = app.otherElements
            .matching(NSPredicate(format: "label == %@", "$50 note")).firstMatch
        guard piece.exists else { return XCTFail("no $50 note in the pile") }

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

    private func handOver(_ label: String, _ app: XCUIApplication) {
        let piece = app.otherElements
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard piece.exists else { return }
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
