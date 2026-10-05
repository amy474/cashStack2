import SwiftUI

struct Institution: Identifiable, Hashable {
    let id: String
    let name: String
    let mark: String        // single-character mark drawn in a hairline circle
    let tint: Color
}

extension Institution {
    static let thistle = Institution(id: "thistle", name: "Thistle Bank", mark: "T", tint: Color(rgb: 0x7A3BFF))
    static let kestrel = Institution(id: "kestrel", name: "Kestrel",      mark: "K", tint: Color(rgb: 0xFF2E93))
    static let aurora  = Institution(id: "aurora",  name: "Aurora",       mark: "A", tint: Color(rgb: 0x00C2FF))
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
