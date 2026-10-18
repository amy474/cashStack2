import SwiftUI

// MARK: - Telling the scene where the jars are

/// Every jar on screen reports its frame here, so the physics scene can tell
/// when a held coin is over one. Views that leave the screen drop out of the
/// preference by themselves, so the scene never aims at a jar that has gone.
struct DropTargetFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Make this view somewhere a held piece of money can be dropped.
    func dropTarget(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: DropTargetFrames.self, value: [id: geo.frame(in: .global)])
            }
        }
    }
}

enum TipJar {
    /// The tip jar's drop target, whether it sits in the pay header or on the receipt.
    static let target = "tip"
    static let symbol = "face.smiling"
    static let tint = Color(rgb: 0xFFC400)
}

extension CoinJar {
    /// What happens to the money next — the line under the undo toast.
    var whatHappensNext: String {
        switch self {
        case .invest: "Buys at the next market open"
        case .donate: "Sent with the rest on \(Self.nextFirstOfMonth)"
        case .save:   "Moved across straight away"
        }
    }

    static var nextFirstOfMonth: String {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let next = calendar.date(byAdding: .month, value: 1, to: start) else { return "the 1st" }
        return next.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Pieces

/// A jar's colour and symbol in a hairline circle — the same shape as the
/// account dots, so it reads as part of the same chrome.
struct JarBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    init(jar: CoinJar, size: CGFloat = 28) {
        self.symbol = jar.symbol
        self.tint = jar.tint
        self.size = size
    }

    init(symbol: String, tint: Color, size: CGFloat = 28) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(tint)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.hairline))
            )
            .accessibilityHidden(true)
    }
}

/// Dashed while it is waiting for something, solid black once a piece is over
/// it — the same "armed" fill the pay pill uses.
struct DropZone: View {
    var isLit: Bool
    var cornerRadius: CGFloat = Theme.radiusCard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(isLit ? Theme.ink : Theme.ground.opacity(0.55))
            shape.strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: Theme.hairline,
                                                             dash: isLit ? [] : [5, 4]))
        }
    }
}

/// The frosted card that floats under the header: receipts, toasts, hints.
struct FloatingCard: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.ground.opacity(0.5)))
            .overlay(shape.strokeBorder(Theme.ink, lineWidth: Theme.hairline))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

// MARK: - The jars

/// What the header turns into while a coin is in the hand: one jar per
/// destination, big enough to hit without looking.
struct JarHeader: View {
    @EnvironmentObject private var wallet: WalletStore

    /// The piece in the hand, or nil for the beat after one has gone in.
    let held: Denomination?
    let hovered: String?
    let landed: CoinJar?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(allowance)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .monospacedDigit()
            }
            .padding(.top, 12)

            Text(held == nil ? " " : "Let go anywhere else to put it back")
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 3)

            Spacer(minLength: 10)

            HStack(spacing: 10) {
                ForEach(wallet.visibleJars) { jar in
                    JarCard(jar: jar,
                            destination: wallet.destination(of: jar),
                            monthMinor: wallet.monthTotal(jar),
                            refusal: wallet.refusal(jar, for: held),
                            isHovered: hovered == jar.rawValue,
                            didLand: landed == jar)
                        .dropTarget(jar.rawValue)
                }
            }
            .frame(height: 110)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
    }

    private var title: String {
        if let held { return "Drop the \(held.label) in a jar" }
        guard let landed else { return "In it goes" }
        if wallet.destination(of: landed) == nil { return "Where should it go?" }
        return wallet.lastDrop?.receipt ?? "In it goes"
    }

    private var allowance: String {
        guard let left = wallet.jarAllowanceLeftMinor else { return "No daily limit" }
        return "\(Money.format(minor: left)) left today"
    }
}

struct JarCard: View {
    let jar: CoinJar
    let destination: String?
    let monthMinor: Int
    let refusal: String?
    let isHovered: Bool
    let didLand: Bool

    private var isLit: Bool { isHovered && refusal == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                JarBadge(jar: jar)
                Spacer(minLength: 4)
                if monthMinor > 0 {
                    Text(Money.format(minor: monthMinor))
                        .font(Theme.title(12))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 6)
            Text(jar.title)
                .font(Theme.title(17))
            Text(refusal ?? destination ?? jar.choosePrompt)
                .font(Theme.body(11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(0.6)
        }
        .foregroundStyle(isLit ? Color.white : Theme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DropZone(isLit: isLit))
        .opacity(refusal == nil ? 1 : 0.45)
        .scaleEffect(isLit ? 1.04 : (didLand ? 0.97 : 1))
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isLit)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: didLand)
        .animation(.easeOut(duration: 0.2), value: monthMinor)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jar-\(jar.rawValue)")
    }
}

