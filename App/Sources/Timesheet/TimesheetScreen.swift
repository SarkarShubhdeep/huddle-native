import HuddleKit
import SwiftUI

/// One week: ticket time per day (as the web app's Work page counts it) and
/// the shifts behind it, for the day detail.
struct WeekSheet: Codable, Sendable {
    var days: [WeekDay]
    var shifts: [ClockEvent]
}

/// The Time tab: the week's total and daily bars, then the picked day's
/// shifts, ticket timers and breaks, edge to edge.
struct TimesheetScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now

    @State private var weekStart = WorkDay().startOfWeek(.now)
    @State private var selected = 0
    @State private var sheet: Resource<WeekSheet>?

    private var workDay: WorkDay { now.workDay }
    private var isThisWeek: Bool { weekStart == workDay.startOfWeek(.now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let sheet, sheet.value != nil, sheet.error != nil {
                    RefreshBanner(message: "Couldn’t refresh the timesheet.") { await timedRefresh("Time") { await sheet.refresh() } }
                }
                if let value = sheet?.value {
                    WeekBars(days: barDays(value), selectedIndex: $selected, caption: caption(value),
                             title: isThisWeek ? "This week" : weekTitle(weekStart))
                    dayDetail(value)
                } else if let sheet, sheet.error != nil {
                    StatusView.unreachable(
                        host: app.session.session?.endpoint.baseURL.host() ?? "The server",
                        onRetry: { Task { await sheet.refresh() } },
                        onChangeServer: { app.signOut() }
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.l)
        }
        .background(Palette.canvas)
        .refreshable { await timedRefresh("Time") { await sheet?.refresh() } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { weekMenu }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Previous week", systemImage: "chevron.left") { move(by: -1) }
                Button("Next week", systemImage: "chevron.right") { move(by: 1) }
                    .disabled(isThisWeek)
            }
        }
        .task(id: weekStart) { await load() }
        // After a clock or timer action anywhere, this week's numbers change.
        .onChange(of: now.completed) { if isThisWeek { Task { await sheet?.refetch() } } }
    }

    // MARK: Week

    private var weekMenu: some View {
        Menu {
            ForEach(0..<6) { back in
                let start = workDay.calendar.date(byAdding: .weekOfYear, value: -back, to: workDay.startOfWeek(.now))!
                Button(back == 0 ? "This week" : (back == 1 ? "Last week" : weekTitle(start))) { weekStart = start }
            }
        } label: {
            HStack(spacing: 6) {
                Text(weekTitle(weekStart)).font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.xs)
        }
        .accessibilityLabel("Week")
        .accessibilityValue(weekTitle(weekStart))
    }

    private func move(by weeks: Int) {
        if let next = workDay.calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart),
           next <= workDay.startOfWeek(.now) {
            weekStart = next
        }
    }

    private func load() async {
        guard let api = app.api, let userId = app.userId else { return }
        let start = weekStart
        let end = workDay.calendar.date(byAdding: .day, value: 7, to: start)!
        let key = workDay.key(for: start)
        let timers = TimerService(api)
        let clock = ClockService(api)
        let resource = Resource<WeekSheet>(cacheKey: "week.\(userId).\(key)", store: app.snapshotStore) {
            async let days = timers.week(starting: key)
            async let sheet = clock.timesheet(userId: userId, from: start, to: end)
            return try await WeekSheet(days: days, shifts: sheet.sessions)
        }
        sheet = resource
        // Today on this week; otherwise the last day with time, else Monday.
        if isThisWeek {
            selected = max(0, (workDay.calendar.dateComponents([.day], from: start, to: workDay.startOfDay(.now)).day ?? 0))
        }
        await resource.load()
        if !isThisWeek, let days = resource.value?.days {
            selected = days.lastIndex { $0.totalSeconds > 0 } ?? 0
        }
    }

    // MARK: Bars

    private func dates(_ value: WeekSheet) -> [Date] {
        (0..<7).compactMap { workDay.calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func barDays(_ value: WeekSheet) -> [WeekBars.Day] {
        let seconds = Dictionary(value.days.map { ($0.date, $0.totalSeconds) }, uniquingKeysWith: { a, _ in a })
        return dates(value).map { date in
            WeekBars.Day(shortName: String(date.formatted(.dateTime.weekday(.narrow))),
                         fullName: date.formatted(.dateTime.weekday(.wide).month().day()),
                         seconds: seconds[workDay.key(for: date)] ?? 0)
        }
    }

    private func caption(_ value: WeekSheet) -> String {
        let worked = value.days.filter { $0.totalSeconds > 0 }
        guard !worked.isEmpty else { return "No ticket time yet" }
        let average = worked.reduce(0) { $0 + $1.totalSeconds } / worked.count
        return "\(worked.count) \(worked.count == 1 ? "day" : "days") · avg \(ShiftClockFormat.duration(average))"
    }

    // MARK: Day detail

    @ViewBuilder private func dayDetail(_ value: WeekSheet) -> some View {
        let day = dates(value)[min(selected, 6)]
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let items = DayTimeline.items(on: day, from: value.shifts, calendar: workDay.calendar, now: context.date)
            let shiftSeconds = items.filter { $0.kind == .shift }.reduce(0) { $0 + $1.seconds }
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: day.formatted(.dateTime.weekday(.wide)),
                              detail: items.isEmpty ? nil : "\(ShiftClockFormat.duration(shiftSeconds))\(items.contains { $0.end == nil } ? " so far" : "") on shift")
                    .padding(.top, Spacing.xs)
                if items.isEmpty {
                    Text(day > .now ? "Nothing yet." : "No shifts this day.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                } else {
                    EdgeToEdgeList {
                        ForEach(items) { item in row(item) }
                    }
                    .padding(.horizontal, -Spacing.margin)
                }
            }
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        let (title, tone, emphasized): (String, Tone, Bool) = switch item.kind {
        case .shift: ("Shift", .working, true)
        case let .ticket(name): (name, item.end == nil ? .working : .neutral, false)
        case .rest(isMeal: nil): ("On break", .onBreak, false)
        case .rest(isMeal: true?): ("Meal break · unpaid", .onBreak, false)
        case .rest(isMeal: false?): ("Rest break · paid", .onBreak, false)
        }
        return TimeRow(title: title, when: range(item), duration: hoursMinutes(item.seconds), tone: tone, isEmphasized: emphasized)
    }

    // MARK: Text

    private func range(_ item: TimelineItem) -> String {
        let start = item.start.formatted(date: .omitted, time: .shortened)
        guard let end = item.end else { return "\(start) – now" }
        // Ran past midnight: say which day it ended.
        let endText = workDay.calendar.isDate(end, inSameDayAs: item.start)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(start) – \(endText)"
    }

    private func hoursMinutes(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    private func weekTitle(_ start: Date) -> String {
        let end = workDay.calendar.date(byAdding: .day, value: 6, to: start)!
        let sameMonth = workDay.calendar.isDate(start, equalTo: end, toGranularity: .month)
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
