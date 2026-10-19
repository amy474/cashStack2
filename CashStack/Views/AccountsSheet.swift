import SwiftUI

/// Multiple banks, one account at a time. Picking an account swaps the pile
/// over to its money, and that is the account the till takes payment from.
/// With real banks this is also where data sharing is managed, and where the
/// account can be signed out of or deleted.
struct AccountsSheet: View {
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var web
    @AppStorage(Preference.demo) private var demo = false
    @StateObject private var sharing = DataSharing()

    @State private var isLinking = false
    @State private var message: String?
    @State private var stopping: APIConnection?
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wallet.selectedAccount.map { "\(wallet.isLive ? "In your wallet" : "Paying from"): \($0.institution.name) \($0.nickname)" }
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
                        linkAnotherBank()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isLinking ? "ellipsis" : "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text(isLinking ? "Connecting…" : !wallet.isLive ? "Link another bank"
                                 : wallet.accounts.isEmpty ? "Connect a bank" : "Connect another bank")
                                .font(Theme.title(15))
                            Spacer()
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLinking || (!wallet.isLive && wallet.accounts.contains { $0.institution.id == "boab" }))
                    .accessibilityIdentifier("linkAnotherBank")

                    if let message {
                        Notice(text: message)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }

                    Hairline()

                    if wallet.isLive { live }

                    if !wallet.history.isEmpty {
                        SheetLabel(title: wallet.isLive ? "Recent practice" : "Recent")
                        ForEach(wallet.history) { transaction in
                            HistoryRow(transaction: transaction)
                        }
                    }

                    if !wallet.isLive {
                        HStack(spacing: 10) {
                            GhostPillButton(title: "Reset demo", systemImage: "arrow.counterclockwise") {
                                Task { await wallet.reset() }
                            }
                            GhostPillButton(title: "Use my real bank", systemImage: "building.columns") {
                                dismiss()
                                demo = false
                            }
                            .accessibilityIdentifier("leaveDemo")
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 30)
                    }
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
            .task {
                if wallet.isLive { await sharing.load(session.api) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Real banks

    @ViewBuilder private var live: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paying at the till and the jars are practice. No money leaves your bank — the pile is your real balance to play with.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                GhostPillButton(title: wallet.isRefreshing ? "Refreshing…" : "Refresh balances",
                                systemImage: "arrow.clockwise") {
                    Task { await wallet.refreshFromBank() }
                }
                .disabled(wallet.isRefreshing || wallet.request != nil)
                .accessibilityIdentifier("refreshBalances")
                if wallet.practiceSpentMinor > 0 {
                    GhostPillButton(title: "Undo practice", systemImage: "arrow.uturn.backward") {
                        wallet.discardPractice()
                    }
                    .accessibilityIdentifier("discardPractice")
                }
            }
            if let refreshed = wallet.lastRefreshed {
                Text("Balances from \(refreshed.formatted(.relative(presentation: .named))). Your bank updates them about once a day.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)

        Hairline()

        SheetLabel(title: "Data sharing")
        if sharing.connections.isEmpty {
            Text(sharing.loaded ? "No banks are sharing with CashStack." : "Checking…")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        VStack(spacing: 0) {
            ForEach(sharing.connections) { connection in
                ConnectionRow(connection: connection) { stopping = connection }
                Hairline().opacity(0.12)
            }
        }
        .confirmationDialog("Stop sharing \(stopping?.institution.name ?? "this bank")?",
                            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                            titleVisibility: .visible,
                            presenting: stopping) { connection in
            Button("Stop sharing", role: .destructive) { stop(connection) }
            Button("Keep sharing", role: .cancel) {}
        } message: { _ in
            Text("Basiq deletes this connection and the data it fetched through it. Its accounts leave your wallet.")
        }
        VStack(alignment: .leading, spacing: 12) {
            if let expires = sharing.consentExpires, expires.timeIntervalSinceNow < 30 * 86_400 {
                Notice(text: "Your consent to share ends \(expires.formatted(date: .abbreviated, time: .omitted)). Extend it to keep your wallet filling.")
                GhostPillButton(title: "Extend sharing", systemImage: "calendar.badge.plus") { runConsent("extend") }
            }
            GhostPillButton(title: "Manage data sharing", systemImage: "slider.horizontal.3") { runConsent("manage") }
                .accessibilityIdentifier("manageDataSharing")
            Link(destination: AppConfig.dataSharingURL) {
                HStack(spacing: 5) {
                    Text("How data sharing works")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                }
                .font(Theme.title(13))
                .foregroundStyle(Theme.ink)
                .underline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)

        Hairline()

        if DeviceLock.isAvailable {
            SheetLabel(title: "Security")
            Toggle(isOn: Binding(get: { session.lockEnabled },
                                 set: { on in Task { await session.setLock(on) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock with \(DeviceLock.name)")
                        .font(Theme.title(15))
                    Text("Locks a minute after you leave the app.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.ink)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .accessibilityIdentifier("lockToggle")
            Hairline()
        }

        SheetLabel(title: "Account")
        VStack(alignment: .leading, spacing: 12) {
            if let email = sharing.email {
                Text("Signed in as \(email)")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            GhostPillButton(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                dismiss()
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("signOut")
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text(deleting ? "Deleting…" : "Delete my account and data")
                    .font(Theme.title(14))
                    .foregroundStyle(Color(rgb: 0xC4122F))
            }
            .disabled(deleting)
            .accessibilityIdentifier("deleteAccount")
            .confirmationDialog("Delete your CashStack account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account and data", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This disconnects every bank, deletes the data Basiq holds for CashStack, and signs you out. It can't be undone.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)

        Hairline()
    }

    // MARK: Actions

    private func linkAnotherBank() {
        guard wallet.isLive else {
            isLinking = true
            Task {
                await wallet.link(DemoBanks.extraSource())
                isLinking = false
            }
            return
        }
        runConsent("connect")
    }

    /// connect, manage or extend — all a trip through Basiq's screens, after
    /// which the accounts and connections are read again.
    private func runConsent(_ action: String) {
        isLinking = true
        message = nil
        Task {
            let outcome = await BankLink(api: session.api).run(action, with: web)
            switch outcome {
            case .connected(let accounts):
                await wallet.connected(accounts)
            case .cancelled:
                await wallet.refreshQuietly()
            case .failed(let reason):
                message = reason
            }
            await sharing.load(session.api)
            isLinking = false
        }
    }

    private func stop(_ connection: APIConnection) {
        Task {
            do {
                try await sharing.stop(connection, api: session.api)
                await wallet.refreshQuietly()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            do {
                try await session.deleteAccount()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            deleting = false
        }
    }
}

/// The banks sharing with CashStack, the consent behind them, and who is
/// signed in — read fresh each time the sheet opens.
@MainActor
final class DataSharing: ObservableObject {
    @Published private(set) var connections: [APIConnection] = []
    @Published private(set) var consentExpires: Date?
    @Published private(set) var email: String?
    @Published private(set) var loaded = false

    func load(_ api: APIClient) async {
        async let connections: ConnectionsResponse = api.get("v1/connections")
        async let me: Me = api.get("v1/me")
        if let list = try? await connections { self.connections = list.connections }
        if let me = try? await me {
            email = me.email
            consentExpires = me.bank.consent?.expiresAt
        }
        loaded = true
    }

    func stop(_ connection: APIConnection, api: APIClient) async throws {
        try await api.delete("v1/connections/\(connection.id)")
        connections.removeAll { $0.id == connection.id }
    }
}

private struct ConnectionRow: View {
    let connection: APIConnection
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            let institution = Institution(connection.institution)
            Text(institution.mark)
                .font(Theme.title(15))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(institution.tint.opacity(0.9))
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline)))
            VStack(alignment: .leading, spacing: 2) {
                Text(institution.name)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            Button("Stop sharing", action: onStop)
                .font(Theme.body(12))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(PillBackground())
                .buttonStyle(.plain)
                .accessibilityIdentifier("stopSharing-\(connection.id)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var detail: String {
        switch connection.status {
        case "active":
            return connection.expiresAt.map { "Sharing until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Sharing"
        case "invalid":
            return "Needs reconnecting"
        default:
            return connection.status.capitalized
        }
    }
}

private struct SheetLabel: View {
    let title: String
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.label(10))
                .kerning(2)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct AccountRow: View {
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
