import SwiftUI

/// A quiet, non-blocking banner shown when a refresh fails. The data under it
/// stays on screen; Retry runs the refresh again.
struct RefreshBanner: View {
    /// "Couldn't refresh. Showing data from 2 min ago."
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.m)
                    .frame(minHeight: 30)
                    .background(Palette.surface, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(Palette.breakText)
        .padding(.leading, 14)
        .padding(.trailing, Spacing.s)
        .padding(.vertical, Spacing.xxs)
        .background(Palette.breakSoft, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// A full-screen state with exactly one next step: empty lists, an unreachable
/// server, an error with nothing cached to show.
struct StatusView: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let systemImage: String
    let title: String
    let message: String
    /// Lime for empty-but-fine, neutral for problems.
    var tone: Tone = .neutral
    var primary: Action?
    var secondary: Action?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tone == .neutral ? Palette.textSecondary : tone.foreground)
                .frame(width: 64, height: 64)
                .background(tone == .neutral ? Palette.surface : tone.background, in: RoundedRectangle(cornerRadius: Radius.card))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            if let primary {
                Button(primary.title, action: primary.perform).buttonStyle(.primary)
            }
            if let secondary {
                Button(secondary.title, action: secondary.perform).buttonStyle(.quiet)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.margin)
        .frame(maxWidth: 360)
    }
}

extension StatusView {
    /// The server didn't answer and there's nothing cached to show.
    static func unreachable(host: String, onRetry: @escaping () -> Void, onChangeServer: @escaping () -> Void) -> StatusView {
        StatusView(
            systemImage: "server.rack",
            title: "Can't reach the server",
            message: "\(host) didn't answer. Check that the backend is running and that both devices are on the same Wi-Fi.",
            primary: Action(title: "Try again", perform: onRetry),
            secondary: Action(title: "Change server", perform: onChangeServer)
        )
    }

    /// No internet connection at all.
    static func offline(onRetry: @escaping () -> Void) -> StatusView {
        StatusView(
            systemImage: "wifi.slash",
            title: "You're offline",
            message: "Connect to Wi-Fi or cellular data, then try again.",
            primary: Action(title: "Try again", perform: onRetry)
        )
    }
}

struct StatesPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                RefreshBanner(message: "Couldn't refresh. Showing data from 2 min ago.", onRetry: {})
                    .padding(.horizontal, Spacing.margin)
                StatusView(systemImage: "list.bullet", title: "No tickets yet",
                           message: "Create one to start tracking time against it.", tone: .working,
                           primary: .init(title: "New ticket") {})
                StatusView.unreachable(host: "192.168.1.24:3100", onRetry: {}, onChangeServer: {})
                StatusView.offline(onRetry: {})
            }
            .padding(.vertical, Spacing.l)
        }
        .background(Palette.canvas)
    }
}

#Preview("Light") { StatesPreview() }
#Preview("Dark") { StatesPreview().preferredColorScheme(.dark) }
