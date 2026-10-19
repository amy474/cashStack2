import SwiftUI

/// Why the selected account has nothing in the pile, so the wallet can say
/// so rather than show an empty screen.
enum EmptyPileReason: Equatable {
    /// $0.00.
    case nothing
    /// 1c to 4c: real money, but less than the smallest coin.
    case underFiveCents(Int)
    /// Below zero.
    case overdrawn(Int)

    var title: String {
        switch self {
        case .nothing: "No cash in the wallet"
        case .underFiveCents: "Less than 5c"
        case .overdrawn: "Overdrawn"
        }
    }

    var detail: String {
        switch self {
        case .nothing:
            "This account has nothing in it right now."
        case .underFiveCents(let minor):
            "\(Money.format(minor: minor)) can't be held as cash: the smallest coin is 5c."
        case .overdrawn(let minor):
            "This account is \(Money.format(minor: -minor)) below zero, so there's no cash to show."
        }
    }
}

extension WalletStore {
    /// Set when an account is selected but there's nothing to pile up.
    var emptyPileReason: EmptyPileReason? {
        guard phase == .ready, selectedAccount != nil, pieceCount == 0, request == nil else { return nil }
        let minor = walletMinor
        if minor < 0 { return .overdrawn(minor) }
        if minor == 0 { return .nothing }
        return minor < Money.smallestPiece ? .underFiveCents(minor) : nil
    }
}

/// What the loose pile and the sorted view show in place of money.
struct EmptyPile: View {
    let reason: EmptyPileReason
    /// Offered when there's another account to switch to.
    var onChooseAccount: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "banknote")
                .font(.system(size: 26, weight: .light))
                .accessibilityHidden(true)
            Text(reason.title)
                .font(Theme.title(16))
            Text(reason.detail)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onChooseAccount {
                GhostPillButton(title: "Choose another account", systemImage: "arrow.left.arrow.right") {
                    onChooseAccount()
                }
                .padding(.top, 6)
                .accessibilityIdentifier("chooseAnotherAccount")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyPile")
    }
}
