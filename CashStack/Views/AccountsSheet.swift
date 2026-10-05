import SwiftUI

/// Multiple banks, one pile. Switching an account off takes its money straight
/// back out of the wallet.
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
                            Text("In your wallet")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.inkSoft)
                            Text(Money.format(minor: wallet.walletMinor))
                                .font(Theme.display(34))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Linked")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.inkSoft)
                            Text(Money.format(minor: wallet.totalLinkedMinor))
                                .font(Theme.title(18))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                    Hairline()

                    ForEach(wallet.accounts) { account in
                        AccountRow(account: account) { included in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                wallet.setIncluded(included, for: account.id)
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
    var onToggle: (Bool) -> Void

    var body: some View {
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
                .foregroundStyle(account.isIncluded ? Theme.ink : Theme.inkSoft)
                .monospacedDigit()

            Toggle("", isOn: Binding(get: { account.isIncluded }, set: onToggle))
                .labelsHidden()
                .accessibilityIdentifier("include-\(account.id)")
                .tint(Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                Text("\(transaction.date.formatted(date: .omitted, time: .shortened)) · handed over \(Money.format(minor: transaction.tenderedMinor)) · change \(Money.format(minor: transaction.changeMinor))")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            Text("−" + Money.format(minor: transaction.amountMinor))
                .font(Theme.title(14))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
