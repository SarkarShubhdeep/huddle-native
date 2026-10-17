import HuddleKit
import SwiftUI

/// Signed in: the five tabs in the dock, each with the team switcher and your
/// avatar in its navigation bar.
struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .now

    var body: some View {
        AppDock(selection: $tab, strip: nil) { tab in
            NavigationStack {
                TabRoot(tab: tab)
                    .navigationTitle(tab.title)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { TeamSwitcher() }
                        ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
                    }
            }
        }
    }
}

/// Each tab's screen. Until its step lands, a placeholder that says which.
private struct TabRoot: View {
    let tab: AppTab
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let teams = model.teams, teams.value == nil, let error = teams.error {
                StatusView.unreachable(
                    host: model.session.session?.endpoint.baseURL.host() ?? "The server",
                    onRetry: { Task { await model.refreshTeams() } },
                    onChangeServer: { model.signOut() }
                )
                .accessibilityHint(error.localizedDescription)
            } else if model.team == nil {
                ProgressView()
            } else {
                StatusView(systemImage: tab.systemImage, title: model.team?.name ?? tab.title, message: placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clearsDock()
        .background(Palette.canvas)
    }

    private var placeholder: String {
        switch tab {
        case .now: "Your shift and today’s work arrive in Step 5."
        case .tickets: "Tickets and timers arrive in Step 6."
        case .huddle: "The team feed arrives in Step 8."
        case .time: "Your timesheet arrives in Step 7."
        case .inbox: "Notifications arrive in Step 9."
        }
    }
}

/// The team name in the navigation bar; tap to switch teams.
struct TeamSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let teams = model.teams?.value ?? []
        Menu {
            Picker("Team", selection: Binding(
                get: { model.team?.id ?? "" },
                set: { id in if let team = teams.first(where: { $0.id == id }) { model.select(team) } }
            )) {
                ForEach(teams) { team in
                    Text(team.isPersonal ? "\(team.name) (personal)" : team.name).tag(team.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.team?.name ?? "Teams")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.xs)
        }
        .disabled(teams.count < 2)
        .accessibilityLabel("Team")
        .accessibilityValue(model.team?.name ?? "None")
        .accessibilityHint(teams.count < 2 ? "" : "Switches the team you’re looking at")
    }
}

/// Your avatar; for now, who and where you're signed in, and Sign out.
/// Profile and settings arrive in Step 9.
struct AccountMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section {
                if let me = model.me { Text(me.displayName) }
                if let host = model.session.session?.endpoint.baseURL.host() { Text(host) }
            }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                model.signOut()
            }
        } label: {
            Avatar(initials: model.me?.initials ?? "", size: 32, isMe: true)
                .overlay {
                    if model.me == nil {
                        Image(systemName: "person.fill").font(.footnote).foregroundStyle(Palette.limeText)
                    }
                }
        }
        .accessibilityLabel("Profile and settings")
    }
}
