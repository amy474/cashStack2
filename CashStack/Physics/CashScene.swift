import SpriteKit
import UIKit

/// The loose pile. Cash is simulated, lives under whatever gravity the phone
/// reports, and is dragged to the top of the screen to pay.
final class CashScene: SKScene {

    // MARK: Hooks back to SwiftUI
    var onTender: ((Denomination) -> Void)?
    var onGrab: ((Denomination) -> Void)?
    var onCrossPayLine: ((Bool) -> Void)?

    /// When false, dragging a note to the top just drops it back in the pile.
    var isPaymentActive = false { didSet { refreshPayLine() } }

    /// Distance from the top of the view down to the "hand it over" line.
    var payLineInset: CGFloat = 170 { didSet { layoutBoundaries() } }
    /// Height of the chrome at the bottom that the pile should rest on top of.
    var floorInset: CGFloat = 104 { didSet { layoutBoundaries() } }

    private(set) var gravityVector = CGVector(dx: 0, dy: -1)

    private var nodesByDenomination: [Int: [MoneyNode]] = [:]
    private var walls = SKNode()
    private var payLine = SKShapeNode()
    private var isArmed = false

    private var activeTouch: UITouch?
    private var heldNode: MoneyNode?
    private var grabOffset: CGPoint = .zero
    private var touchBegan: TimeInterval = 0
    private var lastTouchPoint: CGPoint = .zero
    private var lastTouchTime: TimeInterval = 0
    private var flick = CGVector.zero
    private let holdDelay: TimeInterval = 0.12

    private var payLineY: CGFloat { max(size.height - payLineInset, size.height * 0.5) }

    private let motion = MotionManager()

    // MARK: Lifecycle

    override init() {
        super.init(size: CGSize(width: 390, height: 700))
        backgroundColor = .white
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not supported") }

    override func didMove(to view: SKView) {
        backgroundColor = .white
        scaleMode = .resizeFill
        anchorPoint = .zero
        apply(gravity: CGVector(dx: 0, dy: -1))
        physicsWorld.speed = 1.0

        walls.name = "walls"
        addChild(walls)

        payLine.name = "payline"
        payLine.lineWidth = 1
        payLine.strokeColor = UIColor.black.withAlphaComponent(0.22)
        payLine.lineCap = .round
        payLine.zPosition = 0.5
        addChild(payLine)

        layoutBoundaries()
        Haptics.prepare()
        startMotion()
    }

    override func willMove(from view: SKView) {
        motion.stop()
    }

    private func startMotion() {
        motion.onGravity = { [weak self] gravity in self?.apply(gravity: gravity) }
        motion.onRoll = { roll in HoloShine.updateTilt(Float(sin(roll))) }
        motion.onShake = { [weak self] in self?.shuffle() }
        motion.start()

        // No motion hardware (Simulator): keep a gentle sheen moving anyway.
        if !motion.isAvailable {
            run(.repeatForever(.sequence([
                .run { HoloShine.updateTilt(Float(sin(CACurrentMediaTime() * 0.6)) * 0.9) },
                .wait(forDuration: 1.0 / 20.0)
            ])), withKey: "idleSheen")
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutBoundaries()
    }

    private func layoutBoundaries() {
        guard size.width > 1 else { return }

        // Closed left, right and bottom; the ceiling sits well above the screen
        // so change can fall in from off-screen and nothing escapes.
        // Inset a little so a tumbling note's corner does not hang off the screen.
        let margin: CGFloat = 7
        let box = CGRect(x: margin, y: floorInset,
                         width: size.width - margin * 2,
                         height: size.height - floorInset + 700)
        let body = SKPhysicsBody(edgeLoopFrom: box)
        body.friction = 0.6
        body.restitution = 0.02
        body.categoryBitMask = 2
        walls.physicsBody = body

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 22, y: payLineY))
        path.addLine(to: CGPoint(x: size.width - 22, y: payLineY))
        let dashed = path.copy(dashingWithPhase: 0, lengths: [7, 7])
        payLine.path = dashed
        refreshPayLine()
    }

