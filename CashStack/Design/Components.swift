import SwiftUI

/// A holographic sweep for SwiftUI content — the sorted view's equivalent of
/// the shader running in the physics scene.
struct HoloSheen: ViewModifier {
    var delay: Double = 0
    var active: Bool = true
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear,
                                 Color(rgb: 0xFF2E93).opacity(0.55),
                                 Color(rgb: 0x00E6FF).opacity(0.75),
                                 Color(rgb: 0xFFF03D).opacity(0.6),
                                 .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: geo.size.width * 0.75)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .mask(content)
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 2.6).delay(delay).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func holoSheen(delay: Double = 0, active: Bool = true) -> some View {
        modifier(HoloSheen(delay: delay, active: active))
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

/// A piece of money drawn as a still image, for the sorted view and receipts.
struct MoneyThumb: View {
    let denomination: Denomination
    var height: CGFloat = 34
    var shimmerDelay: Double = 0

    var body: some View {
        Image(uiImage: MoneyArt.image(for: denomination))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .holoSheen(delay: shimmerDelay)
    }
}
