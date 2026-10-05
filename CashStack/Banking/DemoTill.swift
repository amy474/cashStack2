import Foundation

/// The merchant side. In a shipped build a request arrives over NFC, a QR code
/// or a payment link; here the till has a short menu and rings one up at random
/// when the user taps "Pay at till".
enum DemoTill {

    struct Item {
        let merchant: String
        let what: String
        let amountMinor: Int
    }

    /// Every amount is a multiple of 5c — Australia settles cash in 5c steps,
    /// so anything else could not be paid or given back as change.
    static let menu: [Item] = [
        Item(merchant: "Pocket Coffee",    what: "Two flat whites",      amountMinor: 1_040),
        Item(merchant: "Paperbark Books",  what: "Paperback",            amountMinor: 1_495),
        Item(merchant: "Rozelle Hardware", what: "Timber and screws",    amountMinor: 2_340),
        Item(merchant: "Lane Grocer",      what: "Weekly shop",          amountMinor: 1_765),
        Item(merchant: "Harbour Cycles",   what: "Tyres fitted",         amountMinor: 5_895),
        Item(merchant: "Riverside Deli",   what: "Lunch",                amountMinor:   825)
    ]

    static func ringUp() -> PaymentRequest {
        let item = menu.randomElement()!
        return PaymentRequest(merchant: item.merchant,
                              what: item.what,
                              amountMinor: item.amountMinor,
                              reference: reference())
    }

    private static func reference() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0..<2).map { _ in letters.randomElement()! })
             + String(format: "%04d", Int.random(in: 0...9999))
    }
}