// MARK: - The tip jar

/// Out while paying at places that take tips, and on the receipt afterwards
/// for some of the change. Drop a coin on it, or tap it to pick one — the way
/// in for anyone who cannot drag.
struct TipJarButton: View {
    let tipMinor: Int
    let isHovered: Bool
    /// Why the piece in the hand would not go in, if it would not.
    let refusal: String?
    /// The receipt's version runs the width of the card.
    var wide = false
    var action: () -> Void

    private var isLit: Bool { isHovered && refusal == nil }

    var body: some View {
        Button(action: action) {
            Group {
                if wide { wideFace } else { compactFace }
            }
            .foregroundStyle(isLit ? Color.white : Theme.ink)
            .background(DropZone(isLit: isLit, cornerRadius: 14))
            .scaleEffect(isLit ? 1.05 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isLit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropTarget(TipJar.target)
        .accessibilityIdentifier("tipJar")
        .accessibilityLabel(tipMinor > 0 ? "Tip jar, \(Money.format(minor: tipMinor)) in it" : "Tip jar")
        .accessibilityHint("Drag a coin into it, or tap to choose one")
    }

    private var tipFigure: String {
        tipMinor > 0 ? "+" + Money.format(minor: tipMinor) : "Tip jar"
    }

    private var compactFace: some View {
        VStack(spacing: 3) {
            JarBadge(symbol: TipJar.symbol, tint: TipJar.tint, size: 24)
            Text(tipFigure)
                .font(Theme.title(13))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(refusal ?? (tipMinor > 0 ? "Tap to change" : "Optional"))
                .font(Theme.body(10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(0.6)
        }
        .frame(width: 96, height: 78)
        .opacity(refusal == nil ? 1 : 0.5)
    }

    private var wideFace: some View {
        HStack(spacing: 10) {
            JarBadge(symbol: TipJar.symbol, tint: TipJar.tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tip jar")
                    .font(Theme.title(14))
                Text(refusal ?? "Drop in some change, or tap to pick a coin")
                    .font(Theme.body(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(0.6)
            }
            Spacer(minLength: 4)
            if tipMinor > 0 {
                Text("+" + Money.format(minor: tipMinor))
                    .font(Theme.title(14))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .opacity(refusal == nil ? 1 : 0.5)
    }
}

/// Drains along the bottom of the receipt while the tip jar is out, so it is
/// plain how long it will stay. Full while a coin is in the hand.
struct Countdown: View {
    let closes: Date
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: closes == .distantFuture)) { context in
            let left = closes.timeIntervalSince(context.date)
            let fraction = closes == .distantFuture ? 1 : max(0, min(1, left / duration))
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.ink.opacity(0.3))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - After a drop

/// Says where the coin went and what happens to it next, with a way back.
struct DropToast: View {
    let drop: JarDrop
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            JarBadge(jar: drop.jar)
            VStack(alignment: .leading, spacing: 2) {
                Text(drop.receipt)
                    .accessibilityIdentifier("dropReceipt")
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(drop.jar.whatHappensNext)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            Button {
                Haptics.tap()
                onUndo()
            } label: {
                Text("Undo")
                    .font(Theme.title(13))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(PillBackground())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("undoDrop")
            .accessibilityLabel("Undo, take the \(drop.denomination.label) back")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FloatingCard())
    }
}

/// Shown until the first coin goes in a jar: the jars only appear once a coin
/// is picked up, so without this nobody would know they are there.
struct JarCoachMark: View {
    @EnvironmentObject private var wallet: WalletStore
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: -7) {
                ForEach(wallet.visibleJars) { JarBadge(jar: $0, size: 24) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Your coins can do more")
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.ink)
                Text("Hold a coin and drag it up into a jar to \(verbs).")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .background(PillBackground())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FloatingCard())
        .accessibilityIdentifier("jarCoachMark")
    }

    private var verbs: String {
        let words = wallet.visibleJars.map { jar -> String in
            switch jar {
            case .invest: "invest it"
            case .donate: "give it away"
            case .save:   "save it"
            }
        }
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " or " + words.last!
    }
}
