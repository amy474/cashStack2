import XCTest

/// The policies and help are reachable before anyone signs in or connects a
/// bank, and from Accounts afterwards — App Review and the CDR both look for
/// them. The pages themselves are the server's, and its tests cover them.
final class HelpAndLegalUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAccountsLinksToHelpAndEveryPolicy() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["accountsButton"].waitForExistence(timeout: 20))
        app.buttons["accountsButton"].tap()

        for id in ["supportLink", "privacyLink", "cdrPolicyLink", "termsLink"] {
            let link = app.descendants(matching: .any)[id]
            scrollTo(link, in: app)
            XCTAssertTrue(link.exists, "Accounts should link to \(id)")
        }

        let version = app.staticTexts["appVersion"]
        scrollTo(version, in: app)
        XCTAssertTrue(version.label.hasPrefix("CashStack "), "Support asks for the version: \(version.label)")
    }

    func testSigningInMentionsTheTermsAndPrivacyPolicy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "NO"]
        app.launch()
        guard app.buttons["signInWithApple"].waitForExistence(timeout: 10) else {
            throw XCTSkip("This simulator is already signed in; uninstall CashStack to see the welcome screen.")
        }
        let agreement = app.staticTexts["agreement"]
        XCTAssertTrue(agreement.exists)
        XCTAssertTrue(agreement.label.contains("terms of use"))
        XCTAssertTrue(agreement.label.contains("privacy policy"))
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 8 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
    }
}
