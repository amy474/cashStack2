import SwiftUI

struct Institution: Identifiable, Hashable {
    let id: String
    let name: String
    let mark: String        // single-character mark drawn in a hairline circle
    let tint: Color
}

extension Institution {
    static let wattle   = Institution(id: "wattle",   name: "Wattle Bank", mark: "W", tint: Color(rgb: 0x7A3BFF))
    static let rosella  = Institution(id: "rosella",  name: "Rosella",     mark: "R", tint: Color(rgb: 0xFF2E93))
    static let meridian = Institution(id: "meridian", name: "Meridian",    mark: "M", tint: Color(rgb: 0x00C2FF))
    static let boab     = Institution(id: "boab",     name: "Boab",        mark: "B", tint: Color(rgb: 0x16DE7F))
}

/// An account the wallet has been given access to.
struct LinkedAccount: Identifiable, Hashable {
    let id: String
    let institution: Institution
    let nickname: String
    let maskedNumber: String        // "•••• 4417"
    var availableMinor: Int
    /// Whether this account's money is in the pile right now.
    var isIncluded: Bool
}

struct PaymentRequest: Identifiable, Equatable {
    let id = UUID()
    let merchant: String
    let what: String
    let amountMinor: Int
    let reference: String
}

struct CashTransaction: Identifiable {
    let id = UUID()
    let merchant: String
    let amountMinor: Int
    let tenderedMinor: Int
    let changeMinor: Int
    let date: Date
    let accounts: [String]
}
