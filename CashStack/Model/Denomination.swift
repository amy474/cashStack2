import CoreGraphics
import UIKit

enum MoneyKind {
    case note
    case coin
    /// $100 notes strapped together. Only turns up in big balances.
    case bundle
}

/// One physical denomination of money. Sizes are proportional to the real
/// Australian notes and coins so the pile reads as believable cash.
struct Denomination: Identifiable, Hashable {
    let minor: Int          // value in cents
    let kind: MoneyKind
    let label: String       // "$50", "50c"
    let face: String        // text printed on the item
    let tint: UIColor
    let size: CGSize        // points

    var id: Int { minor }

    static func == (a: Denomination, b: Denomination) -> Bool { a.minor == b.minor }
    func hash(into hasher: inout Hasher) { hasher.combine(minor) }
}

extension Denomination {

    // MARK: Notes — all the same height, each one longer than the last,
    // tinted after the real polymer notes. Sized generously: this is money you
    // are meant to grab with a thumb, so a note takes up half the screen.
    static let n100 = Denomination(minor: 10_000, kind: .note, label: "$100", face: "100",
                                   tint: UIColor(rgb: 0x00D96B), size: CGSize(width: 205, height: 94))
    static let n50  = Denomination(minor:  5_000, kind: .note, label: "$50",  face: "50",
                                   tint: UIColor(rgb: 0xFFC400), size: CGSize(width: 197, height: 94))
    static let n20  = Denomination(minor:  2_000, kind: .note, label: "$20",  face: "20",
                                   tint: UIColor(rgb: 0xFF5A36), size: CGSize(width: 189, height: 94))
    static let n10  = Denomination(minor:  1_000, kind: .note, label: "$10",  face: "10",
                                   tint: UIColor(rgb: 0x2E7BFF), size: CGSize(width: 181, height: 94))
    static let n5   = Denomination(minor:    500, kind: .note, label: "$5",   face: "5",
                                   tint: UIColor(rgb: 0xFF49C7), size: CGSize(width: 173, height: 94))

    // MARK: Coins — diameters scaled from the real thing, so the 50c is the
    // big one and the $2 is the little one, exactly as in a real pocket.
    static let c200 = Denomination(minor: 200, kind: .coin, label: "$2",  face: "$2",
                                   tint: UIColor(rgb: 0xFFB000), size: CGSize(width: 51, height: 51))
    static let c100 = Denomination(minor: 100, kind: .coin, label: "$1",  face: "$1",
                                   tint: UIColor(rgb: 0xFFD400), size: CGSize(width: 62, height: 62))
    static let c50  = Denomination(minor:  50, kind: .coin, label: "50c", face: "50c",
                                   tint: UIColor(rgb: 0x00E0C2), size: CGSize(width: 78, height: 78))
    static let c20  = Denomination(minor:  20, kind: .coin, label: "20c", face: "20c",
                                   tint: UIColor(rgb: 0xB36BFF), size: CGSize(width: 72, height: 72))
    static let c10  = Denomination(minor:  10, kind: .coin, label: "10c", face: "10c",
                                   tint: UIColor(rgb: 0x8FE1FF), size: CGSize(width: 59, height: 59))
    static let c5   = Denomination(minor:   5, kind: .coin, label: "5c",  face: "5c",
                                   tint: UIColor(rgb: 0xFF8A5B), size: CGSize(width: 49, height: 49))

    // MARK: Bundles — $100 notes strapped together, for balances too big to
    // hold as loose notes. Seen from above a bundle is the top $100 with a
    // band round it; the extra height is the edge of the stack underneath,
    // so a brick sits taller than a bundle. Both are drawn a touch narrower
    // than a loose $100, so two can lie side by side across the screen.
    static let b1000  = Denomination(minor:   100_000, kind: .bundle, label: "$1,000",  face: "1,000",
                                     tint: n100.tint, size: CGSize(width: 188, height: 94))
    static let b10000 = Denomination(minor: 1_000_000, kind: .bundle, label: "$10,000", face: "10,000",
                                     tint: n100.tint, size: CGSize(width: 188, height: 106))

