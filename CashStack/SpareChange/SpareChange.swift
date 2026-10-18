import SwiftUI

/// Somewhere spare change can go when you are not paying for anything. Pick
/// up a coin and the jars appear across the top; drop it in one and it is gone
/// from the pile, the same way a coin swiped to the till is.
enum CoinJar: String, CaseIterable, Identifiable {
    case invest
    case donate
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invest: "Invest"
        case .donate: "Donate"
        case .save:   "Save"
        }
    }

    var symbol: String {
        switch self {
        case .invest: "chart.line.uptrend.xyaxis"
        case .donate: "heart"
        case .save:   "building.columns"
        }
    }

    /// Borrowed from the money itself, so each jar reads as a colour you
    /// already know from the pile: the $100 green, the $5 pink, the $10 blue.
    var tint: Color {
        switch self {
        case .invest: Color(rgb: 0x00D96B)
        case .donate: Color(rgb: 0xFF49C7)
        case .save:   Color(rgb: 0x2E7BFF)
        }
    }

    /// What an empty jar asks for before it can take anything.
    var choosePrompt: String {
        switch self {
        case .invest: "Choose a fund"
        case .donate: "Choose a charity"
        case .save:   "Choose an account"
        }
    }

    /// "50c invested in OZ200"
    func receipt(_ amount: String, _ destination: String) -> String {
        switch self {
        case .invest: "\(amount) invested in \(destination)"
        case .donate: "\(amount) donated to \(destination)"
        case .save:   "\(amount) saved to \(destination)"
        }
    }

    /// The honest version of what happens to the money next.
    var howItWorks: String {
        switch self {
        case .invest: "Coins are pooled and bought as fractional units at the next market open, so even 5c buys a sliver."
        case .donate: "Coins are pooled and sent on the 1st as one gift. Gifts of $2 or more to a registered charity are tax deductible."
        case .save:   "Moves straight across to the account you pick. Nothing is pooled."
        }
    }
}

// MARK: - Destinations

/// Something coins can buy. The names are made up, like the banks.
struct Investment: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case etf = "ETFs"
        case share = "Shares"
        var id: String { rawValue }
    }

    let ticker: String
    let name: String
    let kind: Kind
    let blurb: String

    var id: String { ticker }

    static let catalogue: [Investment] = [
        Investment(ticker: "OZ200", name: "Australia 200 ETF",   kind: .etf,   blurb: "The 200 biggest listed Australian companies"),
        Investment(ticker: "WRLD",  name: "World Shares ETF",    kind: .etf,   blurb: "About 1,500 companies across developed markets"),
        Investment(ticker: "GRNR",  name: "Clean Energy ETF",    kind: .etf,   blurb: "Renewables, batteries and the grid"),
        Investment(ticker: "TEKK",  name: "Global Tech 100 ETF", kind: .etf,   blurb: "The hundred biggest technology companies"),
        Investment(ticker: "WTL",   name: "Wattle Bank",         kind: .share, blurb: "The bank behind your Everyday account"),
        Investment(ticker: "KOOK",  name: "Kookaburra Mining",   kind: .share, blurb: "Iron ore and lithium out of the Pilbara"),
        Investment(ticker: "LYRE",  name: "Lyrebird Software",   kind: .share, blurb: "Bookkeeping software for small business"),
        Investment(ticker: "QUOL",  name: "Quoll Health",        kind: .share, blurb: "Private hospitals and day clinics")
    ]
}

struct Charity: Identifiable, Hashable {
    let id: String
    let name: String
    let cause: String

    static let catalogue: [Charity] = [
        Charity(id: "wildlife", name: "Wildlife Rescue Network", cause: "Native animals hurt in fires and floods"),
        Charity(id: "shores",   name: "Clean Shores Collective", cause: "Beaches, rivers and the reef"),
        Charity(id: "foodbank", name: "Neighbourhood Food Bank", cause: "Groceries for families who need them"),
        Charity(id: "reading",  name: "Outback Reading Fund",    cause: "Books for remote schools")
    ]
}

// MARK: - Settings

/// Everything the jars can be told. Nothing is chosen for you: each jar asks
/// where its money should go the first time a coin lands in it.
struct SpareChangeSettings: Equatable {
    var investment: Investment?
    var charity: Charity?
    var savingsAccountID: String?

    /// Jars that are switched off never appear when you pick up a coin.
    var hiddenJars: Set<CoinJar> = []

    /// Off by default: a $100 note dropped in the wrong jar is a much worse
    /// mistake than a 20c coin, and notes can be broken into coins anyway.
    var notesAllowed = false

    /// Across the invest, donate and save jars together, per calendar day.
    var dailyLimitMinor: Int? = 1_000

    /// The tip jar beside the amount while you pay, at places that take tips.
    var tipWhilePaying = true
    /// The tip jar on the receipt, for dropping in some of your change.
    var tipFromChange = true
    /// Per payment, counting everything that went in the tip jar.
    var tipCapMinor: Int? = 500

    static let dailyLimitChoices: [Int?] = [500, 1_000, 2_000, nil]
    static let tipCapChoices: [Int?] = [200, 500, 1_000, nil]
}

/// One piece of money that went in a jar.
struct JarDrop: Identifiable, Equatable {
    let id = UUID()
    let jar: CoinJar
    let denomination: Denomination
    /// "OZ200", "Wildlife Rescue Network", "Meridian Savings"
    let destination: String
    let fromAccountID: String
    /// Only saving moves money into another of your own accounts.
    let toAccountID: String?
    let date: Date

    var receipt: String { jar.receipt(denomination.label, destination) }
}
