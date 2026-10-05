import CoreGraphics
import UIKit

enum MoneyKind {
    case note
    case coin
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
    // tinted after the real polymer notes.
    static let n100 = Denomination(minor: 10_000, kind: .note, label: "$100", face: "100",
                                   tint: UIColor(rgb: 0x00D96B), size: CGSize(width: 152, height: 70))
    static let n50  = Denomination(minor:  5_000, kind: .note, label: "$50",  face: "50",
                                   tint: UIColor(rgb: 0xFFC400), size: CGSize(width: 146, height: 70))
    static let n20  = Denomination(minor:  2_000, kind: .note, label: "$20",  face: "20",
                                   tint: UIColor(rgb: 0xFF5A36), size: CGSize(width: 140, height: 70))
    static let n10  = Denomination(minor:  1_000, kind: .note, label: "$10",  face: "10",
                                   tint: UIColor(rgb: 0x2E7BFF), size: CGSize(width: 134, height: 70))
    static let n5   = Denomination(minor:    500, kind: .note, label: "$5",   face: "5",
                                   tint: UIColor(rgb: 0xFF49C7), size: CGSize(width: 128, height: 70))

    // MARK: Coins — diameters scaled from the real thing, so the 50c is the
    // big one and the $2 is the little one, exactly as in a real pocket.
    static let c200 = Denomination(minor: 200, kind: .coin, label: "$2",  face: "$2",
                                   tint: UIColor(rgb: 0xFFB000), size: CGSize(width: 38, height: 38))
    static let c100 = Denomination(minor: 100, kind: .coin, label: "$1",  face: "$1",
                                   tint: UIColor(rgb: 0xFFD400), size: CGSize(width: 46, height: 46))
    static let c50  = Denomination(minor:  50, kind: .coin, label: "50c", face: "50c",
                                   tint: UIColor(rgb: 0x00E0C2), size: CGSize(width: 58, height: 58))
    static let c20  = Denomination(minor:  20, kind: .coin, label: "20c", face: "20c",
                                   tint: UIColor(rgb: 0xB36BFF), size: CGSize(width: 53, height: 53))
    static let c10  = Denomination(minor:  10, kind: .coin, label: "10c", face: "10c",
                                   tint: UIColor(rgb: 0x8FE1FF), size: CGSize(width: 44, height: 44))
    static let c5   = Denomination(minor:   5, kind: .coin, label: "5c",  face: "5c",
                                   tint: UIColor(rgb: 0xFF8A5B), size: CGSize(width: 36, height: 36))

    /// Highest value first — the order every breakdown is computed in.
    static let all: [Denomination] = [n100, n50, n20, n10, n5, c200, c100, c50, c20, c10, c5]

    static func named(minor: Int) -> Denomination? { all.first { $0.minor == minor } }
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

    /// Break an amount into the fewest physical notes and coins.
    static func breakdown(ofMinor amount: Int) -> [MoneyStack] {
        var remaining = cashable(amount)
        var stacks: [MoneyStack] = []
        for denomination in Denomination.all {
            let count = remaining / denomination.minor
            if count > 0 {
                stacks.append(MoneyStack(denomination: denomination, count: count))
                remaining -= count * denomination.minor
            }
        }
        return stacks
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
