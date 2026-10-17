import Foundation

public enum ShiftPhase: Sendable, Equatable {
    case idle
    case working
    case onBreak
    case ended
}

/// Shift time computed on the device between refreshes, so the timer ticks without
/// a live socket. Mirrors the web app's `getActiveClockSeconds`:
///
/// - paused: the server's `workSeconds` snapshot, frozen;
/// - working: whole seconds since `startTime`, minus `deductedBreakSeconds`.
///
/// Only meal breaks (20 min or more) are deducted. When a shorter break ends it
/// counts as paid work, so the timer jumps forward by the break's length.
public enum ShiftClock {
    /// A break this long or longer is an unpaid meal break.
    public static let mealBreakThreshold: TimeInterval = 20 * 60

    public static func phase(_ event: ClockEvent?) -> ShiftPhase {
        guard let event else { return .idle }
        if event.endTime != nil { return .ended }
        return event.isPaused || event.openBreak != nil ? .onBreak : .working
    }

    /// Worked seconds at `now`. For a finished shift, its recorded total.
    public static func workSeconds(_ event: ClockEvent?, at now: Date) -> Int {
        guard let event else { return 0 }
        if event.endTime != nil {
            return event.workSeconds ?? event.accumulatedTime
        }
        if event.isPaused || event.openBreak != nil {
            return max(0, event.workSeconds ?? 0)
        }
        let elapsed = Int(now.timeIntervalSince(event.startTime).rounded(.down))
        return max(0, elapsed - event.deductedBreakSeconds)
    }

    /// Seconds into the current break, or nil when not on one.
    public static func breakSeconds(_ event: ClockEvent?, at now: Date) -> Int? {
        guard let open = event?.openBreak else { return nil }
        return max(0, Int(now.timeIntervalSince(open.startTime).rounded(.down)))
    }

    /// Time left before the current break becomes an unpaid meal break:
    /// nil when not on a break, zero once it already is one.
    public static func mealBreakCountdown(_ event: ClockEvent?, at now: Date) -> TimeInterval? {
        guard let seconds = breakSeconds(event, at: now) else { return nil }
        return max(0, mealBreakThreshold - TimeInterval(seconds))
    }

    /// Always `H:MM:SS` (e.g. `3:42:18`, `0:07:05`), so the digits don't shift as a running timer ticks.
    public static func clockString(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// `7h 51m`, `42m`, `0m` — for totals.
    public static func durationString(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }
}
