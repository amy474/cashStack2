import SwiftUI
import SpriteKit

struct RootView: View {
    @EnvironmentObject private var wallet: WalletStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var scene = CashScene()
    @State private var mode: WalletMode = .loose
    @State private var showAccounts = false
    @State private var showSpareChange = false
    @State private var armed = false
    @State private var sceneReady = false

    // The receipt, and how long it stays up.
    @State private var receiptID: CashTransaction.ID?
    @State private var receiptCloses = Date.distantPast
    @State private var receiptTimer: Task<Void, Never>?

    // Jars.
    /// The piece in the hand right now.
    @State private var held: Denomination?
    @State private var hoveredTarget: String?
    /// The jar that just took a piece, kept on screen a beat so you see it land.
    @State private var landed: CoinJar?
    @State private var lingerTask: Task<Void, Never>?
    /// A jar that needs telling where its money goes.
    @State private var setup: JarSetup?
    @State private var tipChooserOpen = false

    /// Every header is the same height, so the pay line never has to move.
    private let headerHeight: CGFloat = 194
    private let footerHeight: CGFloat = 92
    /// How long the receipt holds the tip jar out for some change.
    private static let tipWindow: TimeInterval = 8

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
                               bottomInset: safeBottom + footerHeight + 14,
                               onPutInJar: putInJar)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if wallet.phase == .loading {
                    LoadingPile().ignoresSafeArea()
                }

                if mode == .loose, let reason = wallet.emptyPileReason {
                    EmptyPile(reason: reason,
                              onChooseAccount: wallet.accounts.count > 1 ? { showAccounts = true } : nil)
                        .padding(.top, safeTop + headerHeight)
                        .padding(.bottom, safeBottom + footerHeight)
                        .transition(.opacity)
                }

                if wallet.isLive && wallet.phase == .ready && wallet.accounts.isEmpty {
                    EmptyWallet()
                        .padding(.horizontal, 18)
                        .padding(.top, safeTop + headerHeight)
                        .padding(.bottom, safeBottom + footerHeight)
                }

                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)
                        .padding(.top, safeTop)
                        .background(TopGlass())
                        .animation(.easeInOut(duration: 0.18), value: showsJars)

                    Spacer(minLength: 0)

                    footer
                        .frame(height: footerHeight)
                        .padding(.bottom, safeBottom)
                        .background(BottomBar())
                }
                .ignoresSafeArea()

                banner
                    .padding(.horizontal, 18)
                    .padding(.top, safeTop + headerHeight + 14)
                    .zIndex(3)
            }
            .onPreferenceChange(DropTargetFrames.self) { frames in
                scene.dropTargets = frames.map { CashScene.DropTarget(id: $0.key, frame: $0.value) }
            }
            .task(id: geo.size) {
                configureScene()
                scene.payLineInset = safeTop + headerHeight + 30
                // The pile rests on the top edge of the bottom bar.
                scene.floorInset = safeBottom + footerHeight
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: wallet.request)
        .animation(.easeInOut(duration: 0.22), value: receiptID)
        .animation(.easeInOut(duration: 0.22), value: wallet.lastDrop?.id)
        .animation(.easeInOut(duration: 0.22), value: showsCoachMark)
        .animation(.easeInOut(duration: 0.22), value: wallet.errorMessage)
        .sheet(isPresented: $showAccounts) { AccountsSheet() }
        .sheet(isPresented: $showSpareChange) { SpareChangeSheet() }
        .sheet(item: $setup, onDismiss: {
            // "Put it back": the coin that was waiting falls back into the pile.
            scene.sync(to: wallet.stacks)
        }) { setup in
            JarSetupSheet(setup: setup) { finishSetup(setup) }
        }
        .confirmationDialog("Drop a coin in the tip jar", isPresented: $tipChooserOpen,
                            titleVisibility: .visible) {
            ForEach(tippableCoins) { coin in
                Button("Tip \(coin.label)") { tipByTap(coin) }
            }
            if let last = lastTip {
                Button("Take back the \(last.label)", role: .destructive) { takeBackTip() }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(tipChooserMessage)
        }
        .onChange(of: tipChooserOpen) { _, open in
            guard receiptOffersTip else { return }
            if open { receiptCloses = .distantFuture } else { holdReceiptOpen() }
        }
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
            showReceipt(settlement)
        }
        .task(id: wallet.lastDrop?.id) {
            // The undo toast steps aside after eight seconds — unless VoiceOver
            // is reading it, in which case it stays until it is dealt with.
            guard let drop = wallet.lastDrop, !voiceOver else { return }
            try? await Task.sleep(for: .seconds(8))
            if wallet.lastDrop?.id == drop.id { wallet.dismissLastDrop() }
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
        scene.onSplit = { denomination in
            Task { @MainActor in wallet.split(denomination) }
        }
        scene.onGrab = { grabbed($0) }
        scene.onLetGo = { _ in letGo() }
        scene.onHoverTarget = { hoveredTarget = $0 }
        scene.canDrop = { canDrop($0, into: $1) }
        scene.onDrop = { dropped($0, into: $1) }
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
                      practice: wallet.isLive,
                      onCancel: {
                          Haptics.tap()
                          wallet.cancelRequest()
                          scene.isPaymentActive = false
                      }) {
                if wallet.showsTipJarWhilePaying {
                    TipJarButton(tipMinor: wallet.tipMinor,
                                 isHovered: hoveredTarget == TipJar.target,
                                 refusal: held.flatMap { wallet.tipRefusal(for: $0, alreadyTipped: wallet.tipMinor) }) {
                        tipChooserOpen = true
                    }
                }
            }
        } else if showsJars {
            JarHeader(held: held, hovered: hoveredTarget, landed: landed)
                .transition(.opacity)
        } else {
            WalletHeader(mode: $mode,
                         onAccounts: { showAccounts = true },
                         onJars: { showSpareChange = true })
                .transition(.opacity)
        }
    }

    // MARK: Under the header: receipt, undo, first-run hint

    @ViewBuilder private var banner: some View {
        if let receipt = wallet.transaction(receiptID) {
            ReceiptCard(transaction: receipt,
                        practice: wallet.isLive,
                        tipping: receiptOffersTip ? .init(
                            isHovered: hoveredTarget == TipJar.target,
                            refusal: held.flatMap { wallet.tipRefusal(for: $0, alreadyTipped: receipt.tipMinor) },
                            closes: receiptCloses,
                            duration: Self.tipWindow) : nil,
                        onTipJar: { tipChooserOpen = true },
                        onClose: closeReceipt)
                // A receipt holding the tip jar fades in rather than sliding:
                // the jar measures where it is as it appears, and mid-slide it
                // would tell the scene it is somewhere above the screen.
                .transition(receiptOffersTip ? .opacity : .move(edge: .top).combined(with: .opacity))
        } else if let drop = wallet.lastDrop {
            DropToast(drop: drop) {
                withAnimation(.easeInOut(duration: 0.2)) { wallet.undo(drop) }
            }
            .id(drop.id)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let message = wallet.errorMessage {
            Button {
                wallet.errorMessage = nil
            } label: {
                Notice(text: message, floating: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dismisses the message")
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(for: .seconds(6))
                if wallet.errorMessage == message { wallet.errorMessage = nil }
            }
        } else if showsCoachMark {
            JarCoachMark { wallet.coachMarkSeen = true }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var showsCoachMark: Bool {
        !wallet.coachMarkSeen && wallet.drops.isEmpty && wallet.phase == .ready && mode == .loose
            && wallet.request == nil && held == nil && landed == nil
            && !wallet.visibleJars.isEmpty && !wallet.coins.isEmpty
    }

    // MARK: Jars

    /// The header turns into jars while a coin is in the hand — and stays a
    /// beat after one goes in, so you see it land.
    private var showsJars: Bool {
        guard wallet.request == nil, mode == .loose, !receiptOffersTip else { return false }
        if let held { return wallet.jarsTake(held) }
        return landed != nil
    }

    private func grabbed(_ denomination: Denomination) {
        held = denomination
        lingerTask?.cancel()
        landed = nil
        // Nobody should lose the tip jar while a coin is on its way to it.
        if receiptOffersTip { receiptCloses = .distantFuture }
    }

    private func letGo() {
        held = nil
        if receiptOffersTip { holdReceiptOpen() }
    }

    private func canDrop(_ denomination: Denomination, into target: String) -> Bool {
        if target == TipJar.target {
            if wallet.request != nil {
                return wallet.showsTipJarWhilePaying
                    && wallet.tipRefusal(for: denomination, alreadyTipped: wallet.tipMinor) == nil
            }
            guard let receipt = wallet.transaction(receiptID), wallet.offersTipFromChange(receipt) else {
                return false
            }
            return wallet.tipRefusal(for: denomination, alreadyTipped: receipt.tipMinor) == nil
        }
        guard showsJars, let jar = CoinJar(rawValue: target) else { return false }
        return wallet.refusal(jar, for: denomination) == nil
    }

    private func dropped(_ denomination: Denomination, into target: String) {
        var took = false
        if target == TipJar.target {
            if wallet.request != nil {
                took = wallet.tip(denomination)
            } else if let receiptID {
                took = wallet.tip(denomination, after: receiptID)
            }
        } else if let jar = CoinJar(rawValue: target) {
            landed = jar
            linger()
            if wallet.destination(of: jar) == nil {
                // Nowhere to send it yet: ask now, and keep the coin until then.
                setup = JarSetup(jar: jar, pending: denomination)
                return
            }
            took = wallet.drop(denomination, into: jar)
            if took { wallet.coachMarkSeen = true }
        }
        // The scene has already let go of the piece. If the wallet would not
        // take it after all, it falls back into the pile.
        if !took { scene.sync(to: wallet.stacks) }
    }

    private func linger() {
        lingerTask?.cancel()
        lingerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            landed = nil
        }
    }

    /// The sorted view's way in: no dragging, same jars.
    private func putInJar(_ denomination: Denomination, _ jar: CoinJar) {
        if wallet.destination(of: jar) == nil {
            setup = JarSetup(jar: jar, pending: denomination)
        } else if wallet.drop(denomination, into: jar) {
            Haptics.drop()
            wallet.coachMarkSeen = true
        }
    }

    private func finishSetup(_ setup: JarSetup) {
        if let pending = setup.pending, wallet.drop(pending, into: setup.jar) {
            Haptics.drop()
            wallet.coachMarkSeen = true
        }
        self.setup = nil
    }

    // MARK: Tipping by tap

    /// The tip so far on whatever the tip jar belongs to right now.
    private var tipSoFar: [Denomination] {
        if wallet.request != nil { return wallet.tipPieces }
        return wallet.transaction(receiptID)?.tipPieces ?? []
    }

    private var lastTip: Denomination? { tipSoFar.last }

    /// One of each coin in the pile that the tip jar would take.
    private var tippableCoins: [Denomination] {
        let already = tipSoFar.reduce(0) { $0 + $1.minor }
        return wallet.stacks.map(\.denomination).filter {
            wallet.tipRefusal(for: $0, alreadyTipped: already) == nil
        }
    }

    private var tipChooserMessage: String {
        let merchant = wallet.request?.merchant ?? wallet.transaction(receiptID)?.merchant ?? "them"
        let already = tipSoFar.reduce(0) { $0 + $1.minor }
        if already > 0 { return "\(Money.format(minor: already)) in the jar for \(merchant) so far." }
        return tippableCoins.isEmpty ? "No coins that fit under your tip limit."
                                     : "Optional. It goes to \(merchant) on top of the bill."
    }

    private func tipByTap(_ coin: Denomination) {
        let took = wallet.request != nil ? wallet.tip(coin)
                                         : receiptID.map { wallet.tip(coin, after: $0) } ?? false
        if took { Haptics.drop() }
    }

    private func takeBackTip() {
        if wallet.request != nil {
            wallet.takeBackTip()
        } else if let receiptID {
            wallet.takeBackTip(after: receiptID)
        }
    }

    // MARK: Receipt

    private var receiptOffersTip: Bool {
        wallet.transaction(receiptID).map(wallet.offersTipFromChange) ?? false
    }

    private func showReceipt(_ transaction: CashTransaction) {
        receiptID = transaction.id
        let seconds = wallet.offersTipFromChange(transaction) ? Self.tipWindow : 3.2
        receiptCloses = Date().addingTimeInterval(seconds)
        if voiceOver && wallet.offersTipFromChange(transaction) { receiptCloses = .distantFuture }

        receiptTimer?.cancel()
        let id = transaction.id
        receiptTimer = Task { @MainActor in
            // The deadline moves while the tip jar is in use, so keep checking it.
            while !Task.isCancelled, receiptCloses.timeIntervalSinceNow > 0 {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled, receiptID == id else { return }
            receiptID = nil
        }
    }

    /// Start the tip jar's countdown again from the top.
    private func holdReceiptOpen() {
        receiptCloses = voiceOver ? .distantFuture : Date().addingTimeInterval(Self.tipWindow)
    }

    private func closeReceipt() {
        Haptics.tap()
        receiptTimer?.cancel()
        receiptID = nil
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
                .accessibilityLabel("Tidy the pile into the fewest pieces")

                PrimaryPillButton(title: "Pay at till", systemImage: "wave.3.right") {
                    payAtTill()
                }
                // Nothing to pay with until a bank is connected.
                .disabled(wallet.pieceCount == 0)
                .opacity(wallet.pieceCount == 0 ? 0.35 : 1)
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
        else if hoveredTarget == TipJar.target { "Let go to drop it in the tip jar" }
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
    var onJars: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("CASHSTACK")
                    .font(Theme.label(11))
                    .kerning(2.4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onJars) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Jars")
                            .font(Theme.body(12))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                    .background(PillBackground())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jarsButton")
                .accessibilityLabel("Spare change jars")
                Button(action: onAccounts) {
                    HStack(spacing: 7) {
                        AccountDot(account: wallet.selectedAccount)
                        Text(wallet.selectedAccount?.nickname ?? "Accounts")
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
                .accessibilityIdentifier("accountsButton")
            }
            .padding(.top, 6)

            Text(Money.format(minor: wallet.walletMinor))
                .accessibilityIdentifier("walletBalance")
                .font(Theme.display(48))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.top, 12)

            Text(subline)
                .accessibilityIdentifier("walletSubline")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 2)

            Spacer(minLength: 10)

            ModeSwitch(selection: $mode)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
    }

    private var subline: String {
        let pieces = "\(wallet.pieceCount) pieces of cash"
        if wallet.practiceSpentMinor > 0 {
            return "\(pieces) · \(Money.format(minor: wallet.practiceSpentMinor)) spent in practice"
        }
        return "\(pieces) · \(wallet.selectedAccount?.institution.name ?? "no account")"
    }
}

private struct AccountDot: View {
    let account: LinkedAccount?
    var body: some View {
        Circle()
            .fill(account?.institution.tint ?? .clear)
            .frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
    }
}

// MARK: - Payment header

private struct PayHeader<TipJarView: View>: View {
    let request: PaymentRequest
    /// Counts down as money is handed over, then goes negative — at which
    /// point it is the change on its way back.
    let outstanding: Int
    let tendered: Int
    let armed: Bool
    /// Real balances, pretend money: nothing leaves the bank.
    var practice = false
    var onCancel: () -> Void
    /// Beside the amount, at places that take tips.
    @ViewBuilder var tipJar: () -> TipJarView

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
                Text("\(practice ? "PRACTICE · " : "")\(request.what.uppercased()) · REF \(request.reference)")
                    .font(Theme.label(10))
                    .kerning(1.2)
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 6)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 12)

                    // Green once it goes negative: that figure is money coming back.
                    Text(Money.format(minor: outstanding))
                        .accessibilityIdentifier("outstandingAmount")
                        .font(Theme.display(46))
                        .foregroundStyle(isOverpaid ? Theme.credit : Theme.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: isOverpaid)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                tipJar()
            }

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

