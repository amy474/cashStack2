import SwiftUI

/// A jar being told where its money goes — either because a coin just landed
/// in it with nowhere to go, or because the sorted view asked for one.
struct JarSetup: Identifiable {
    let id = UUID()
    let jar: CoinJar
    /// The piece waiting to go in once a destination is picked.
    let pending: Denomination?
}

// MARK: - Settings

/// Where spare change goes, how much of it may, and what has gone so far.
struct SpareChangeSheet: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary
                    Hairline()

                    if wallet.isLive {
                        Notice(text: "The jars are practice for now. CashStack reads your bank balance but can't move money, so nothing is invested, donated or saved.")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    SheetSectionLabel(title: "Jars")
                    ForEach(CoinJar.allCases) { jar in
                        JarSettingRow(jar: jar)
                        Hairline().opacity(0.12)
                    }

                    SheetSectionLabel(title: "Limits")
                    SettingBlock(title: "What can go in a jar",
                                 detail: "A note can always be broken into coins with a double tap.") {
                        PillChoice(options: [("Coins only", false), ("Coins and notes", true)],
                                   selection: $wallet.spareChange.notesAllowed)
                    }
                    Hairline().opacity(0.12)
                    SettingBlock(title: "Daily limit across all jars",
                                 detail: limitDetail) {
                        PillChoice(options: SpareChangeSettings.dailyLimitChoices.map { (Self.label($0), $0) },
                                   selection: $wallet.spareChange.dailyLimitMinor)
                    }

                    SheetSectionLabel(title: "Tipping")
                    ToggleBlock(title: "Tip jar while I pay",
                                detail: "Only at places that take tips. A tip goes on top of the bill, never towards it.",
                                isOn: $wallet.spareChange.tipWhilePaying)
                    Hairline().opacity(0.12)
                    ToggleBlock(title: "Tip from my change",
                                detail: "Holds the tip jar out on the receipt for a few seconds after paying.",
                                isOn: $wallet.spareChange.tipFromChange)
                    Hairline().opacity(0.12)
                    SettingBlock(title: "Most I'll tip per payment", detail: nil) {
                        PillChoice(options: SpareChangeSettings.tipCapChoices.map { (Self.label($0), $0) },
                                   selection: $wallet.spareChange.tipCapMinor)
                    }

                    if !wallet.drops.isEmpty {
                        SheetSectionLabel(title: "Recent")
                        ForEach(wallet.drops.prefix(20)) { drop in
                            DropRow(drop: drop)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Theme.ground)
            .navigationTitle("Spare change")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CoinJar.self) { jar in
                DestinationPicker(jar: jar)
            }
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

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Into your jars this month")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
            Text(Money.format(minor: CoinJar.allCases.reduce(0) { $0 + wallet.monthTotal($1) }))
                .accessibilityIdentifier("jarsMonthTotal")
                .font(Theme.display(34))
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                ForEach(CoinJar.allCases) { jar in
                    HStack(spacing: 6) {
                        JarBadge(jar: jar, size: 18)
                        Text(Money.format(minor: wallet.monthTotal(jar)))
                            .font(Theme.body(12))
                            .monospacedDigit()
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .frame(height: 28)
                    .background(PillBackground())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(jar.title): \(Money.format(minor: wallet.monthTotal(jar)))")
                }
            }
            .padding(.top, 10)
            Text("Hold a coin and drag it up into a jar. Let go anywhere else and it drops back in the pile.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var limitDetail: String {
        guard let left = wallet.jarAllowanceLeftMinor else {
            return "No limit. Every coin still waits for you to drop it in."
        }
        return "\(Money.format(minor: left)) left today. A coin over the limit bounces back out."
    }

    static func label(_ minor: Int?) -> String {
        minor.map { Money.formatShort(minor: $0) } ?? "None"
    }
}

private struct JarSettingRow: View {
    @EnvironmentObject private var wallet: WalletStore
    let jar: CoinJar

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            JarBadge(jar: jar, size: 36)

            NavigationLink(value: jar) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(jar.title)
                            .font(Theme.title(15))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Text(destinationLine)
                        .font(Theme.body(13))
                        .foregroundStyle(hasDestination ? Theme.ink : Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    let total = wallet.monthTotal(jar)
                    if total > 0 {
                        Text("\(Money.format(minor: total)) this month · \(jar.whatHappensNext.lowercased())")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jarSettings-\(jar.rawValue)")

            Toggle("Show the \(jar.title) jar", isOn: shown)
                .labelsHidden()
        }
        .opacity(shown.wrappedValue ? 1 : 0.6)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hasDestination: Bool { wallet.destination(of: jar) != nil }

    private var destinationLine: String {
        switch jar {
        case .invest:
            if let fund = wallet.spareChange.investment { return "\(fund.ticker) · \(fund.name)" }
        case .donate:
            if let charity = wallet.spareChange.charity { return charity.name }
        case .save:
            if let account = wallet.savingsAccount {
                return "\(account.institution.name) \(account.nickname) \(account.maskedNumber)"
            }
        }
        return "\(jar.choosePrompt) — or drop a coin in and you'll be asked"
    }

    private var shown: Binding<Bool> {
        Binding(get: { !wallet.spareChange.hiddenJars.contains(jar) },
                set: { show in
                    if show { wallet.spareChange.hiddenJars.remove(jar) }
                    else    { wallet.spareChange.hiddenJars.insert(jar) }
                })
    }
}

private struct DropRow: View {
    @EnvironmentObject private var wallet: WalletStore
    let drop: JarDrop

