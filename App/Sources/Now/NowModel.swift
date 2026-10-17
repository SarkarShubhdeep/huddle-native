import Foundation
import HuddleKit
import Observation
import OSLog

/// Everything the Now screen and the dock's timer strip show, fetched together.
struct NowData: Codable, Sendable {
    /// Your open shift in any team.
    var active: ClockEvent?
    /// Today's work items and their timer sessions.
    var entries: [DayEntry]
    /// The ticket timer that's running, if any.
    var running: TimerSession?
    /// This week's shifts, Monday on.
    var week: [ClockEvent]
}

/// Shift state and actions. Lives for the signed-in session (the dock's strip
/// needs it on every tab) and refreshes when the app becomes active, every
/// 30 s while it is, and after every action.
@MainActor
@Observable
final class NowModel {
    enum Action: Equatable { case startDay, takeBreak, resume, endDay, pauseTimer }

    let data: Resource<NowData>
    /// The action in flight, for button spinners.
    private(set) var pending: Action?
    /// The last action's failure, in plain words. Cleared by the next action.
    var actionError: String?
    /// Bumped after each successful action, for haptics.
    private(set) var completed = 0

    @ObservationIgnored private let clock: ClockService
    @ObservationIgnored private let timers: TimerService
    @ObservationIgnored private let huddle: HuddleService
    @ObservationIgnored let userId: String
    @ObservationIgnored let workDay = WorkDay()
    nonisolated static let log = Logger(subsystem: "HuddleNative", category: "Now")

