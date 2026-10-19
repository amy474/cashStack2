import AuthenticationServices
import SwiftUI

/// First run, in four steps: sign in, lock, connect a bank, pick the account
/// that fills the wallet. Each step says plainly what happens next, and the
/// bank step says what is shared, with whom, and how to stop — before anyone
/// leaves the app for Basiq.
struct OnboardingFlow: View {

    enum Step: Hashable {
        case welcome
        case lock
        case connect
        case pick([LinkedAccount])
    }

    @EnvironmentObject private var session: SessionStore
    @AppStorage(Preference.onboarded) private var onboarded = false
    @AppStorage(Preference.demo) private var demo = false
    @State private var step: Step

    init(signedIn: Bool) {
        let lockSettled = UserDefaults.standard.bool(forKey: Preference.lockDecided) || !DeviceLock.isAvailable
        _step = State(initialValue: !signedIn ? .welcome : lockSettled ? .connect : .lock)
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            switch step {
            case .welcome:
                WelcomeStep(onDemo: { demo = true })
            case .lock:
                LockStep { advance(from: .lock) }
            case .connect:
                ConnectStep(onConnected: { step = .pick($0) },
                            onLater: { onboarded = true })
            case .pick(let accounts):
                PickStep(accounts: accounts) { chosen in
                    UserDefaults.standard.set(chosen, forKey: Preference.selectedAccountID)
                    onboarded = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .onChange(of: session.state) { _, state in
            if state == .signedIn, step == .welcome { advance(from: .welcome) }
        }
    }

    private func advance(from current: Step) {
        switch current {
        case .welcome:
            step = (UserDefaults.standard.bool(forKey: Preference.lockDecided) || !DeviceLock.isAvailable) ? .connect : .lock
        case .lock:
            step = .connect
        default:
            break
        }
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    @EnvironmentObject private var session: SessionStore
    var onDemo: () -> Void
    @State private var signingIn = false

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                MoneyFan()
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                Text("Your bank balance, as cash.")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)

                Text("CashStack shows the money in your account as notes and coins you can pile up, sort and count out at the till.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        } actions: {
            if let message = session.errorMessage {
                Notice(text: message)
            }

            SignInWithAppleButton(.continue) { request in
                session.prepare(request)
            } onCompletion: { result in
                signingIn = true
                Task {
                    await session.complete(result)
                    signingIn = false
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(Capsule(style: .continuous))
            .disabled(signingIn)
            .accessibilityIdentifier("signInWithApple")

            GhostPillButton(title: "Try it with pretend money", systemImage: "sparkles") { onDemo() }
                .frame(maxWidth: .infinity)

            if AppConfig.offersDevelopmentSignIn {
                Button("Developer sign-in (local server)") {
                    Task { await session.signInForDevelopment() }
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("developerSignIn")
            }

            Text("Read-only. CashStack can see your balance; it can't move your money.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A $100, $50 and $20 fanned out, with a couple of coins — the same artwork
/// as the wallet, so the first screen already looks like the app.
private struct MoneyFan: View {
    var body: some View {
        ZStack {
            note(10_000, angle: -14, x: -38, y: 10)
            note(5_000, angle: -2, x: 0, y: -6)
            note(2_000, angle: 11, x: 40, y: 8)
            if let two = Denomination.all.first(where: { $0.minor == 200 }) {
                MoneyThumb(denomination: two, height: 64, shimmerDelay: 0.9)
                    .offset(x: 112, y: 72)
            }
            if let fifty = Denomination.all.first(where: { $0.minor == 50 }) {
                MoneyThumb(denomination: fifty, height: 58, shimmerDelay: 1.3)
                    .offset(x: -118, y: 78)
            }
        }
    }

    @ViewBuilder private func note(_ minor: Int, angle: Double, x: CGFloat, y: CGFloat) -> some View {
        if let denomination = Denomination.all.first(where: { $0.minor == minor }) {
            MoneyThumb(denomination: denomination, height: 112, shimmerDelay: Double(minor % 7) * 0.2)
                .rotationEffect(.degrees(angle))
                .offset(x: x, y: y)
        }
    }
}

// MARK: - Lock

private struct LockStep: View {
    @EnvironmentObject private var session: SessionStore
    var onDone: () -> Void

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                StepIcon(systemName: DeviceLock.name == "Touch ID" ? "touchid" : "faceid")
                Text("Keep your balance behind \(DeviceLock.name)")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                Text("Your wallet stays hidden until it's you holding the phone. It locks again a minute after you leave the app.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        } actions: {
            if let message = session.errorMessage { Notice(text: message) }
            PrimaryPillButton(title: "Use \(DeviceLock.name)", systemImage: "lock") {
                Task {
                    await session.setLock(true)
                    if session.lockEnabled { onDone() }
                }
            }
            .accessibilityIdentifier("enableLock")
            GhostPillButton(title: "Not now") {
                Task {
                    await session.setLock(false)
                    onDone()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Connect a bank

private struct ConnectStep: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.webAuthenticationSession) private var web
    var onConnected: ([LinkedAccount]) -> Void
    var onLater: () -> Void

    @State private var working = false
    @State private var message: String?

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                StepIcon(systemName: "building.columns")
                Text("Connect your bank")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 24)
                Text("Your bank shares your balance with CashStack through Basiq, under Australia's Consumer Data Right.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    Hairline().padding(.top, 22)
                    FactRow(symbol: "eye",
                            title: "What CashStack sees",
                            text: "Account names, the last four digits and balances. Your bank's screen lists exactly what you're sharing, and for how long.")
                    Hairline().opacity(0.12)
                    FactRow(symbol: "hand.raised",
                            title: "What it can't do",
                            text: "Move money or see your bank login. Paying at the till in CashStack is practice.")
                    Hairline().opacity(0.12)
                    FactRow(symbol: "checkmark.shield",
                            title: "Who connects",
                            text: "Basiq, an accredited data recipient. You'll see Basiq's screens, then your bank's own login.")
                    Hairline().opacity(0.12)
                    FactRow(symbol: "xmark.circle",
                            title: "Stop any time",
                            text: "From Accounts › Data sharing in CashStack, or from your bank's app.")
                    Hairline()
                }

                Link(destination: AppConfig.dataSharingURL) {
                    HStack(spacing: 5) {
                        Text("How data sharing works")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(Theme.title(13))
                    .foregroundStyle(Theme.ink)
                    .underline()
                }
                .padding(.top, 14)
            }
        } actions: {
            if let message { Notice(text: message) }
            if working {
                Working(text: "Fetching your accounts…")
            } else {
                PrimaryPillButton(title: "Connect a bank", systemImage: "link") { connect() }
                    .accessibilityIdentifier("connectBank")
                GhostPillButton(title: "Do this later") { onLater() }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func connect() {
        message = nil
        working = true
        Task {
            let outcome = await BankLink(api: session.api).run("connect", with: web)
            working = false
            switch outcome {
            case .connected(let accounts) where !accounts.isEmpty:
                Haptics.success()
                onConnected(accounts)
            case .connected:
                message = "That bank didn't share an everyday or savings account. Try another, or connect later."
            case .cancelled:
                message = "No bank connected yet."
            case .failed(let reason):
                message = reason
            }
        }
    }
}

// MARK: - Pick the wallet account

private struct PickStep: View {
    let accounts: [LinkedAccount]
    var onDone: (String) -> Void
    @State private var chosen: String?

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                Text("Which account is your wallet?")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Its balance becomes the pile of cash. You can switch whenever you like.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                Hairline()
                ForEach(accounts) { account in
                    AccountRow(account: account, isSelected: account.id == (chosen ?? accounts.first?.id)) {
                        Haptics.tap()
                        chosen = account.id
                    }
                    .padding(.horizontal, -20)
                    Hairline().opacity(0.12)
                }
            }
        } actions: {
            PrimaryPillButton(title: "Fill my wallet", systemImage: "arrow.down") {
                if let id = chosen ?? accounts.first?.id { onDone(id) }
            }
            .accessibilityIdentifier("fillWallet")
        }
    }
}

// MARK: - Locked

/// The whole app, locked. Face ID is asked for straight away; the button is
/// there for when it was dismissed.
struct LockView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    /// Face ID's own sheet makes the app inactive and active again, so
    /// prompting on every return to active would loop after a cancel.
    @State private var prompted = false

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                StepIcon(systemName: "lock")
                Text("CashStack is locked")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 24)
                Text("Unlock to see your wallet.")
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 10)
            }
        } actions: {
            PrimaryPillButton(title: "Unlock with \(DeviceLock.name)", systemImage: "lock.open") {
                Task { await session.unlock() }
            }
            .accessibilityIdentifier("unlock")
            Button("Sign out") { Task { await session.signOut() } }
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
        }
        .task(id: scenePhase) {
            if scenePhase == .background { prompted = false }
            guard scenePhase == .active, !prompted else { return }
            prompted = true
            await session.unlock()
        }
    }
}

/// Covers the wallet whenever the app isn't frontmost, so balances don't
/// show in the app switcher.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            Text("CASHSTACK")
                .font(Theme.label(13))
                .kerning(3)
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Pieces

/// Content up top, scrolling if it has to; actions pinned to the bottom.
struct OnboardingPage<Content: View, Actions: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CASHSTACK")
                    .font(Theme.label(11))
                    .kerning(2.4)
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) { actions() }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .background(alignment: .top) { Hairline().opacity(0.12) }
        }
        .background(Theme.ground)
    }
}

private struct StepIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(Theme.ink)
            .frame(width: 64, height: 64)
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
            .accessibilityHidden(true)
    }
}

private struct FactRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// A short message in a hairline card — errors and "nothing happened" notes.
struct Notice: View {
    let text: String
    /// Over the pile, it floats on frosted glass like the receipt does.
    var floating = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(Theme.body(13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, floating ? 14 : 11)
        .background {
            if floating {
                FloatingCard()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
            }
        }
        .accessibilityIdentifier("notice")
    }
}

struct Working: View {
    let text: String
    @State private var spin = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: Theme.line, lineCap: .round))
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                }
            Text(text)
                .font(Theme.title(15))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(PillBackground())
        .accessibilityElement(children: .combine)
    }
}