    private func refreshPayLine() {
        payLine.isHidden = !isPaymentActive
        payLine.strokeColor = isArmed ? UIColor.black
                                      : UIColor.black.withAlphaComponent(0.22)
        payLine.lineWidth = isArmed ? 1.6 : 1
    }

    // MARK: Gravity

    func apply(gravity: CGVector, strength: CGFloat = 2.4) {
        gravityVector = gravity
        physicsWorld.gravity = CGVector(dx: gravity.dx * 9.8 * strength,
                                        dy: gravity.dy * 9.8 * strength)
    }

    /// A shake gives the whole pile a nudge.
    func shuffle() {
        for node in allMoney() where !node.isHeld {
            node.physicsBody?.applyImpulse(CGVector(dx: CGFloat.random(in: -1.3...1.3),
                                                    dy: CGFloat.random(in: 0.6...2.4)))
            node.physicsBody?.applyAngularImpulse(CGFloat.random(in: -0.004...0.004))
        }
    }

    // MARK: Contents

    func allMoney() -> [MoneyNode] {
        nodesByDenomination.values.flatMap { $0 }
    }

    /// Bring the pile in line with a breakdown, adding and retiring pieces as
    /// the balance moves rather than rebuilding the whole scene.
    func sync(to stacks: [MoneyStack], animated: Bool = true) {
        let wanted = Dictionary(uniqueKeysWithValues: stacks.map { ($0.denomination.minor, $0.count) })

        for denomination in Denomination.all {
            let target = wanted[denomination.minor] ?? 0
            var existing = nodesByDenomination[denomination.minor] ?? []
            existing.removeAll { $0.parent == nil }

            if existing.count > target {
                let surplus = existing.suffix(existing.count - target)
                surplus.forEach { $0.retire() }
                existing.removeLast(existing.count - target)
            } else if existing.count < target {
                for index in 0..<(target - existing.count) {
                    let node = spawn(denomination,
                                     delay: animated ? Double(index) * 0.035 : 0,
                                     fromTop: animated)
                    existing.append(node)
                }
            }
            nodesByDenomination[denomination.minor] = existing
        }
    }

    /// Change, falling down from the top of the screen.
    func dropIn(_ items: [Denomination], completion: (() -> Void)? = nil) {
        for (index, denomination) in items.enumerated() {
            let node = spawn(denomination, delay: Double(index) * 0.09, fromTop: true, splash: true)
            nodesByDenomination[denomination.minor, default: []].append(node)
        }
        if let completion {
            run(.sequence([.wait(forDuration: Double(items.count) * 0.09 + 0.3), .run(completion)]))
        }
    }

    func clear() {
        allMoney().forEach { $0.removeFromParent() }
        nodesByDenomination.removeAll()
    }

