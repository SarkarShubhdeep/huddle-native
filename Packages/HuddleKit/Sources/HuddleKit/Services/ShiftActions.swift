import Foundation

/// The clock actions that work outside the app (App Intents, Control Center,
/// widgets, the Live Activity), and the snapshot they leave behind.
public struct ShiftActions: Sendable {
    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        case notOnShift
        case noTeam
        case notOnBreak
        case alreadyOnShift
        /// The team wants a plan or wrap-up first, which needs the app.
        case needsApp(String)

        public var errorDescription: String? {
            switch self {
            case .notOnShift: "You’re not on the clock."
            case .noTeam: "Open Huddle and pick a team first."
            case .notOnBreak: "You’re not on a break."
            case .alreadyOnShift: "You’re already on the clock."
            case let .needsApp(message): message
            }
        }
    }

    private let clock: ClockService
    private let timers: TimerService
    private let userId: String
    private let workDay: WorkDay

    public init(api: APIClient, userId: String, timeZone: TimeZone = .current) {
        clock = ClockService(api)
        timers = TimerService(api)
        self.userId = userId
        workDay = WorkDay(timeZone: timeZone)
    }

    /// The current state, from the backend.
    public func snapshot(teamName: @Sendable (String) -> String? = { _ in nil }, now: Date = .now) async throws -> ShiftSnapshot {
        let dayStart = workDay.startOfDay(now)
        async let active = clock.active()
        async let running = timers.running()
        async let entries = timers.today(timeZone: workDay.calendar.timeZone)
        async let sheet = clock.timesheet(userId: userId, from: dayStart, to: now.addingTimeInterval(60))
        return try await ShiftSnapshot.make(active: active, running: running, entries: entries,
                                            todayShifts: sheet.sessions, teamName: teamName, now: now)
    }

    public func startDay(teamId: String?) async throws {
        if try await clock.active() != nil { throw Failure.alreadyOnShift }
        guard let teamId else { throw Failure.noTeam }
        do {
            _ = try await clock.start(teamId: teamId)
        } catch let error as APIError where error.serverCode == "plan-required" {
            throw Failure.needsApp("Your team asks for a plan first. Open Huddle to write it.")
        }
    }

    public func takeBreak() async throws {
        guard let active = try await clock.active() else { throw Failure.notOnShift }
        guard active.openBreak == nil, !active.isPaused else { return }
        _ = try await clock.pause(teamId: active.teamId)
    }

    public func resume() async throws {
        guard let active = try await clock.active() else { throw Failure.notOnShift }
        guard active.openBreak != nil || active.isPaused else { throw Failure.notOnBreak }
        _ = try await clock.resume(teamId: active.teamId)
    }

    /// Ends the day. When the team wants a wrap-up first, says to open the app.
    public func endDay() async throws {
        guard let active = try await clock.active() else { throw Failure.notOnShift }
        do {
            _ = try await clock.stop(teamId: active.teamId)
        } catch let error as APIError where error.serverCode == "plan-required" {
            throw Failure.needsApp("Your team asks for a wrap-up first. Open Huddle to post it.")
        }
    }

    public func pauseTicket() async throws {
        guard let running = try await timers.running() else { return }
        _ = try await timers.stop(sessionId: running.id)
    }

    /// Starts `ticketId`'s timer, stopping any other. Needs an open shift.
    public func startTicket(_ ticketId: String, now: Date = .now) async throws {
        do {
            _ = try await timers.startTicket(ticketId, on: workDay.key(for: now), timeZone: workDay.calendar.timeZone)
        } catch let error as APIError where error.serverCode == "no-active-shift" {
            throw Failure.notOnShift
        }
    }
}
