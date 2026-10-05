import CoreGraphics
import UIKit

enum MoneyKind {
    case note
    case coin
}

/// One physical denomination of money. Sizes are proportional to real
/// sterling notes and coins so the pile reads as believable cash.
struct Denomination: Identifiable, Hashable {
    let minor: Int          // value in pence
    let kind: MoneyKind
    let label: String       // "£50", "50p"
    let face: String        // text printed on the item
    let tint: UIColor
    let size: CGSize        // points

    var id: Int { minor }

    static func == (a: Denomination, b: Denomination) -> Bool { a.minor == b.minor }
    func hash(into hasher: inout Hasher) { hasher.combine(minor) }
}

extension Denomination {

    // MARK: Notes
    static let n50 = Denomination(minor: 5000, kind: .note, label: "£50", face: "50",
                                  tint: UIColor(rgb: 0xFF2E93), size: CGSize(width: 152, height: 80))
    static let n20 = Denomination(minor: 2000, kind: .note, label: "£20", face: "20",
                                  tint: UIColor(rgb: 0x7A3BFF), size: CGSize(width: 144, height: 76))
    static let n10 = Denomination(minor: 1000, kind: .note, label: "£10", face: "10",
                                  tint: UIColor(rgb: 0x00C2FF), size: CGSize(width: 136, height: 72))
    static let n5  = Denomination(minor:  500, kind: .note, label: "£5",  face: "5",
                                  tint: UIColor(rgb: 0x16DE7F), size: CGSize(width: 128, height: 68))

    // MARK: Coins — diameters scaled from the real thing
    static let c200 = Denomination(minor: 200, kind: .coin, label: "£2",  face: "£2",
                                   tint: UIColor(rgb: 0xFFB000), size: CGSize(width: 56, height: 56))
    static let c100 = Denomination(minor: 100, kind: .coin, label: "£1",  face: "£1",
                                   tint: UIColor(rgb: 0xFFD400), size: CGSize(width: 46, height: 46))
    static let c50  = Denomination(minor:  50, kind: .coin, label: "50p", face: "50p",
                                   tint: UIColor(rgb: 0xFF6B3D), size: CGSize(width: 54, height: 54))
    static let c20  = Denomination(minor:  20, kind: .coin, label: "20p", face: "20p",
                                   tint: UIColor(rgb: 0x3C7BFF), size: CGSize(width: 42, height: 42))
    static let c10  = Denomination(minor:  10, kind: .coin, label: "10p", face: "10p",
                                   tint: UIColor(rgb: 0x00E0C2), size: CGSize(width: 48, height: 48))
    static let c5   = Denomination(minor:   5, kind: .coin, label: "5p",  face: "5p",
                                   tint: UIColor(rgb: 0xB36BFF), size: CGSize(width: 36, height: 36))
    static let c2   = Denomination(minor:   2, kind: .coin, label: "2p",  face: "2p",
                                   tint: UIColor(rgb: 0xFF8A5B), size: CGSize(width: 50, height: 50))
    static let c1   = Denomination(minor:   1, kind: .coin, label: "1p",  face: "1p",
                                   tint: UIColor(rgb: 0x8FE1FF), size: CGSize(width: 40, height: 40))

    /// Highest value first — the order every breakdown is computed in.
    static let all: [Denomination] = [n50, n20, n10, n5, c200, c100, c50, c20, c10, c5, c2, c1]

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

    /// Break an amount into the fewest physical notes and coins.
    static func breakdown(ofMinor amount: Int) -> [MoneyStack] {
        var remaining = max(0, amount)
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
        let pounds = value / 100
        let pence = value % 100
        let grouped = NumberFormatter.grouping.string(from: NSNumber(value: pounds)) ?? "\(pounds)"
        return "\(negative ? "−" : "")£\(grouped).\(String(format: "%02d", pence))"
    }

    /// Short form for chips: £1,284 / £12.50
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
