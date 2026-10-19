import SwiftUI

/// The "I need to see this clearly" view: the same cash, counted and in order.
struct SortedView: View {
    @EnvironmentObject private var wallet: WalletStore

    /// Room for the glass bars the list scrolls underneath.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// Put one of a row's pieces in a jar — the same jars as dragging, for
    /// anyone who would rather not, or cannot, drag.
    var onPutInJar: (Denomination, CoinJar) -> Void = { _, _ in }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)

                if wallet.stacks.isEmpty {
                    EmptyWallet()
                        .padding(.top, 70)
                } else {
                    if !wallet.bundles.isEmpty {
                        SectionLabel(title: "Bundles", value: wallet.bundles.reduce(0) { $0 + $1.subtotalMinor })
                        ForEach(Array(wallet.bundles.enumerated()), id: \.element.id) { index, stack in
                            StackRow(stack: stack, shimmerDelay: Double(index) * 0.18, onPutInJar: onPutInJar)
                            Hairline().opacity(0.12)
                        }
                    }
                    if !wallet.notes.isEmpty {
                        SectionLabel(title: "Notes", value: wallet.notes.reduce(0) { $0 + $1.subtotalMinor })
                        ForEach(Array(wallet.notes.enumerated()), id: \.element.id) { index, stack in
                            StackRow(stack: stack, shimmerDelay: Double(index) * 0.18, onPutInJar: onPutInJar)
                            Hairline().opacity(0.12)
                        }
                    }
                    if !wallet.coins.isEmpty {
                        SectionLabel(title: "Coins", value: wallet.coins.reduce(0) { $0 + $1.subtotalMinor })
                        ForEach(Array(wallet.coins.enumerated()), id: \.element.id) { index, stack in
                            StackRow(stack: stack, shimmerDelay: Double(index) * 0.18 + 0.4, onPutInJar: onPutInJar)
                            Hairline().opacity(0.12)
                        }
                    }
                    TotalRow(total: wallet.pileMinor, pieces: wallet.pieceCount)
                }

                Color.clear.frame(height: bottomInset)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground)
    }
}

private struct SectionLabel: View {
    let title: String
    let value: Int

    var body: some View {
        HStack {
            Text(title.uppercased())
                .accessibilityIdentifier("section-\(title)")
                .font(Theme.label(10))
                .kerning(2)
            Spacer()
            Text(Money.format(minor: value))
                .font(Theme.body(11))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct StackRow: View {
    @EnvironmentObject private var wallet: WalletStore
    let stack: MoneyStack
    let shimmerDelay: Double
    var onPutInJar: (Denomination, CoinJar) -> Void

    var body: some View {
        HStack(spacing: 14) {
            MoneyThumb(denomination: stack.denomination,
                       height: stack.denomination.kind == .coin ? 32 : 38,
                       shimmerDelay: shimmerDelay)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(stack.denomination.label)
                    .font(Theme.title(16))
                    .foregroundStyle(Theme.ink)
                Text(kindLabel)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 6)

            Text("×\(stack.count)")
                .font(Theme.title(15))
                .foregroundStyle(Theme.inkSoft)
                .monospacedDigit()

            Text(Money.format(minor: stack.subtotalMinor))
                .font(Theme.title(16))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 86, alignment: .trailing)

            if wallet.jarsTake(stack.denomination) {
                jarMenu
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var kindLabel: String {
        let piece = stack.denomination
        return piece.kind == .bundle ? "bundle of \(piece.hundreds) × \(Denomination.n100.label)" : piece.noun
    }

    private var jarMenu: some View {
        let piece = stack.denomination
        return Menu {
            Section("Put one \(piece.label) in a jar") {
                ForEach(wallet.visibleJars) { jar in
                    let refusal = wallet.refusal(jar, for: piece)
                    Button {
                        onPutInJar(piece, jar)
                    } label: {
                        Text(jar.title)
                        Text(refusal ?? wallet.destination(of: jar) ?? jar.choosePrompt)
                        Image(systemName: jar.symbol)
                    }
                    .disabled(refusal != nil)
                    .accessibilityIdentifier("menu-\(jar.rawValue)")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(PillBackground())
                .contentShape(Circle())
        }
        .accessibilityIdentifier("jarMenu-\(piece.label)")
        .accessibilityLabel("Put a \(piece.label) in a jar")
    }
}

private struct TotalRow: View {
    let total: Int
    let pieces: Int

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total")
                        .font(Theme.title(16))
                    Text("\(pieces) pieces")
                        .accessibilityIdentifier("sortedPieces")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text(Money.format(minor: total))
                    .accessibilityIdentifier("sortedTotal")
                    .font(Theme.display(26))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .padding(.top, 10)
    }
}

private struct EmptyWallet: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "banknote")
                .font(.system(size: 26, weight: .light))
            Text("No cash in the wallet")
                .font(Theme.title(16))
            Text("Pick another account to fill it")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
    }
}