    @discardableResult
    private func spawn(_ denomination: Denomination,
                       delay: TimeInterval,
                       fromTop: Bool,
                       splash: Bool = false) -> MoneyNode {
        let node = MoneyNode(denomination: denomination)
        let margin = denomination.size.width / 2 + 10
        let x = CGFloat.random(in: margin...(max(margin + 1, size.width - margin)))
        let y = fromTop ? size.height + CGFloat.random(in: 60...260)
                        : CGFloat.random(in: (floorInset + 40)...(payLineY - 40))
        node.position = CGPoint(x: x, y: y)
        node.zRotation = CGFloat.random(in: -0.5...0.5)
        node.alpha = 0
        addChild(node)

        node.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.12)
        ]))
        if splash {
            node.physicsBody?.velocity = CGVector(dx: CGFloat.random(in: -40...40), dy: -260)
        }
        return node
    }

    // MARK: Touch — tap, hold, swipe up to pay

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        let point = touch.location(in: self)
        guard let node = topMoney(at: point) else { return }

        activeTouch = touch
        heldNode = node
        grabOffset = CGPoint(x: node.position.x - point.x, y: node.position.y - point.y)
        touchBegan = CACurrentMediaTime()
        lastTouchPoint = point
        lastTouchTime = touchBegan
        flick = .zero

        // Tap and hold: the piece lifts out of the pile after a beat.
        node.run(.sequence([
            .wait(forDuration: holdDelay),
            .run { [weak self, weak node] in
                guard let self, let node, self.heldNode === node else { return }
                node.beginHold()
                Haptics.grab()
                self.onGrab?(node.denomination)
            }
        ]), withKey: "holdTimer")
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let node = heldNode else { return }
        let point = touch.location(in: self)

        // Before the hold lands, a large movement means the user is flicking the
        // pile around rather than picking something up — honour that instead.
        if !node.isHeld {
            if CACurrentMediaTime() - touchBegan < holdDelay,
               hypot(point.x - lastTouchPoint.x, point.y - lastTouchPoint.y) > 14 {
                node.removeAction(forKey: "holdTimer")
                let dt = max(CACurrentMediaTime() - lastTouchTime, 1.0 / 120)
                node.physicsBody?.velocity = CGVector(dx: (point.x - lastTouchPoint.x) / dt,
                                                      dy: (point.y - lastTouchPoint.y) / dt)
                cancelTouch()
                return
            }
            lastTouchPoint = point
            lastTouchTime = CACurrentMediaTime()
            return
        }

        let now = CACurrentMediaTime()
        let dt = max(now - lastTouchTime, 1.0 / 120)
        flick = CGVector(dx: (point.x - lastTouchPoint.x) / dt * 0.5,
                         dy: (point.y - lastTouchPoint.y) / dt * 0.5)
        lastTouchPoint = point
        lastTouchTime = now

        node.position = CGPoint(x: point.x + grabOffset.x, y: point.y + grabOffset.y)
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0

        let armed = isPaymentActive && node.position.y > payLineY
        if armed != isArmed {
            isArmed = armed
            refreshPayLine()
            onCrossPayLine?(armed)
            Haptics.arm()
            node.removeAction(forKey: "armPulse")
            node.run(.sequence([
                .scale(to: armed ? 1.25 : 1.14, duration: 0.1)
            ]), withKey: "armPulse")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let node = heldNode else { return }
        node.removeAction(forKey: "holdTimer")

        if node.isHeld, isPaymentActive, node.position.y > payLineY {
            let denomination = node.denomination
            nodesByDenomination[denomination.minor]?.removeAll { $0 === node }
            node.tender { [weak self] in
                self?.onTender?(denomination)
            }
        } else if node.isHeld {
            node.endHold(flick: flick)
        } else {
            // A plain tap: give it a small hop so the pile feels alive.
            node.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 0.6))
            Haptics.tap()
        }

        if isArmed {
            isArmed = false
            refreshPayLine()
            onCrossPayLine?(false)
        }
        cancelTouch()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        heldNode?.removeAction(forKey: "holdTimer")
        heldNode?.endHold(flick: .zero)
        if isArmed {
            isArmed = false
            refreshPayLine()
            onCrossPayLine?(false)
        }
        cancelTouch()
    }

    private func cancelTouch() {
        activeTouch = nil
        heldNode = nil
        flick = .zero
    }

    private func topMoney(at point: CGPoint) -> MoneyNode? {
        nodes(at: point)
            .compactMap { $0 as? MoneyNode }
            .max { $0.zPosition < $1.zPosition }
    }

    // MARK: Keep the pile inside the frame

    override func update(_ currentTime: TimeInterval) {
        guard size.width > 1 else { return }
        for node in allMoney() where !node.isHeld {
            if node.position.y < floorInset - 140 || node.position.y > size.height + 1400 {
                node.position = CGPoint(x: size.width / 2, y: size.height - 60)
                node.physicsBody?.velocity = .zero
            }
        }
    }
}
