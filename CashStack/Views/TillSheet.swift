import SwiftUI

/// Stands in for the merchant's terminal. In a shipped build this is where the
/// request would arrive from — a QR code, NFC tap, or a payment link.
struct TillSheet: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss

    @State private var custom = ""

    private var customMinor: Int { Int(custom) ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Pick what the till is asking for")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(Array(DemoBanks.merchants.enumerated()), id: \.offset) { _, entry in
                            Button {
                                start(merchant: entry.0, minor: entry.1)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.0)
                                            .font(Theme.title(16))
                                            .foregroundStyle(Theme.ink)
                                        Text("card machine")
                                            .font(Theme.body(11))
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                    Spacer()
                                    Text(Money.format(minor: entry.1))
                                        .font(Theme.title(17))
                                        .foregroundStyle(Theme.ink)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                // Without this the gap the Spacer leaves is not
                                // tappable, so the middle of the row does nothing.
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("merchant-\(entry.0)")
                            Hairline().opacity(0.12)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("OR TYPE AN AMOUNT")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .kerning(2)
                                .foregroundStyle(Theme.inkSoft)

                            HStack(spacing: 12) {
                                Text(Money.format(minor: customMinor))
                                    .font(Theme.display(30))
                                    .foregroundStyle(customMinor > 0 ? Theme.ink : Theme.inkFaint)
                                    .monospacedDigit()
                                Spacer()
                            }

                            Keypad(value: $custom)

                            PrimaryPillButton(title: "Ask for \(Money.format(minor: customMinor))",
                                              systemImage: "wave.3.right") {
                                start(merchant: "Counter", minor: customMinor)
                            }
                            .opacity(customMinor > 0 ? 1 : 0.35)
                            .disabled(customMinor == 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Theme.ground)
            .navigationTitle("Till")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func start(merchant: String, minor: Int) {
        guard minor > 0 else { return }
        Haptics.grab()
        // Dismiss before touching the store: changing observed state first
        // rebuilds the presenting view and the dismissal is lost.
        dismiss()
        wallet.beginRequest(PaymentRequest(merchant: merchant,
                                           amountMinor: minor,
                                           reference: Self.reference()))
    }

    private static func reference() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0..<2).map { _ in letters.randomElement()! })
             + String(format: "%04d", Int.random(in: 0...9999))
    }
}

/// Hairline keypad, entering pence from the right like a card terminal.
private struct Keypad: View {
    @Binding var value: String

    private let keys: [[String]] = [["1","2","3"], ["4","5","6"], ["7","8","9"], ["C","0","⌫"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            Haptics.tap()
                            press(key)
                        } label: {
                            Text(key)
                                .font(Theme.title(19))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "C": value = ""
        case "⌫": value = String(value.dropLast())
        default:
            guard value.count < 7 else { return }
            value = (value + key).trimmingLeadingZeros()
        }
    }
}

private extension String {
    func trimmingLeadingZeros() -> String {
        let trimmed = drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "" : String(trimmed)
    }
}
