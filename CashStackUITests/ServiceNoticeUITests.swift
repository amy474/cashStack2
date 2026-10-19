import XCTest

/// The server can stop an old build, or switch the app off for maintenance.
/// The app takes `-serviceNotice update|maintenance` in Debug to show either
/// without a server; the server's side is covered by its own tests.
final class ServiceNoticeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testAnOldBuildIsStoppedEvenInTheDemo() {
        let app = launch(["-demo", "YES", "-serviceNotice", "update"])
        let title = app.staticTexts["serviceNoticeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Time to update")
        XCTAssertTrue(app.buttons["updateApp"].exists, "There's somewhere to go to update")
        XCTAssertFalse(app.buttons["Pay at till"].exists, "Nothing behind it can be reached")
    }

    func testMaintenanceSaysWhyAndOffersTheDemo() {
        let app = launch(["-demo", "NO", "-serviceNotice", "maintenance"])
        let title = app.staticTexts["serviceNoticeTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Back soon")
        XCTAssertEqual(app.staticTexts["serviceNoticeMessage"].label, "We're upgrading CashStack. Back by 9pm.")
        XCTAssertTrue(app.buttons["retryService"].exists)
        XCTAssertTrue(app.buttons["Try it with pretend money"].exists)
    }

    func testTheDemoCarriesOnThroughMaintenance() {
        let app = launch(["-demo", "YES", "-serviceNotice", "maintenance"])
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Pay at till"].isHittable)
        XCTAssertFalse(app.staticTexts["serviceNoticeTitle"].exists)
    }
}
