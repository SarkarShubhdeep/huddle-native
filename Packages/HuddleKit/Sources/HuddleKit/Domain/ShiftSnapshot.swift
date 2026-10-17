import Foundation

/// Your shift as the widgets, Control Center and the Live Activity show it.
///
/// Running times are stored as reference dates ("worked time is now minus
/// `workingSince`"), so a widget can tick with `Text(timerInterval:)` without
/// being reloaded, and two snapshots of the same state compare equal.
public struct ShiftSnapshot: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable, Hashable {
        case offClock, working, onBreak, dayDone
    }

    public var phase: Phase
    /// The open shift's team, or the last shift's.
    public var teamId: String?
    public var teamName: String?

    /// Working: worked time is `now - workingSince`.
    public var workingSince: Date?
    /// Worked time when it isn't ticking (on break, or the day's total).
    public var workedSeconds: Int

    /// On break: when it began, and when it becomes an unpaid meal break.
    public var breakStart: Date?
    public var mealBreakAt: Date?

    public var ticketId: String?
    public var ticketTitle: String?
    /// A running ticket timer: today's ticket time is `now - ticketSince`.
    public var ticketSince: Date?
    /// Ticket time when it isn't ticking (paused by a break).
    public var ticketSeconds: Int

    public init(phase: Phase, teamId: String? = nil, teamName: String? = nil, workingSince: Date? = nil,
                workedSeconds: Int = 0, breakStart: Date? = nil, mealBreakAt: Date? = nil,
                ticketId: String? = nil, ticketTitle: String? = nil, ticketSince: Date? = nil, ticketSeconds: Int = 0) {
        self.phase = phase
        self.teamId = teamId
        self.teamName = teamName
        self.workingSince = workingSince
        self.workedSeconds = workedSeconds
        self.breakStart = breakStart
        self.mealBreakAt = mealBreakAt
        self.ticketId = ticketId
        self.ticketTitle = ticketTitle
        self.ticketSince = ticketSince
        self.ticketSeconds = ticketSeconds
    }

    public static let signedOut = ShiftSnapshot(phase: .offClock)

    public var isOnShift: Bool { phase == .working || phase == .onBreak }

    /// Worked seconds at `now`.
    public func worked(at now: Date) -> Int {
        if let workingSince { return max(0, Int(now.timeIntervalSince(workingSince))) }
        return workedSeconds
    }

    /// Ticket seconds today at `now`.
    public func ticket(at now: Date) -> Int {
        if let ticketSince { return max(0, Int(now.timeIntervalSince(ticketSince))) }
        return ticketSeconds
    }

    /// Builds the snapshot from what the backend returns.
    ///
    /// - Parameters:
    ///   - active: the open shift, if any.
    ///   - running: the running ticket timer, if any.
    ///   - entries: today's work items and their sessions.
    ///   - todayShifts: shifts that started today (for the day's total once it's over).
    public static func make(active: ClockEvent?, running: TimerSession?, entries: [DayEntry],
                            todayShifts: [ClockEvent], teamName: (String) -> String?, now: Date) -> ShiftSnapshot {
        if let active, active.endTime == nil {
            var snapshot = ShiftSnapshot(phase: .working, teamId: active.teamId, teamName: teamName(active.teamId))
            switch ShiftClock.phase(active) {
            case .onBreak:
                snapshot.phase = .onBreak
                snapshot.workedSeconds = ShiftClock.workSeconds(active, at: now)
                snapshot.breakStart = active.openBreak?.startTime
                snapshot.mealBreakAt = active.openBreak.map { $0.startTime.addingTimeInterval(ShiftClock.mealBreakThreshold) }
            default:
                snapshot.workingSince = active.startTime.addingTimeInterval(TimeInterval(active.deductedBreakSeconds))
            }

            if let running, let entry = entries.first(where: { $0.entry.id == running.workItemId }) {
                let closed = entry.sessions.filter { $0.id != running.id }.reduce(0) { $0 + $1.seconds(at: now) }
                snapshot.ticketId = entry.entry.ticketId
                snapshot.ticketTitle = entry.entry.displayTitle ?? "Ticket"
                snapshot.ticketSince = running.startTime.addingTimeInterval(-TimeInterval(closed))
            } else if snapshot.phase == .onBreak,
                      let paused = entries.max(by: { lastStop($0) < lastStop($1) }), lastStop(paused) != .distantPast {
                // A break pauses the ticket timer; show the ticket it paused.
                snapshot.ticketId = paused.entry.ticketId
                snapshot.ticketTitle = paused.entry.displayTitle ?? "Ticket"
                snapshot.ticketSeconds = paused.totalSeconds(at: now)
            }
            return snapshot
        }

        let finished = todayShifts.filter { $0.endTime != nil }
        guard let last = finished.max(by: { $0.startTime < $1.startTime }) else {
            return ShiftSnapshot(phase: .offClock)
        }
        return ShiftSnapshot(
            phase: .dayDone, teamId: last.teamId, teamName: teamName(last.teamId),
            workedSeconds: finished.reduce(0) { $0 + ShiftClock.workSeconds($1, at: now) }
        )
    }

    private static func lastStop(_ entry: DayEntry) -> Date {
        entry.sessions.compactMap(\.endTime).max() ?? .distantPast
    }
}