// MARK: - No bank yet

/// Signed in, but nothing connected — or everything disconnected. Someone
/// whose consent ran out after a year shouldn't be greeted as if they were
/// new, so the server is asked which it is.
private struct EmptyWallet: View {
    @EnvironmentObject private var wallet: WalletStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.webAuthenticationSession) private var web
    @State private var working = false
    @State private var message: String?
    @State private var bank: Me.Bank?

    private enum Situation { case unreachable, new, stoppedSharing, nothingShared }

    private var situation: Situation {
        if wallet.loadFailed { return .unreachable }
        guard let bank, bank.linked else { return .new }
        return bank.consent == nil ? .stoppedSharing : .nothingShared
    }

    private var title: String {
        switch situation {
        case .unreachable: "Couldn't reach your bank"
        case .new: "Nothing in your wallet yet"
        case .stoppedSharing: "Your bank stopped sharing"
        case .nothingShared: "No accounts to show"
        }
    }

    private var detail: String {
        switch situation {
        case .unreachable:
            "Check your connection and try again. Nothing has changed with your accounts."
        case .new:
            "Connect a bank and its balance turns into cash here. CashStack can only read it — your money stays where it is."
        case .stoppedSharing:
            "Sharing lasts up to 12 months, and ends early if it's stopped from your bank. Connect again to fill your wallet."
        case .nothingShared:
            "Your bank is connected but isn't sharing an everyday or savings account right now. Connect again to choose what it shares."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            Text(title)
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("emptyWalletTitle")
            Text(detail)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let message { Notice(text: message) }
            if working {
                Working(text: wallet.loadFailed ? "Trying again…" : "Fetching your accounts…")
            } else if wallet.loadFailed {
                PrimaryPillButton(title: "Try again", systemImage: "arrow.clockwise") {
                    working = true
                    Task {
                        await wallet.refreshQuietly()
                        working = false
                    }
                }
                .accessibilityIdentifier("retryLoad")
            } else {
                PrimaryPillButton(title: situation == .new ? "Connect a bank" : "Connect again", systemImage: "link") {
                    working = true
                    message = nil
                    Task {
                        switch await BankLink(api: session.api).run("connect", with: web) {
                        case .connected(let accounts): await wallet.connected(accounts)
                        case .cancelled: break
                        case .failed(let reason): message = reason
                        }
                        working = false
                    }
                }
                .accessibilityIdentifier("connectBankEmpty")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground)
        .task(id: wallet.loadFailed) {
            guard !wallet.loadFailed, let me: Me = try? await session.api.get("v1/me") else { return }
            bank = me.bank
        }
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
    var practice = false
    /// Set when the receipt holds the tip jar out for some of the change.
    var tipping: Tipping?
    var onTipJar: () -> Void = {}
    var onClose: () -> Void = {}

    struct Tipping {
        let isHovered: Bool
        let refusal: String?
        let closes: Date
        let duration: TimeInterval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.ink))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(practice ? "Practice: paid" : "Paid") \(Money.format(minor: transaction.amountMinor)) to \(transaction.merchant)")
                        .accessibilityIdentifier("receiptHeadline")
                        .font(Theme.title(14))
                        .foregroundStyle(Theme.ink)
                    Text(subline)
                        .accessibilityIdentifier("receiptDetail")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)

                if tipping != nil {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(PillBackground())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close receipt")
                }
            }

            if let tipping {
                TipJarButton(tipMinor: transaction.tipMinor,
                             isHovered: tipping.isHovered,
                             refusal: tipping.refusal,
                             wide: true,
                             action: onTipJar)
                Countdown(closes: tipping.closes, duration: tipping.duration)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FloatingCard())
    }

    private var subline: String {
        if practice { return "Nothing left your bank. It's your real balance, played with." }
        let change = transaction.changeMinor > 0
            ? "\(Money.format(minor: transaction.changeMinor)) change falling back in"
            : "Exact money — no change"
        guard transaction.tipMinor > 0 else { return change }
        return "\(change) · \(Money.format(minor: transaction.tipMinor)) tip"
    }
}
