import Foundation

/// Calendar helpers in the user's time zone, matching the web app's
/// `toDateString` (`YYYY-MM-DD`) and its Monday-first weeks.
public struct WorkDay: Sendable {
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
    }

    /// `2026-10-17`, the key the backend uses for posts and work items.
    public func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Midnight on the Monday of `date`'s week.
    public func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Worked seconds of the shifts that started on `day`. An open shift counts
    /// up to `now`.
    public func workedSeconds(on day: Date, in sessions: [ClockEvent], now: Date) -> Int {
        let start = startOfDay(day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return sessions
            .filter { $0.startTime >= start && $0.startTime < end }
            .reduce(0) { $0 + ShiftClock.workSeconds($1, at: now) }
    }

    /// Worked seconds of every shift in `sessions` (a week's timesheet).
    public func workedSeconds(in sessions: [ClockEvent], now: Date) -> Int {
        sessions.reduce(0) { $0 + ShiftClock.workSeconds($1, at: now) }
    }
}

/// The text saved when a wrap-up is posted.
///
/// `huddle.updatePost` replaces a post's text, so a wrap-up added to a plan
/// keeps the plan and appends the wrap-up under it. Without a plan the
/// wrap-up stands alone, in the same "**Wrap-up:**" form the web app uses.
public enum WrapUpText {
    public static func compose(plan: String?, note: String) -> String {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wrapUp = "**Wrap-up:** \(note)"
        return plan.isEmpty ? wrapUp : "\(plan)\n\n\(wrapUp)"
    }
}
