import SwiftUI

/// A still piece of money with the same holographic sweep the physics scene
/// runs as a shader — a rainbow band travelling diagonally across the face.
///
/// The band is composited into its own group before being masked by the
/// artwork, otherwise the additive blend leaks past the note's edges and the
/// shine reads as a square sitting on top of the money.
struct MoneyThumb: View {
    let denomination: Denomination
    var height: CGFloat = 34
    var shimmerDelay: Double = 0

    @State private var phase: CGFloat = -1.1

    private var artwork: some View {
        Image(uiImage: MoneyArt.image(for: denomination))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }

    var body: some View {
        artwork
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: Color(rgb: 0xFF2E93).opacity(0.55), location: 0.30),
                            .init(color: Color(rgb: 0xFFFFFF).opacity(0.85), location: 0.50),
                            .init(color: Color(rgb: 0x00E6FF).opacity(0.60), location: 0.70),
                            .init(color: .clear, location: 1.00)
                        ],
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.55)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .mask(artwork)
            .onAppear {
                guard phase < 0 else { return }
                withAnimation(.linear(duration: 2.8).delay(shimmerDelay).repeatForever(autoreverses: false)) {
                    phase = 1.1
                }
            }
    }
}

/// Hairline pill. Every interactive surface in the chrome is one of these.
struct PillBackground: View {
    var filled = false
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(filled ? Theme.ink : .clear)
            Capsule(style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
        }
    }
}

struct PrimaryPillButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(Theme.title(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(PillBackground(filled: true))
        }
        .buttonStyle(.plain)
    }
}

struct GhostPillButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(Theme.body(14))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(PillBackground())
        }
        .buttonStyle(.plain)
    }
}

/// Two-up hairline segmented control: Loose / Sorted.
struct ModeSwitch: View {
    @Binding var selection: WalletMode
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WalletMode.allCases) { mode in
                let isOn = selection == mode
                Button {
                    guard !isOn else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.title)
                            .font(Theme.title(14))
                    }
                    .foregroundStyle(isOn ? .white : Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if isOn {
                            Capsule(style: .continuous)
                                .fill(Theme.ink)
                                .matchedGeometryEffect(id: "modePill", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: Theme.hairline)
        )
    }
}

enum WalletMode: String, CaseIterable, Identifiable {
    case loose
    case sorted

    var id: String { rawValue }
    var title: String { self == .loose ? "Loose" : "Sorted" }
    var symbol: String { self == .loose ? "water.waves" : "list.bullet" }
}