    /// Highest value first — the order every breakdown is computed in.
    static let all: [Denomination] = [b10000, b1000, n100, n50, n20, n10, n5, c200, c100, c50, c20, c10, c5]

    /// Everything but the bundles: what an ordinary balance is broken into.
    static let loose: [Denomination] = all.filter { $0.kind != .bundle }

    static func named(minor: Int) -> Denomination? { all.first { $0.minor == minor } }

    /// How many $100 notes are strapped into a bundle.
    var hundreds: Int { minor / Denomination.n100.minor }

    /// What one is called: "note", "coin" or "bundle".
    var noun: String {
        switch kind {
        case .note:   "note"
        case .coin:   "coin"
        case .bundle: "bundle"
        }
    }
}

/// A count of one denomination.
struct MoneyStack: Identifiable, Hashable {
    let denomination: Denomination
    var count: Int

    var id: Int { denomination.minor }
    var subtotalMinor: Int { denomination.minor * count }
}

enum Money {

    static let currencyCode = "AUD"
    static let symbol = "$"

    /// Australia withdrew the 1c and 2c, so cash settles in 5c steps.
    static let smallestPiece = 5

    /// The part of an amount that can actually be held as cash.
    static func cashable(_ minor: Int) -> Int {
        let value = max(0, minor)
        return value - value % smallestPiece
    }

    /// Most $100 notes the pile holds loose. A balance that would need more
    /// has its thousands strapped into bundles instead, so $80,000 of savings
    /// is eight bricks rather than eight hundred notes for the physics to push
    /// around. Small balances never see a bundle.
    static let maxLooseHundreds = 15

    /// Break an amount into the fewest physical notes and coins — or, once it
    /// would take more than `maxLooseHundreds` $100s, the fewest pieces
    /// counting bundles.
    static func breakdown(ofMinor amount: Int) -> [MoneyStack] {
        let value = cashable(amount)
        let bundled = value / Denomination.n100.minor > maxLooseHundreds
        return fewest(value, from: bundled ? Denomination.all : Denomination.loose)
    }

    private static func fewest(_ amount: Int, from denominations: [Denomination]) -> [MoneyStack] {
        var remaining = amount
        var stacks: [MoneyStack] = []
        for denomination in denominations {
            let count = remaining / denomination.minor
            if count > 0 {
                stacks.append(MoneyStack(denomination: denomination, count: count))
                remaining -= count * denomination.minor
            }
        }
        return stacks
    }

    /// Most pieces the loose pile will hold. Splitting stops here, otherwise a
    /// determined thumb could turn a hundred dollars into two thousand 5c coins.
    static let maxLoosePieces = 120

    /// Break one piece of money into the fewest pieces of smaller denominations.
    /// A $10,000 brick becomes ten $1,000 bundles and a bundle ten $100s; a
    /// $100 becomes two $50s; a $50 becomes two $20s and a $10. The smallest
    /// coin there is cannot be broken down, so it comes back empty.
    static func split(_ denomination: Denomination) -> [Denomination] {
        var remaining = denomination.minor
        var pieces: [Denomination] = []
        for smaller in Denomination.all where smaller.minor < denomination.minor {
            while remaining >= smaller.minor {
                pieces.append(smaller)
                remaining -= smaller.minor
            }
        }
        return remaining == 0 ? pieces : []
    }

    /// Flat list of individual items, biggest first.
    static func items(ofMinor amount: Int) -> [Denomination] {
        breakdown(ofMinor: amount).flatMap { stack in
            Array(repeating: stack.denomination, count: stack.count)
        }
    }

    static func format(minor: Int) -> String {
        let negative = minor < 0
        let value = abs(minor)
        let dollars = value / 100
        let cents = value % 100
        let grouped = NumberFormatter.grouping.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return "\(negative ? "−" : "")\(symbol)\(grouped).\(String(format: "%02d", cents))"
    }

    /// Short form for chips: $1,284 / $12.50
    static func formatShort(minor: Int) -> String {
        minor % 100 == 0 ? format(minor: minor).replacingOccurrences(of: ".00", with: "")
                         : format(minor: minor)
    }
}

private extension NumberFormatter {
    static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()
}
