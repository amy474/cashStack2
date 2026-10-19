import Testing
@testable import CashStack

/// The breakdown maths: what a balance looks like as cash.
@Suite("Money")
struct MoneyTests {

    private func counts(_ stacks: [MoneyStack]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: stacks.map { ($0.denomination.label, $0.count) })
    }

    @Test("A balance breaks into the fewest Australian notes and coins")
    func fewestPieces() {
        #expect(counts(Money.breakdown(ofMinor: 18_740)) == ["$100": 1, "$50": 1, "$20": 1, "$10": 1, "$5": 1, "$2": 1, "20c": 2])
    }

    @Test("Cash settles in 5c steps, since the 1c and 2c are gone", arguments: [
        (18_742, 18_740), (18_744, 18_740), (18_745, 18_745), (4, 0), (-500, 0),
    ])
    func cashable(amount: Int, expected: Int) {
        #expect(Money.cashable(amount) == expected)
        #expect(Money.breakdown(ofMinor: amount).reduce(0) { $0 + $1.subtotalMinor } == expected)
    }

    @Test("Up to fifteen $100s stay loose")
    func fifteenHundredsStayLoose() {
        #expect(counts(Money.breakdown(ofMinor: 150_000)) == ["$100": 15])
    }

    @Test("Past fifteen $100s, the thousands come strapped")
    func bundles() {
        #expect(counts(Money.breakdown(ofMinor: 160_000)) == ["$1,000": 1, "$100": 6])
        #expect(counts(Money.breakdown(ofMinor: 8_000_000)) == ["$10,000": 8])
        #expect(counts(Money.breakdown(ofMinor: 8_765_430)) == ["$10,000": 8, "$1,000": 7, "$100": 6, "$50": 1, "$2": 2, "20c": 1, "10c": 1])
    }

    @Test("Breaking a piece up keeps its value", arguments: Denomination.all.map(\.minor))
    func splitKeepsValue(minor: Int) throws {
        let denomination = try #require(Denomination.named(minor: minor))
        let pieces = Money.split(denomination)
        if denomination == .c5 {
            #expect(pieces.isEmpty, "The 5c has nothing smaller to become")
        } else {
            #expect(!pieces.isEmpty)
            #expect(pieces.reduce(0) { $0 + $1.minor } == denomination.minor)
            #expect(pieces.allSatisfy { $0.minor < denomination.minor })
        }
    }

    @Test("Each piece breaks into the next sizes down")
    func splitShapes() {
        #expect(Money.split(.b10000) == Array(repeating: .b1000, count: 10))
        #expect(Money.split(.b1000) == Array(repeating: .n100, count: 10))
        #expect(Money.split(.n100) == [.n50, .n50])
        #expect(Money.split(.n50) == [.n20, .n20, .n10])
    }

    @Test("Amounts read the Australian way")
    func formatting() {
        #expect(Money.format(minor: 18_740) == "$187.40")
        #expect(Money.format(minor: 128_405) == "$1,284.05")
        #expect(Money.format(minor: -505) == "−$5.05")
        #expect(Money.formatShort(minor: 128_400) == "$1,284")
        #expect(Money.formatShort(minor: 1_250) == "$12.50")
    }
}
