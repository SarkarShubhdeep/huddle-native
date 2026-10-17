import Foundation

/// One line of a day in the timesheet: a shift, a ticket timer inside it, or a break.
public struct TimelineItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case shift
        case ticket(title: String)
        /// `isMeal`: 20 minutes or more, unpaid. Nil while the break is still open.
        case rest(isMeal: Bool?)
    }

    public let id: String
    public let kind: Kind
    public let start: Date
    /// Nil while it's still running.
    public let end: Date?
    public let seconds: Int
}

/// Builds a day's timeline from the shifts in a timesheet: each shift that
/// started that day, followed by its ticket timers and breaks, newest first.
/// Running items count up to `now`.
public enum DayTimeline {
    public static func items(on day: Date, from sessions: [ClockEvent], calendar: Calendar, now: Date) -> [TimelineItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let shifts = sessions
            .filter { $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime > $1.startTime }

        return shifts.flatMap { shift -> [TimelineItem] in
            let head = TimelineItem(id: shift.id, kind: .shift, start: shift.startTime, end: shift.endTime,
                                    seconds: ShiftClock.workSeconds(shift, at: now))
            let tickets = shift.ticketSessions.map { session in
                TimelineItem(
                    id: "t-\(session.id)",
                    kind: .ticket(title: session.title ?? "Ticket"),
                    start: session.startTime, end: session.endTime,
                    seconds: session.durationSeconds ?? seconds(from: session.startTime, to: session.endTime ?? now)
                )
            }
            let breaks = shift.breaks.enumerated().map { index, item in
                TimelineItem(
                    id: "b-\(shift.id)-\(index)",
                    kind: .rest(isMeal: item.endTime == nil ? nil : (item.type.map { $0 == "meal" }
                        ?? (seconds(from: item.startTime, to: item.endTime!) >= Int(ShiftClock.mealBreakThreshold)))),
                    start: item.startTime, end: item.endTime,
                    seconds: seconds(from: item.startTime, to: item.endTime ?? now)
                )
            }
            return [head] + (tickets + breaks).sorted { $0.start > $1.start }
        }
    }

    private static func seconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded(.down)))
    }
}
