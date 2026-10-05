import SwiftUI
import SpriteKit

struct RootView: View {
    @EnvironmentObject private var wallet: WalletStore

    @State private var scene = CashScene()
    @State private var mode: WalletMode = .loose
    @State private var showAccounts = false
    @State private var showTill = false
    @State private var receipt: CashTransaction?
    @State private var armed = false
    @State private var sceneReady = false

    private let headerPlainHeight: CGFloat = 196
    private let headerPayHeight: CGFloat = 210
    private let footerHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .top) {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Hairline()

                ZStack {
                    CashSceneView(scene: scene)
                        .opacity(mode == .loose ? 1 : 0)
                        .allowsHitTesting(mode == .loose)

                    if mode == .sorted {
                        SortedView()
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if wallet.phase == .loading {
                        LoadingPile()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Hairline()
                footer
            }

            if let receipt {
                ReceiptCard(transaction: receipt)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: wallet.request)
        .animation(.easeInOut(duration: 0.22), value: receipt?.id)
        .sheet(isPresented: $showAccounts) { AccountsSheet() }
        .sheet(isPresented: $showTill) { TillSheet() }
        .task {
            configureScene()
            if wallet.phase == .loading { await wallet.load() }
        }
        .onChange(of: wallet.pileSignature) { _, _ in
            scene.sync(to: wallet.stacks)
        }
        .onChange(of: wallet.request) { _, request in
            scene.isPaymentActive = request != nil
        }
        .onChange(of: wallet.lastSettlement?.id) { _, _ in
            guard let settlement = wallet.lastSettlement else { return }
            Haptics.success()
            receipt = settlement
            Task {
                try? await Task.sleep(for: .seconds(3.2))
                if receipt?.id == settlement.id { receipt = nil }
            }
        }
    }

    // MARK: Scene wiring

    private func configureScene() {
        guard !sceneReady else { return }
        sceneReady = true
        scene.scaleMode = .resizeFill
        scene.payLineInset = 36
        scene.floorInset = 10

        scene.onCrossPayLine = { isArmed in
            armed = isArmed
        }
        scene.onTender = { denomination in
            Task { @MainActor in
                let result = await wallet.tender(denomination)
                if case .shortBy = result { Haptics.arm() }
            }
        }
        scene.sync(to: wallet.stacks, animated: false)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if let request = wallet.request {
            PayHeader(request: request,
                      tendered: wallet.tenderedMinor,
                      outstanding: wallet.outstandingMinor,
                      armed: armed,
                      onCancel: {
                          Haptics.tap()
                          wallet.cancelRequest()
                      })
            .frame(height: headerPayHeight)
        } else {
            WalletHeader(mode: $mode, onAccounts: { showAccounts = true })
                .frame(height: headerPlainHeight)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if wallet.request == nil {
                Button {
                    Haptics.tap()
                    wallet.tidyPile()
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 54, height: 54)
                        .background(PillBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tidy the pile into the fewest notes and coins")

                PrimaryPillButton(title: "Pay at till", systemImage: "wave.3.right") {
                    showTill = true
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(armed ? "Let go to hand it over" : "Hold a note, swipe to the top")
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.ink)
                    Text("\(wallet.pieceCount) pieces in your wallet")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: armed ? "arrow.up.circle.fill" : "arrow.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .offset(y: armed ? -3 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: armed)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: footerHeight)
    }
}

// MARK: - Wallet header

private struct WalletHeader: View {
    @EnvironmentObject private var wallet: WalletStore
    @Binding var mode: WalletMode
    var onAccounts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CASHSTACK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(2.4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onAccounts) {
                    HStack(spacing: 7) {
                        AccountDots(accounts: wallet.includedAccounts)
                        Text("\(wallet.includedAccounts.count) of \(wallet.accounts.count)")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(PillBackground())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            Text(Money.format(minor: wallet.walletMinor))
                .accessibilityIdentifier("walletBalance")
                .font(Theme.display(50))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 14)

            Text("\(wallet.pieceCount) pieces of cash · \(wallet.includedAccounts.count) \(wallet.includedAccounts.count == 1 ? "bank" : "banks")")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 2)

            Spacer(minLength: 10)

            ModeSwitch(selection: $mode)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
    }
}

private struct AccountDots: View {
    let accounts: [LinkedAccount]
    var body: some View {
        HStack(spacing: -5) {
            ForEach(accounts.prefix(3)) { account in
                Circle()
                    .fill(account.institution.tint)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
            }
            if accounts.isEmpty {
                Circle()
                    .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                    .frame(width: 13, height: 13)
            }
        }
    }
}

// MARK: - Payment header

private struct PayHeader: View {
    let request: PaymentRequest
    let tendered: Int
    let outstanding: Int
    let armed: Bool
    var onCancel: () -> Void

    private var progress: Double {
        guard request.amountMinor > 0 else { return 1 }
        return min(1, Double(tendered) / Double(request.amountMinor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(PillBackground())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("REF \(request.reference)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(1.4)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 6)

            Text("\(request.merchant) is asking for")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 12)

            Text(Money.format(minor: request.amountMinor))
                .accessibilityIdentifier("requestAmount")
                .font(Theme.display(44))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()

            // Progress: a hairline track that fills as money is handed over.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 8)
            .padding(.top, 10)

            HStack {
                Text("Handed over \(Money.format(minor: tendered))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(outstanding > 0 ? "\(Money.format(minor: outstanding)) to go" : "Enough — let go above the line")
                    .font(Theme.title(12))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 6)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                Text(armed ? "Release to pay" : "Swipe money above this line")
                    .font(Theme.title(12))
            }
            .foregroundStyle(armed ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PillBackground(filled: armed))
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Loading

private struct LoadingPile: View {
    @State private var spin = false
    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: Theme.line, lineCap: .round))
                .frame(width: 34, height: 34)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                }
            Text("Counting your cash")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
    }
}

// MARK: - Receipt

private struct ReceiptCard: View {
    let transaction: CashTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.ink))

            VStack(alignment: .leading, spacing: 2) {
                Text("Paid \(Money.format(minor: transaction.amountMinor)) to \(transaction.merchant)")
                    .accessibilityIdentifier("receiptHeadline")
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.ink)
                Text(transaction.changeMinor > 0
                     ? "\(Money.format(minor: transaction.changeMinor)) change falling back in"
                     : "Exact money — no change")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.ground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                )
                .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
        }
    }
}
