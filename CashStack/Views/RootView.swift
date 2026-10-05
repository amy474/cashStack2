import SwiftUI
import SpriteKit

struct RootView: View {
    @EnvironmentObject private var wallet: WalletStore

    @State private var scene = CashScene()
    @State private var mode: WalletMode = .loose
    @State private var showAccounts = false
    @State private var receipt: CashTransaction?
    @State private var armed = false
    @State private var sceneReady = false

    /// Both headers are the same height, so the pay line never has to move.
    private let headerHeight: CGFloat = 194
    private let footerHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack(alignment: .top) {
                Theme.ground.ignoresSafeArea()

                // The pile fills the whole screen, so cash slides behind the
                // glass rather than stopping at it.
                CashSceneView(scene: scene)
                    .ignoresSafeArea()
                    .opacity(mode == .loose ? 1 : 0)
                    .allowsHitTesting(mode == .loose)

                if mode == .sorted {
                    SortedView(topInset: safeTop + headerHeight + 14,
                               bottomInset: safeBottom + footerHeight + 14)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if wallet.phase == .loading {
                    LoadingPile().ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)
                        .padding(.top, safeTop)
                        .background(TopGlass())

                    Spacer(minLength: 0)

                    footer
                        .frame(height: footerHeight)
                        .padding(.bottom, safeBottom)
                        .background(BottomBar())
                }
                .ignoresSafeArea()

                if let receipt {
                    ReceiptCard(transaction: receipt)
                        .padding(.horizontal, 18)
                        .padding(.top, safeTop + headerHeight + 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(3)
                }
            }
            .task(id: geo.size) {
                configureScene()
                scene.payLineInset = safeTop + headerHeight + 30
                // The pile rests on the top edge of the bottom bar.
                scene.floorInset = safeBottom + footerHeight
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: wallet.request)
        .animation(.easeInOut(duration: 0.22), value: receipt?.id)
        .sheet(isPresented: $showAccounts) { AccountsSheet() }
        .task {
            if wallet.phase == .loading { await wallet.load() }
        }
        .onChange(of: wallet.pileSignature) { _, _ in
            scene.sync(to: wallet.stacks)
        }
        .onChange(of: wallet.request?.id) { _, _ in
            scene.isPaymentActive = wallet.request != nil
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
        scene.onCrossPayLine = { armed = $0 }
        scene.onTender = { denomination in
            Task { @MainActor in wallet.tender(denomination) }
        }
        scene.sync(to: wallet.stacks, animated: false)
    }

    /// Paying needs the loose pile, so asking to pay brings it back.
    private func payAtTill() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { mode = .loose }
        wallet.beginDemoRequest()
        scene.isPaymentActive = true
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if let request = wallet.request {
            PayHeader(request: request,
                      outstanding: wallet.outstandingMinor,
                      tendered: wallet.tenderedMinor,
                      armed: armed,
                      onCancel: {
                          Haptics.tap()
                          wallet.cancelRequest()
                          scene.isPaymentActive = false
                      })
        } else {
            WalletHeader(mode: $mode, onAccounts: { showAccounts = true })
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
                    payAtTill()
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(footerPrompt)
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
    }

    private var footerPrompt: String {
        if wallet.isSettling { "Counting your change…" }
        else if armed       { "Let go to hand it over" }
        else                { "Hold a note, swipe to the top" }
    }
}

// MARK: - Glass

/// The frosted bar at the top. Cash slides up behind it and stays visible,
/// which is the whole point of it being glass rather than paint.
private struct TopGlass: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.ultraThinMaterial)
            Hairline()
        }
    }
}

/// The bottom bar is solid — the pile lands on top of it rather than
/// disappearing underneath.
private struct BottomBar: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.ground)
            Hairline()
        }
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
                    .font(Theme.label(11))
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
                    .contentShape(Rectangle())
                    .background(PillBackground())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            Text(Money.format(minor: wallet.walletMinor))
                .accessibilityIdentifier("walletBalance")
                .font(Theme.display(48))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 12)

            Text("\(wallet.pieceCount) pieces of cash · \(wallet.includedAccounts.count) \(wallet.includedAccounts.count == 1 ? "bank" : "banks")")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 2)

            Spacer(minLength: 10)

            ModeSwitch(selection: $mode)
                .padding(.bottom, 12)
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
    /// Counts down as money is handed over, then goes negative — at which
    /// point it is the change on its way back.
    let outstanding: Int
    let tendered: Int
    let armed: Bool
    var onCancel: () -> Void

    private var isOverpaid: Bool { outstanding < 0 }
    private var isExact: Bool { outstanding == 0 }

    private var caption: String {
        if isOverpaid { "Change coming back to you" }
        else if isExact { "Exactly right — thanks" }
        else if tendered > 0 { "Still to pay \(request.merchant)" }
        else { "\(request.merchant) is asking for" }
    }

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
                        .contentShape(Rectangle())
                        .background(PillBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel payment")
                Spacer()
                Text("\(request.what.uppercased()) · REF \(request.reference)")
                    .font(Theme.label(10))
                    .kerning(1.2)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 6)

            Text(caption)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 12)

            Text(Money.format(minor: outstanding))
                .accessibilityIdentifier("outstandingAmount")
                .font(Theme.display(46))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())

            // Hairline track that fills as money is handed over.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 8)
            .padding(.top, 8)

            HStack {
                Text("Handed over \(Money.format(minor: tendered))")
                    .accessibilityIdentifier("tenderedAmount")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text("of \(Money.format(minor: request.amountMinor))")
                    .accessibilityIdentifier("askedAmount")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 6)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Image(systemName: isOverpaid || isExact ? "checkmark" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                Text(hint)
                    .font(Theme.title(12))
            }
            .foregroundStyle(armed || isOverpaid || isExact ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PillBackground(filled: armed || isOverpaid || isExact))
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 18)
    }

    private var hint: String {
        if isOverpaid { "Change falling back in" }
        else if isExact { "Paid" }
        else if armed { "Release to pay" }
        else { "Swipe money above this line" }
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
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.ground.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        }
    }
}
