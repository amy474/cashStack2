import SwiftUI

/// The whole app, stopped by the server: this build is too old, or the
/// server is down for maintenance. Nothing would work until the notice
/// clears, so it takes the place of everything rather than letting each
/// request fail on its own.
struct ServiceNoticeView: View {
    let notice: ServiceNotice
    /// Ask the server again.
    var onRetry: () async -> Void
    /// Maintenance only: play with pretend money in the meantime.
    var onDemo: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var checking = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            page
        }
    }

    private var page: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                StepIcon(systemName: notice.isMaintenance ? "wrench.and.screwdriver" : "arrow.down.app")
                Text(notice.isMaintenance ? "Back soon" : "Time to update")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 24)
                    .accessibilityIdentifier("serviceNoticeTitle")
                Text(message)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityIdentifier("serviceNoticeMessage")
            }
        } actions: {
            switch notice {
            case .updateRequired(_, let url):
                if let url {
                    PrimaryPillButton(title: "Update CashStack", systemImage: "arrow.down.circle") { openURL(url) }
                        .accessibilityIdentifier("updateApp")
                } else {
                    Text("Update CashStack from the App Store or TestFlight.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            case .maintenance:
                if checking {
                    Working(text: "Checking…")
                } else {
                    PrimaryPillButton(title: "Try again", systemImage: "arrow.clockwise") { retry() }
                        .accessibilityIdentifier("retryService")
                }
                GhostPillButton(title: "Try it with pretend money", systemImage: "sparkles") { onDemo() }
                    .frame(maxWidth: .infinity)
            }
        }
        // Maintenance ends by itself; look again every minute while it lasts.
        .task(id: notice.isMaintenance) {
            guard notice.isMaintenance else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await onRetry()
            }
        }
    }

    private var message: String {
        switch notice {
        case .updateRequired(let message, _), .maintenance(let message): message
        }
    }

    private func retry() {
        checking = true
        Task {
            await onRetry()
            checking = false
        }
    }
}