    init(api: APIClient, userId: String, snapshots: any SnapshotStore) {
        let clock = ClockService(api)
        let timers = TimerService(api)
        self.clock = clock
        self.timers = timers
        self.huddle = HuddleService(api)
        self.userId = userId
        let workDay = self.workDay
        data = Resource(cacheKey: "now.\(userId)", store: snapshots) {
            let now = Date.now
            async let active = clock.active()
            async let entries = timers.today()
            async let running = timers.running()
            async let week = clock.timesheet(userId: userId, from: workDay.startOfWeek(now), to: now.addingTimeInterval(60))
            do {
                return try await NowData(active: active, entries: entries, running: running, week: week.sessions)
            } catch {
                NowModel.log.error("Now refresh failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
    }

    // MARK: Derived state

    var active: ClockEvent? { data.value?.active }
    var phase: ShiftPhase {
        if let active { return ShiftClock.phase(active) }
        return endedToday != nil ? .ended : .idle
    }

    /// Today's last finished shift, when you're off the clock after working.
    var endedToday: ClockEvent? {
        guard data.value?.active == nil else { return nil }
        let today = workDay.startOfDay(.now)
        return data.value?.week.filter { $0.endTime != nil && $0.startTime >= today }.max { $0.startTime < $1.startTime }
    }

    var entries: [DayEntry] { data.value?.entries ?? [] }

    /// The running timer's work item.
    var runningEntry: DayEntry? {
        guard let running = data.value?.running else { return nil }
        return entries.first { $0.entry.id == running.workItemId }
    }

    /// The ticket a break paused: the most recently stopped session today.
    var pausedEntry: DayEntry? {
        guard phase == .onBreak, data.value?.running == nil else { return nil }
        return entries.max { lastStop($0) < lastStop($1) }.flatMap { lastStop($0) == .distantPast ? nil : $0 }
    }

    private func lastStop(_ entry: DayEntry) -> Date {
        entry.sessions.compactMap(\.endTime).max() ?? .distantPast
    }

    /// The strip's state at `now`, or nil off the clock.
    func strip(at now: Date) -> TimerStripState? {
        guard let active else { return nil }
        switch ShiftClock.phase(active) {
        case .working:
            if let entry = runningEntry {
                return .timing(shiftSeconds: ShiftClock.workSeconds(active, at: now),
                               ticketTitle: entry.entry.displayTitle ?? "Ticket",
                               ticketSeconds: entry.totalSeconds(at: now))
            }
            return .onShift(shiftSeconds: ShiftClock.workSeconds(active, at: now))
        case .onBreak:
            let paused = pausedEntry
            return .onBreak(breakSeconds: ShiftClock.breakSeconds(active, at: now) ?? 0,
                            pausedTicketTitle: paused?.entry.displayTitle,
                            ticketSeconds: paused?.totalSeconds(at: now))
        case .idle, .ended:
            return nil
        }
    }

    // MARK: Actions

    /// Clocks in to `teamId`, after posting `plan` when the team asks for one.
    func startDay(teamId: String, plan: String?) async -> Bool {
        await perform(.startDay) {
            var planPostId: String?
            if let plan, !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                planPostId = try await self.huddle.create(.init(
                    teamId: teamId,
                    content: .init(text: plan.trimmingCharacters(in: .whitespacesAndNewlines)),
                    postDate: self.workDay.key(for: .now)
                ))
            }
            let event = try await self.clock.start(teamId: teamId, planPostId: planPostId)
            return { $0.active = event }
        }
    }

    func takeBreak() async {
        guard let teamId = active?.teamId else { return }
        _ = await perform(.takeBreak) {
            let event = try await self.clock.pause(teamId: teamId)
            return { $0.active = event; $0.running = nil }
        }
    }

    func resume() async {
        guard let teamId = active?.teamId else { return }
        _ = await perform(.resume) {
            let event = try await self.clock.resume(teamId: teamId)
            return { $0.active = event }
        }
    }

    func pauseTimer() async {
        guard let session = data.value?.running else { return }
        _ = await perform(.pauseTimer) {
            _ = try await self.timers.stop(sessionId: session.id)
            return { $0.running = nil }
        }
    }

    /// This shift's Huddle post (its plan), if it has one.
    func sessionPost() async -> HuddlePost? {
        guard let active else { return nil }
        let post = try? await huddle.myPost(teamId: active.teamId, on: workDay.key(for: active.startTime))
        return post?.clockEventId == active.id ? post : nil
    }

    /// Posts the wrap-up (onto the plan when there is one), then clocks out.
    /// With no note, just clocks out. Returns whether the day ended.
    func endDay(note: String?, plan: HuddlePost?) async -> Bool {
        guard let active else { return false }
        return await perform(.endDay) {
            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let text = WrapUpText.compose(plan: plan?.content.text, note: note)
                if let plan {
                    _ = try await self.huddle.update(postId: plan.id, content: .init(text: text, mentions: plan.content.mentions), wrapUp: true)
                } else {
                    _ = try await self.huddle.create(.init(
                        teamId: active.teamId, content: .init(text: text),
                        postDate: self.workDay.key(for: active.startTime), clockEventId: active.id, wrapUp: true
                    ) as HuddleService.NewPost)
                }
            }
            let event = try await self.clock.stop(teamId: active.teamId)
            return { data in
                data.active = nil
                data.running = nil
                data.week.removeAll { $0.id == event.id }
                data.week.append(event)
            }
        }
    }

    func refresh() async { await data.refresh() }

    /// Runs one write. Its result shows at once (the server returns the
    /// updated shift), then a refetch confirms everything else. Success or
    /// not, the screen ends up showing what the server has.
    private func perform(_ action: Action, _ body: @escaping () async throws -> (inout NowData) -> Void) async -> Bool {
        guard pending == nil else { return false }
        pending = action
        actionError = nil
        defer { pending = nil }
        do {
            let apply = try await body()
            if var updated = data.value {
                apply(&updated)
                data.set(updated)
            }
            completed += 1
            await data.refetch()
            return true
        } catch {
            actionError = Self.message(for: APIError.from(error), action: action)
            await data.refetch()
            return false
        }
    }

    static func message(for error: APIError, action: Action) -> String {
        switch error.serverCode {
        case "plan-required":
            return action == .endDay
                ? "Your team needs a wrap-up before you end the day."
                : "Your team needs a plan before you start."
        case "no-active-shift": return "Start your day first. Ticket timers only run during a shift."
        case "not-found" where action != .startDay: return "That shift already ended. Pull to refresh."
        default: return error.localizedDescription
        }
    }
}
