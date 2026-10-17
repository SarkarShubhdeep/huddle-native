import HuddleKit
import SwiftUI

/// Signed in: the five tabs in the dock, each with the team switcher and your
/// avatar in its navigation bar. Owns the shift model, so the timer strip
/// ticks on every tab.
struct MainShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .now
    @State private var now: NowModel?

    var body: some View {
        Group {
            if let now {
                AppDock(selection: $tab, liveStrip: { now.strip(at: $0) }, onStripAction: { stripAction(now) }) { tab in
                    NavigationStack {
                        TabRoot(tab: tab, onShowTimesheet: { self.tab = .time })
                            .navigationTitle(tab.title)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { TeamSwitcher() }
                                ToolbarItem(placement: .topBarTrailing) { AccountMenu() }
                            }
                    }
                }
                .environment(now)
                .sensoryFeedback(.success, trigger: now.completed)
                .sensoryFeedback(.error, trigger: now.actionError) { _, new in new != nil }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
            }
        }
        .task {
            if now == nil { now = model.makeNowModel() }
            await now?.data.load()
        }
        // Live data without a socket: refresh every 30 s while the app is in front.
        .task(id: scenePhase) {
            guard scenePhase == .active, let now else { return }
            await now.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await now.refresh()
            }
        }
    }

    /// The strip's one button: pause the ticket, end the break, or go pick a ticket.
    private func stripAction(_ now: NowModel) {
        switch now.strip(at: .now) {
        case .timing: Task { await now.pauseTimer() }
        case .onBreak: Task { await now.resume() }
        case .onShift: tab = .tickets
        case nil: break
        }
    }
}

/// Each tab's screen. Until its step lands, a placeholder that says which.
private struct TabRoot: View {
    let tab: AppTab
    var onShowTimesheet: () -> Void = {}
    @Environment(AppModel.self) private var model

    var body: some View {
        if tab == .now, model.team != nil {
            NowScreen(onShowTimesheet: onShowTimesheet)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
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
