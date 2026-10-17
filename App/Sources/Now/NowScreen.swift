import HuddleKit
import SwiftUI

/// The Now tab: one card that says where you are in your day and offers the
/// one thing to do next, the ticket being timed, and today's work.
struct NowScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now
    var onShowTimesheet: () -> Void = {}

    @State private var showPlan = false
    @State private var showWrapUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let error = now.data.error, now.data.value != nil {
                    RefreshBanner(message: banner(for: error)) { Task { await now.refresh() } }
                }
                if let message = now.actionError {
                    InlineError(message: message)
                }
                if now.data.value == nil, let error = now.data.error {
                    StatusView.unreachable(
                        host: app.session.session?.endpoint.baseURL.host() ?? "The server",
                        onRetry: { Task { await now.refresh() } },
                        onChangeServer: { app.signOut() }
                    )
                    .accessibilityHint(error.localizedDescription)
                    .frame(maxWidth: .infinity)
                } else if now.data.value == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: Spacing.l) {
                            hero(at: context.date)
                            ticketCard(at: context.date)
                        }
                    }
                    today
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.l)
            .springAnimation(value: now.phase)
        }
        .background(Palette.canvas)
        .refreshable { await now.refresh() }
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .sheet(isPresented: $showPlan) {
            PlanSheet(teamName: app.team?.name ?? "Your team") { plan in
                guard let teamId = app.team?.id else { return false }
                return await now.startDay(teamId: teamId, plan: plan)
            }
        }
        .sheet(isPresented: $showWrapUp) {
            WrapUpSheet(requiresWrapUp: activeTeam?.requiresPlan ?? false)
        }
    }

    // MARK: Hero

    private var activeTeam: Team? {
        guard let teamId = now.active?.teamId else { return nil }
        return app.teams?.value?.first { $0.id == teamId }
    }

    @ViewBuilder private func hero(at date: Date) -> some View {
        let busy = now.pending != nil
        switch now.phase {
        case .idle:
            let yesterday = now.workDay.calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let yesterdaySeconds = now.workDay.workedSeconds(on: yesterday, in: now.data.value?.week ?? [], now: date)
            NowHero(
                phase: .idle, time: "0:00",
                timeAccessibilityLabel: "Not started",
                subtitle: yesterdaySeconds > 0 ? "Yesterday you worked \(ShiftClockFormat.duration(yesterdaySeconds))." : "Not started today",
                facts: [
                    .init(label: "Yesterday", value: ShiftClockFormat.duration(yesterdaySeconds)),
                    .init(label: "This week", value: ShiftClockFormat.duration(weekSeconds(at: date))),
                    .init(label: "Team", value: app.team?.name ?? "–"),
                ],
                primaryTitle: "Start day",
                primaryAction: startDay,
                isBusy: busy
            )
        case .working:
            let active = now.active
            let worked = ShiftClock.workSeconds(active, at: date)
            NowHero(
                phase: .working, time: ShiftClockFormat.clock(worked),
                timeAccessibilityLabel: "Worked \(ShiftClockFormat.spoken(worked))",
                subtitle: sinceLine(active),
                facts: [
                    .init(label: "Started", value: active.map { $0.startTime.formatted(date: .omitted, time: .shortened) } ?? "–"),
                    .init(label: "Breaks", value: ShiftClockFormat.duration(active?.totalBreakSeconds ?? 0)),
                    .init(label: "Tickets", value: "\(now.entries.count)"),
                ],
                primaryTitle: "Take a break",
                primaryAction: { Task { await now.takeBreak() } },
                onEndDay: { showWrapUp = true },
                isBusy: busy
            )
        case .onBreak:
            let active = now.active
            let breakSeconds = ShiftClock.breakSeconds(active, at: date) ?? 0
            let countdown = ShiftClock.mealBreakCountdown(active, at: date) ?? 0
            NowHero(
                phase: .onBreak, time: ShiftClockFormat.clock(breakSeconds),
                timeAccessibilityLabel: "On break for \(ShiftClockFormat.spoken(breakSeconds))",
                subtitle: now.pausedEntry != nil ? "Your ticket timer is paused." : "Enjoy the break.",
                facts: [
                    countdown > 0
                        ? .init(label: "Meal break in", value: "\(Int((countdown / 60).rounded(.up))) min")
                        : .init(label: "Meal break", value: "Unpaid"),
                    .init(label: "Worked", value: ShiftClockFormat.duration(ShiftClock.workSeconds(active, at: date))),
                    .init(label: "Since", value: active?.openBreak.map { $0.startTime.formatted(date: .omitted, time: .shortened) } ?? "–"),
                ],
                primaryTitle: "Back to work",
                primaryAction: { Task { await now.resume() } },
                isBusy: busy
            )
        case .ended:
            // The whole day, which may be more than one shift.
            let shifts = todaysShifts(at: date)
            let worked = now.workDay.workedSeconds(in: shifts, now: date)
            let unpaid = shifts.reduce(0) { $0 + $1.deductedBreakSeconds }
            NowHero(
                phase: .ended, time: String(format: "%d:%02d", worked / 3600, (worked % 3600) / 60),
                timeAccessibilityLabel: "Worked \(ShiftClockFormat.spoken(worked))",
                subtitle: dayRange(shifts),
                facts: [
                    .init(label: "Unpaid meal", value: ShiftClockFormat.duration(unpaid)),
                    .init(label: "Tickets", value: "\(now.entries.count)"),
                    .init(label: "This week", value: ShiftClockFormat.duration(weekSeconds(at: date))),
                ],
                primaryTitle: "See timesheet",
                primaryAction: onShowTimesheet,
                onStartAgain: startDay,
                isBusy: busy
            )
        }
    }

    @ViewBuilder private func ticketCard(at date: Date) -> some View {
        if let entry = now.runningEntry {
            TicketTimerCard(title: entry.entry.displayTitle ?? "Ticket",
                            time: ShiftClockFormat.clock(entry.totalSeconds(at: date))) {
                Task { await now.pauseTimer() }
            }
        } else if let entry = now.pausedEntry {
            TicketTimerCard(title: entry.entry.displayTitle ?? "Ticket",
                            time: ShiftClockFormat.clock(entry.totalSeconds(at: date)), isPaused: true)
        }
    }

    // MARK: Today

    private var today: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            let total = now.entries.reduce(0) { $0 + $1.totalSeconds(at: .now) }
            SectionHeader(title: "Today",
                          detail: now.entries.isEmpty ? nil : "\(now.entries.count) \(now.entries.count == 1 ? "ticket" : "tickets") · \(ShiftClockFormat.duration(total))")
                .padding(.top, Spacing.xs)
            if now.entries.isEmpty {
                Text(now.active != nil ? "No ticket time yet. Start a timer from Tickets." : "No ticket time today.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.xs)
            } else {
                EdgeToEdgeList {
                    ForEach(now.entries, id: \.entry.id) { entry in
                        WorkRow(title: entry.entry.displayTitle ?? "Ticket",
                                duration: hoursMinutes(entry.totalSeconds(at: .now)),
                                isActive: entry.entry.id == now.runningEntry?.entry.id)
                    }
                }
                .padding(.horizontal, -Spacing.margin)
            }
        }
    }

    // MARK: Helpers

    private func startDay() {
        if app.team?.requiresPlan == true {
            showPlan = true
        } else if let teamId = app.team?.id {
            Task { await now.startDay(teamId: teamId, plan: nil) }
        }
    }

    private func weekSeconds(at date: Date) -> Int {
        now.workDay.workedSeconds(in: now.data.value?.week ?? [], now: date)
    }

    private func sinceLine(_ active: ClockEvent?) -> String {
        guard let active else { return "" }
        let since = "Since \(active.startTime.formatted(date: .omitted, time: .shortened))"
        guard active.teamId != app.team?.id, let team = activeTeam else { return since }
        return "\(since) · \(team.name)"
    }

    private func todaysShifts(at date: Date) -> [ClockEvent] {
        let today = now.workDay.startOfDay(date)
        return (now.data.value?.week ?? []).filter { $0.startTime >= today }.sorted { $0.startTime < $1.startTime }
    }

    /// "9:02 AM – 5:21 PM", plus how many shifts when there was more than one.
    private func dayRange(_ shifts: [ClockEvent]) -> String {
        guard let first = shifts.first, let last = shifts.last else { return "" }
        let text = range(first.startTime, last.endTime)
        return shifts.count > 1 ? "\(text) · \(shifts.count) shifts" : text
    }

    private func range(_ start: Date, _ end: Date?) -> String {
        let s = start.formatted(date: .omitted, time: .shortened)
        return "\(s) – \(end?.formatted(date: .omitted, time: .shortened) ?? "now")"
    }

    private func hoursMinutes(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    private func banner(for error: APIError) -> String {
        guard let updated = now.data.lastUpdated else { return "Couldn’t refresh." }
        return "Couldn’t refresh. Showing data from \(updated.formatted(.relative(presentation: .named)))."
    }
}
