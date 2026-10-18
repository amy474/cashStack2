import SwiftUI

/// Multiple banks, one account at a time. Picking an account swaps the pile
/// over to its money, and that is the account the till takes payment from.
struct AccountsSheet: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var isLinking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wallet.selectedAccount.map { "Paying from \($0.institution.name) \($0.nickname)" }
                                 ?? "No account selected")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.inkSoft)
                            Text(Money.format(minor: wallet.walletMinor))
                                .font(Theme.display(34))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                    Hairline()

                    ForEach(wallet.accounts) { account in
                        AccountRow(account: account,
                                   isSelected: account.id == wallet.selectedAccountID) {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                wallet.select(account.id)
                            }
                        }
                        Hairline().opacity(0.12)
                    }

                    Button {
                        Haptics.tap()
                        isLinking = true
                        Task {
                            await wallet.link(DemoBanks.extraSource())
                            isLinking = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isLinking ? "ellipsis" : "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text(isLinking ? "Connecting…" : "Link another bank")
                                .font(Theme.title(15))
                            Spacer()
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLinking || wallet.accounts.contains { $0.institution.id == "boab" })

                    Hairline()

                    if !wallet.history.isEmpty {
                        HStack {
                            Text("RECENT")
                                .font(Theme.label(10))
                                .kerning(2)
                                .foregroundStyle(Theme.inkSoft)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 6)

                        ForEach(wallet.history) { transaction in
                            HistoryRow(transaction: transaction)
                        }
                    }

                    GhostPillButton(title: "Reset demo", systemImage: "arrow.counterclockwise") {
                        Task { await wallet.reset() }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 30)
                }
            }
            .background(Theme.ground)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct AccountRow: View {
    let account: LinkedAccount
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("select-\(account.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var content: some View {
        HStack(spacing: 14) {
            Text(account.institution.mark)
                .font(Theme.title(15))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(account.institution.tint.opacity(0.9))
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(account.institution.name) \(account.nickname)")
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink)
                Text(account.maskedNumber)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 6)

            Text(Money.format(minor: account.availableMinor))
                .font(Theme.title(15))
                .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
                .monospacedDigit()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct HistoryRow: View {
    let transaction: CashTransaction

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant)
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            Text("−" + Money.format(minor: transaction.amountMinor + transaction.tipMinor))
                .font(Theme.title(14))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var detail: String {
        var parts = [transaction.date.formatted(date: .omitted, time: .shortened),
                     "handed over \(Money.format(minor: transaction.tenderedMinor))",
                     "change \(Money.format(minor: transaction.changeMinor))"]
        if transaction.tipMinor > 0 { parts.append("tip \(Money.format(minor: transaction.tipMinor))") }
        return parts.joined(separator: " · ")
    }
}
