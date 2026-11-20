import XCTest

/// Everything that floats under the header — the jar hint, an error, the undo
/// toast after a drop, and the receipt after paying — sits the same 24pt below
/// it, whichever phone it is on.
final class BannerPlacementUITests: XCTestCase {

    private var app: XCUIApplication!

    private let gap: CGFloat = 24
    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testTheJarHintSitsUnderTheHeader() {
        launch()
        XCTAssertTrue(app.staticTexts["Your coins can do more"].waitForExistence(timeout: 10))
        assertBannerSitsUnderTheHeader("jar hint")
    }

    func testAnErrorSitsUnderTheHeader() {
        // No apostrophes: launch arguments are read as a property list.
        launch("-demoError", "Wattle Bank is not answering right now.")
        XCTAssertTrue(app.buttons["Wattle Bank is not answering right now."].waitForExistence(timeout: 10))
        assertBannerSitsUnderTheHeader("error")
    }

    func testTheUndoToastSitsUnderTheHeader() {
        launch()
        app.buttons["Sorted"].tap()
        let menu = app.buttons["jarMenu-20c"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let save = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Save")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        let savings = app.buttons["pick-meridian-saver"]
        XCTAssertTrue(savings.waitForExistence(timeout: 5))
        savings.tap()

        XCTAssertTrue(app.staticTexts["dropReceipt"].waitForExistence(timeout: 5))
        assertBannerSitsUnderTheHeader("undo toast")
    }

    func testTheReceiptSitsUnderTheHeader() {
        launch()
        app.buttons["Pay at till"].tap()
        XCTAssertTrue(app.staticTexts["outstandingAmount"].waitForExistence(timeout: 5))
        payOff()
        XCTAssertTrue(app.staticTexts["receiptHeadline"].waitForExistence(timeout: 10))
        assertBannerSitsUnderTheHeader("receipt")
    }

    // MARK: Helpers

    private func launch(_ extra: String...) {
        app.launchArguments = ["-demo", "YES", "-jarCoachSeen", "NO"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2.0)   // let the pile fall and settle
    }

    /// From the header's hairline rule to the card's top edge. The card's frame
    /// is its own, but the header's only covers what is inside it, not the
    /// glass, so the rule is found on the screen itself.
    private func assertBannerSitsUnderTheHeader(_ what: String,
                                                file: StaticString = #filePath, line: UInt = #line) {
        // Let it finish sliding in before measuring.
        Thread.sleep(forTimeInterval: 0.6)
        let header = app.otherElements["header"].frame
        let banner = app.otherElements["banner"].frame
        XCTAssertFalse(header.isEmpty, "No header on screen", file: file, line: line)
        XCTAssertFalse(banner.isEmpty, "No \(what) on screen", file: file, line: line)

        let screen = Pixels(XCUIScreen.main.screenshot().image, width: app.frame.width)
        // The rule runs the full width, so look for it at the very edge, where
        // no card reaches.
        guard let ruleTop = screen.firstDark(x: 3, from: header.maxY, to: header.maxY + 40) else {
            return XCTFail("Couldn't find the header's rule", file: file, line: line)
        }
        let ruleBottom = screen.lastDark(x: 3, from: ruleTop)
        XCTAssertEqual(banner.minY - ruleBottom, gap, accuracy: 1,
                       "The \(what) should sit \(gap)pt under the header", file: file, line: line)
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
            guard label.exists, Int(label.label.filter(\.isNumber)) ?? 0 > 0,
                  !label.label.hasPrefix("−") else { return }
            guard let piece = lowestPiece(of: notes) ?? lowestPiece(of: coins) else { return }
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.45, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
}

/// A screenshot read in points.
private struct Pixels {
    private let data: [UInt8]
    private let bytesPerRow: Int
    private let scale: CGFloat
    private let height: Int

    init(_ image: UIImage, width points: CGFloat) {
        let cg = image.cgImage!
        scale = CGFloat(cg.width) / points
        height = cg.height
        bytesPerRow = cg.width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * cg.height)
        let context = CGContext(data: &buffer, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        data = buffer
    }

    /// Ink, as opposed to glass, card or paper.
    private func isDark(x: CGFloat, row: Int) -> Bool {
        guard row >= 0, row < height else { return false }
        let i = row * bytesPerRow + Int(x * scale) * 4
        return Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2]) < 255
    }

    /// The top of the first inked row between two heights.
    func firstDark(x: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat? {
        for row in Int(start * scale)...Int(end * scale) where isDark(x: x, row: row) {
            return CGFloat(row) / scale
        }
        return nil
    }

    /// The bottom of a line of ink that starts at `start`.
    func lastDark(x: CGFloat, from start: CGFloat) -> CGFloat {
        var row = Int(start * scale)
        while isDark(x: x, row: row + 1) { row += 1 }
        return CGFloat(row + 1) / scale
    }
}
