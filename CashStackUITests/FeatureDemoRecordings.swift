import XCTest
import ObjectiveC

/// Not tests so much as choreography: each one performs a single feature at a
/// person's pace, for a screen recording. `scripts/record-demos.sh` records
/// the simulator while these run and cuts each clip between the `start` and
/// `end` marks they write. Skipped unless that script is driving them.
final class FeatureDemoRecordings: XCTestCase {

    private var app: XCUIApplication!
    private let notes = ["$100 note", "$50 note", "$20 note", "$10 note", "$5 note"]
    private let coins = ["$2 coin", "$1 coin", "50c coin", "20c coin", "10c coin", "5c coin"]
    /// About the speed of an unhurried thumb, in points a second.
    private let thumb = XCUIGestureVelocity(900)

    private var markerDir: String? { ProcessInfo.processInfo.environment["DEMO_MARKERS"] }

    override func setUpWithError() throws {
        try XCTSkipIf(markerDir == nil, "Only runs while recording the demos")
        continueAfterFailure = true
        Self.skipWaitingForIdle()
    }

    /// Before every action XCUITest waits for the app to go idle, and the pile
    /// never does — it animates for as long as it's on screen — so each step
    /// would sit through a second or two of dead air. For a recording the
    /// waits go; the choreography paces itself.
    private static var skipped = false
    private static func skipWaitingForIdle() {
        guard !skipped, let process = NSClassFromString("XCUIApplicationProcess") else { return }
        skipped = true
        let one: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let two: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
        let swaps: [(String, AnyObject)] = [
            ("waitForQuiescenceIncludingAnimationsIdle:", one as AnyObject),
            ("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", two as AnyObject)
        ]
        for (name, block) in swaps {
            if let method = class_getInstanceMethod(process, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(block))
                print("demo: skipping \(name)")
            }
        }
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-showTouches", "YES", "-demoHintSeen", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["Pay at till"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3.0)   // let the pile fall and settle
    }

    // MARK: 1. Swipe to pay

    func test1SwipeToPay() {
        launch(["-till", "Paperbark Books"])
        let note = clearPoint(for: ["$20 note"]) ?? clearPoint(for: notes)!
        mark("start")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Pay at till"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        note.press(forDuration: 0.3, thenDragTo: top(), withVelocity: thumb, thenHoldForDuration: 0.25)
        // The figure goes green and negative — the change — then it settles
        // and the change falls back in.
        _ = app.staticTexts["receiptHeadline"].waitForExistence(timeout: 6)
        Thread.sleep(forTimeInterval: 1.2)
        mark("end")
    }

    // MARK: 2. Organise

    func test2Organise() {
        launch()
        mark("start")
        Thread.sleep(forTimeInterval: 1.2)
        app.buttons["Sorted"].tap()
        Thread.sleep(forTimeInterval: 2.6)
        app.buttons["Loose"].tap()
        Thread.sleep(forTimeInterval: 1.4)
        mark("end")
    }

    // MARK: 3. Split

    func test3Split() {
        launch(["-account", "rosella-spend"])
        let hundred = clearPoint(for: ["$100 note"])!
        mark("start")
        Thread.sleep(forTimeInterval: 0.6)
        hundred.doubleTap()
        Thread.sleep(forTimeInterval: 1.4)
        if let fifty = clearPoint(for: ["$50 note"]) {
            fifty.doubleTap()
        }
        Thread.sleep(forTimeInterval: 1.6)
        mark("end")
    }

    // MARK: 4. Money jars

    func test4MoneyJars() {
        launch(["-demoJars", "YES"])
        mark("start")
        // Aim before anything is picked up: the jars take the header's place.
        let jars = (0..<3).map(jar(column:))
        Thread.sleep(forTimeInterval: 0.8)
        for target in jars {
            // Each coin is found just before it's picked up: the last one
            // going in shifts the pile.
            guard let coin = clearPoint(for: coins) else { break }
            drop(coin, on: target)
            Thread.sleep(forTimeInterval: 1.6)
        }
        Thread.sleep(forTimeInterval: 0.8)
        mark("end")
        // All three coins ($2, 20c, 20c) went in: worth keeping this take.
        if app.staticTexts["walletBalance"].label == "$185.00" { mark("ok") }
    }

    // MARK: 5. Tip jar

    func test5TipJar() {
        launch(["-till", "Pocket Coffee"])
        let pile = pieces()
        let coin = clearPoint(for: ["$2 coin"], in: pile) ?? clearPoint(for: coins, in: pile)!
        let note = clearPoint(for: ["$20 note"], in: pile) ?? clearPoint(for: notes, in: pile)!
        mark("start")
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Pay at till"].tap()
        // Aim at where the tip jar sits beside the amount rather than asking
        // for it: looking it up costs a second or two on camera.
        Thread.sleep(forTimeInterval: 0.6)
        drop(coin, on: app.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.137)))
        Thread.sleep(forTimeInterval: 0.4)
        note.press(forDuration: 0.3, thenDragTo: top(), withVelocity: thumb, thenHoldForDuration: 0.3)
        _ = app.staticTexts["receiptHeadline"].waitForExistence(timeout: 6)
        Thread.sleep(forTimeInterval: 1.2)
        mark("end")
    }

    // MARK: 6. Switch accounts

    func test6SwitchAccounts() {
        launch()
        mark("start")
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["accountsButton"].tap()
        let nestEgg = app.buttons["select-meridian-nest-egg"]
        XCTAssertTrue(nestEgg.waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 0.7)
        nestEgg.tap()
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 2.4)
        mark("end")
    }

    // MARK: Helpers

    private func mark(_ name: String) {
        guard let dir = markerDir else { return }
        let line = "\(name) \(Date().timeIntervalSince1970)\n"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(self.name.split(separator: " ").last!.dropLast()).txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func top() -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
    }

    private func pieces() -> [(label: String, frame: CGRect)] {
        // One query for the whole pile: each one walks the accessibility tree.
        let labels = notes + coins + ["$1,000 bundle", "$10,000 bundle"]
        return app.otherElements.matching(NSPredicate(format: "label IN %@", labels))
            .allElementsBoundByIndex.map { ($0.label, $0.frame) }
    }

    /// A point on one of these pieces that no other piece's frame covers,
    /// lowest first — clear of the glass header, and sure to pick up that piece.
    private func clearPoint(for labels: [String], in pile: [(label: String, frame: CGRect)]? = nil,
                            skipping skip: Int = 0) -> XCUICoordinate? {
        let all = pile ?? pieces()
        let headerBottom = app.frame.height * 0.3
        let targets = all.enumerated().filter { labels.contains($0.element.label) }
            .sorted { $0.element.frame.midY > $1.element.frame.midY }
        var skipping = skip
        for (index, target) in targets {
            let others = all.enumerated().filter { $0.offset != index }.map(\.element.frame)
            let f = target.frame
            var best: CGPoint?
            for fy in stride(from: 0.8, through: 0.2, by: -0.1) {
                for fx in [0.5, 0.35, 0.65, 0.2, 0.8] {
                    let p = CGPoint(x: f.minX + f.width * fx, y: f.minY + f.height * fy)
                    if p.y > headerBottom, !others.contains(where: { $0.contains(p) }) { best = p; break }
                }
                if best != nil { break }
            }
            if best != nil, skipping > 0 { skipping -= 1; continue }
            if let best {
                return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: best.x, dy: best.y))
            }
        }
        guard let fallback = targets.first?.element.frame else { return nil }
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: fallback.midX, dy: fallback.midY))
    }

    private func jar(column: Int) -> XCUICoordinate {
        let button = app.buttons["jarsButton"].frame
        let jarWidth = (app.frame.width - 36 - 20) / 3
        let x = 18 + jarWidth / 2 + CGFloat(column) * (jarWidth + 10)
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: button.midY + 103))
    }

    private func drop(_ coin: XCUICoordinate, on target: XCUICoordinate) {
        coin.press(forDuration: 0.3, thenDragTo: target, withVelocity: thumb, thenHoldForDuration: 0.45)
    }
}