    var body: some View {
        HStack(spacing: 12) {
            JarBadge(jar: drop.jar, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(drop.receipt)
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.ink)
                Text(drop.date.formatted(date: .omitted, time: .shortened))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            Button("Take back") {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) { wallet.undo(drop) }
            }
            .font(Theme.title(12))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PillBackground())
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

// MARK: - Choosing where a jar's money goes

/// Opens by itself the first time a coin lands in a jar with nowhere to go,
/// so nobody has to set anything up before they can use it.
struct JarSetupSheet: View {
    let setup: JarSetup
    var onPicked: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DestinationPicker(jar: setup.jar, pending: setup.pending, onPicked: onPicked)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(setup.pending == nil ? "Cancel" : "Put it back") { dismiss() }
                            .font(Theme.title(16))
                            .foregroundStyle(Theme.ink)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

struct DestinationPicker: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.dismiss) private var dismiss

    let jar: CoinJar
    /// A piece waiting on this choice. It goes in as soon as one is made.
    var pending: Denomination?
    var onPicked: (() -> Void)?

    @State private var kind: Investment.Kind = .etf

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                intro
                Hairline()
                switch jar {
                case .invest: investments
                case .donate: charities
                case .save:   savings
                }
                Text(footnote)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            }
        }
        .background(Theme.ground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let chosen = wallet.spareChange.investment { kind = chosen.kind }
        }
    }

    private var title: String {
        switch jar {
        case .invest: "Invest in"
        case .donate: "Donate to"
        case .save:   "Save into"
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 14) {
            if let pending {
                MoneyThumb(denomination: pending, height: 40)
                    .frame(width: 44)
            } else {
                JarBadge(jar: jar, size: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.ink)
                Text(pending == nil ? jar.howItWorks
                                    : "Pick once and it goes straight in. Next time it just drops. You can change this under Jars.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var headline: String {
        guard let pending else {
            switch jar {
            case .invest: return "What should your coins buy?"
            case .donate: return "Who should your coins help?"
            case .save:   return "Where should your coins be saved?"
            }
        }
        switch jar {
        case .invest: return "What should your \(pending.label) buy?"
        case .donate: return "Who should your \(pending.label) help?"
        case .save:   return "Where should your \(pending.label) go?"
        }
    }

    private var footnote: String {
        switch jar {
        case .invest:
            "\(jar.howItWorks)\n\nGeneral information only, not a recommendation. Think about whether an investment suits you and read its disclosure document first. Prices go down as well as up."
        case .donate:
            jar.howItWorks
        case .save:
            if let current = wallet.selectedAccount {
                "\(jar.howItWorks) Your wallet is paying from \(current.institution.name) \(current.nickname), so it isn't listed."
            } else {
                jar.howItWorks
            }
        }
    }

    // MARK: Investments

    private var investments: some View {
        VStack(spacing: 0) {
            PillChoice(options: Investment.Kind.allCases.map { ($0.rawValue, $0) }, selection: $kind)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            ForEach(Investment.catalogue.filter { $0.kind == kind }) { fund in
                PickRow(isSelected: wallet.spareChange.investment == fund,
                        identifier: "pick-\(fund.ticker)",
                        action: {
                            wallet.spareChange.investment = fund
                            picked()
                        }) {
                    Text(fund.ticker)
                        .font(Theme.label(11))
                        .kerning(0.6)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 56, height: 28)
                        .background(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fund.name)
                            .font(Theme.title(15))
                        Text(fund.blurb)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Hairline().opacity(0.12)
            }
        }
    }

    // MARK: Charities

    private var charities: some View {
        VStack(spacing: 0) {
            ForEach(Charity.catalogue) { charity in
                PickRow(isSelected: wallet.spareChange.charity == charity,
                        identifier: "pick-\(charity.id)",
                        action: {
                            wallet.spareChange.charity = charity
                            picked()
                        }) {
                    JarBadge(jar: .donate, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(charity.name)
                            .font(Theme.title(15))
                        Text(charity.cause)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.inkSoft)
                        Text("TAX DEDUCTIBLE")
                            .font(Theme.label(9))
                            .kerning(1)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 2)
                    }
                }
                Hairline().opacity(0.12)
            }
        }
    }

    // MARK: Savings

    private var savings: some View {
        VStack(spacing: 0) {
            let others = wallet.accounts.filter { $0.id != wallet.selectedAccountID }
            if others.isEmpty {
                Text("Link another account under Accounts to save into it.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(20)
            }
            ForEach(others) { account in
                PickRow(isSelected: wallet.spareChange.savingsAccountID == account.id,
                        identifier: "pick-\(account.id)",
                        action: {
                            wallet.spareChange.savingsAccountID = account.id
                            picked()
                        }) {
                    Text(account.institution.mark)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(account.institution.tint.opacity(0.9))
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(account.institution.name) \(account.nickname)")
                            .font(Theme.title(15))
                        Text("\(account.maskedNumber) · \(Money.format(minor: account.availableMinor))")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.inkSoft)
                            .monospacedDigit()
                    }
                }
                Hairline().opacity(0.12)
            }
        }
    }

    private func picked() {
        Haptics.tap()
        if let onPicked { onPicked() } else { dismiss() }
    }
}

private struct PickRow<Content: View>: View {
    let isSelected: Bool
    let identifier: String
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                content()
                Spacer(minLength: 6)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Sheet furniture

private struct SheetSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.label(10))
            .kerning(2)
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }
}

private struct SettingBlock<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.title(15))
                .foregroundStyle(Theme.ink)
            control()
            if let detail {
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct ToggleBlock: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// The Loose / Sorted switch, for any short list of options.
struct PillChoice<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button {
                    guard !isOn else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(Theme.title(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isOn {
                                Capsule(style: .continuous)
                                    .fill(Theme.ink)
                                    .matchedGeometryEffect(id: "choice", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
        )
    }
}
