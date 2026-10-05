import SpriteKit

/// One physical piece of money in the pile.
final class MoneyNode: SKSpriteNode {

    let denomination: Denomination
    private(set) var isHeld = false

    private static var variantCounter = 0

    init(denomination: Denomination) {
        self.denomination = denomination
        let texture = MoneyArt.texture(for: denomination)
        super.init(texture: texture, color: .clear, size: denomination.size)

        MoneyNode.variantCounter += 1
        shader = HoloShine.shader(variant: MoneyNode.variantCounter)

        // SpriteKit surfaces a named node to the accessibility tree, so naming
        // each piece after its denomination lets the UI tests pick up a
        // particular note rather than guessing at coordinates.
        name = "\(denomination.label) \(denomination.kind == .note ? "note" : "coin")"

        zPosition = CGFloat.random(in: 1...6)

        let body: SKPhysicsBody
        switch denomination.kind {
        case .note:
            // A touch smaller than the art so notes nestle instead of hovering.
            body = SKPhysicsBody(rectangleOf: CGSize(width: denomination.size.width - 4,
                                                     height: denomination.size.height - 4))
            body.mass = 0.016
            body.restitution = 0.05
            body.linearDamping = 1.5
            body.angularDamping = 1.1
            body.friction = 0.75
        case .coin:
            body = SKPhysicsBody(circleOfRadius: denomination.size.width / 2 - 1.5)
            body.mass = 0.05
            body.restitution = 0.24
            body.linearDamping = 0.55
            body.angularDamping = 0.5
            body.friction = 0.35
        }
        body.allowsRotation = true
        body.categoryBitMask = 1
        body.collisionBitMask = 1 | 2
        body.contactTestBitMask = 0
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Grab / release

    func beginHold() {
        guard !isHeld else { return }
        isHeld = true
        physicsBody?.affectedByGravity = false
        physicsBody?.velocity = .zero
        physicsBody?.angularVelocity = 0
        zPosition = 100
        removeAction(forKey: "lift")
        run(.group([
            .scale(to: 1.14, duration: 0.14),
            .rotate(toAngle: 0, duration: 0.2, shortestUnitArc: true)
        ]), withKey: "lift")
    }

    func endHold(flick: CGVector) {
        guard isHeld else { return }
        isHeld = false
        physicsBody?.affectedByGravity = true
        physicsBody?.velocity = flick
        physicsBody?.angularVelocity = CGFloat.random(in: -2.2...2.2)
        zPosition = CGFloat.random(in: 1...6)
        removeAction(forKey: "lift")
        run(.scale(to: 1, duration: 0.16), withKey: "lift")
    }

    /// Hand it over: the money leaves the screen upward and vanishes.
    func tender(completion: @escaping () -> Void) {
        isHeld = false
        physicsBody = nil
        removeAction(forKey: "lift")
        run(.sequence([
            .group([
                .moveBy(x: 0, y: 190, duration: 0.3),
                .scale(to: 0.55, duration: 0.3),
                .fadeOut(withDuration: 0.28)
            ]),
            .removeFromParent(),
            .run(completion)
        ]))
    }

    /// Taken out of the wallet because the balance changed.
    func retire() {
        physicsBody = nil
        run(.sequence([
            .group([.scale(to: 0.3, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .removeFromParent()
        ]))
    }
}
