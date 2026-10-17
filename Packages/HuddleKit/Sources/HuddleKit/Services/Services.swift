import Foundation

// One thin, typed wrapper per backend area. Each method is one Meteor method;
// params match the server's handlers in meteor-backend/server/*.js.
// Reads use `query` (retried once on a dropped connection); writes use `mutate`.

private struct TeamID: Encodable, Sendable { let teamId: String }

public struct TeamService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    /// Your teams, personal team first.
    public func list() async throws -> [Team] {
        try await api.query("teams.list", as: TeamsList.self).teams
    }

    public func members(teamId: String) async throws -> [TeamMember] {
        try await api.query("teams.getMembers", TeamID(teamId: teamId), as: TeamMembers.self).members
    }
}

public struct UserService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    private struct Params: Encodable, Sendable { let userId: String }

    public func get(_ userId: String) async throws -> PublicUser {
        try await api.query("users.get", Params(userId: userId), as: UserEnvelope.self).user
    }
}

public struct ClockService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    private struct Start: Encodable, Sendable { let teamId: String; let planPostId: String? }
    private struct Range: Encodable, Sendable { let userId: String; let startMs: Int64; let endMs: Int64 }

    /// Your open shift in any team, or nil when you're off the clock.
    public func active() async throws -> ClockEvent? {
        try await api.query("clock.activeForUser")
    }

    public func status(teamId: String) async throws -> ClockStatus? {
        try await api.query("clock.status", TeamID(teamId: teamId))
    }

    /// Fails with `plan-required` style server errors when the team asks for a plan first.
    public func start(teamId: String, planPostId: String? = nil) async throws -> ClockEvent {
        try await api.mutate("clock.start", Start(teamId: teamId, planPostId: planPostId))
    }

    /// Also stops every running ticket timer. Fails with `plan-required` when the team
    /// requires a wrap-up that hasn't been posted.
    public func stop(teamId: String) async throws -> ClockEvent {
        try await api.mutate("clock.stop", TeamID(teamId: teamId))
    }

    /// Starts a break; also pauses the running ticket timer.
    public func pause(teamId: String) async throws -> ClockEvent {
        try await api.mutate("clock.pause", TeamID(teamId: teamId))
    }

    /// Ends the break and restarts the ticket timer it paused.
    public func resume(teamId: String) async throws -> ClockEvent {
        try await api.mutate("clock.resume", TeamID(teamId: teamId))
    }

    public func timesheet(userId: String, from start: Date, to end: Date) async throws -> Timesheet {
        try await api.query("clock.timesheet", Range(userId: userId, startMs: start.epochMilliseconds, endMs: end.epochMilliseconds))
    }
}

public struct TimerService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    private struct Today: Encodable, Sendable { let tz: String }
    private struct WeekParams: Encodable, Sendable { let date: String; let tz: String }
    private struct CreateEntry: Encodable, Sendable {
        let ticketId: String; let source: String; let date: String; let startNow: Bool; let tz: String
    }
    private struct StartSession: Encodable, Sendable { let entryId: String; let tz: String }
    private struct StopSession: Encodable, Sendable { let sessionId: String }
    private struct Total: Encodable, Sendable { let ticketId: String; let source: String }

    public func today(timeZone: TimeZone = .current) async throws -> [DayEntry] {
        try await api.query("timers.getToday", Today(tz: timeZone.identifier), as: DayEntries.self).entries
    }

    /// Seven days starting at `start` (`YYYY-MM-DD`).
    public func week(starting start: String, timeZone: TimeZone = .current) async throws -> [WeekDay] {
        try await api.query("timers.getWeek", WeekParams(date: start, tz: timeZone.identifier), as: Week.self).days
    }

    public func running() async throws -> TimerSession? {
        try await api.query("timers.getRunning", as: RunningTimer.self).session
    }

    /// Finds or creates today's work item for a ticket and, with `startNow`, starts its
    /// timer (closing any other running one). Needs an open shift: `no-active-shift` otherwise.
    public func startTicket(_ ticketId: String, on date: String, timeZone: TimeZone = .current) async throws -> EntryCreated {
        try await api.mutate("timers.createEntry", CreateEntry(ticketId: ticketId, source: "huddle", date: date, startNow: true, tz: timeZone.identifier))
    }

    public func start(entryId: String, timeZone: TimeZone = .current) async throws -> TimerStarted {
        try await api.mutate("timers.startSession", StartSession(entryId: entryId, tz: timeZone.identifier))
    }

    public func stop(sessionId: String) async throws -> TimerStopped {
        try await api.mutate("timers.stopSession", StopSession(sessionId: sessionId))
    }

    /// Your closed sessions on a ticket; a running session isn't counted.
    public func total(ticketId: String) async throws -> Int {
        try await api.query("timers.getTicketTotal", Total(ticketId: ticketId, source: "huddle"), as: TicketTotal.self).totalSeconds
    }
}

public struct TicketService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    public struct NewTicket: Encodable, Sendable {
        public let teamId: String
        public let title: String
        public let description: String?
        public let github: String?
        public let priority: String?
        public let assignedToUserIds: [String]?

        public init(teamId: String, title: String, description: String? = nil, github: String? = nil, priority: String? = nil, assignedToUserIds: [String]? = nil) {
            self.teamId = teamId
            self.title = title
            self.description = description
            self.github = github
            self.priority = priority
            self.assignedToUserIds = assignedToUserIds
        }
    }

    private struct StatusChange: Encodable, Sendable { let ticketId: String; let status: String }

    /// Newest first; deleted tickets are left out by the server.
    public func list(teamId: String) async throws -> [Ticket] {
        try await api.query("tickets.list", TeamID(teamId: teamId))
    }

    public func create(_ ticket: NewTicket) async throws -> Ticket {
        try await api.mutate("tickets.create", ticket)
    }

    public func setStatus(_ status: String, ticketId: String) async throws -> Ticket {
        try await api.mutate("tickets.updateStatus", StatusChange(ticketId: ticketId, status: status))
    }
}

public struct HuddleService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    private struct Feed: Encodable, Sendable { let teamId: String; let since: String? }
    private struct ForDate: Encodable, Sendable { let teamId: String; let postDate: String }
    private struct Update: Encodable, Sendable { let postId: String; let content: HuddlePost.Content; let wrapUp: Bool }

    public struct NewPost: Encodable, Sendable {
        public let teamId: String
        public let content: HuddlePost.Content
        public let ticketId: String?
        public let postDate: String?
        public let clockEventId: String?

        public init(teamId: String, content: HuddlePost.Content, ticketId: String? = nil, postDate: String? = nil, clockEventId: String? = nil) {
            self.teamId = teamId
            self.content = content
            self.ticketId = ticketId
            self.postDate = postDate
            self.clockEventId = clockEventId
        }
    }

    /// Newest first. Without `since`, the server returns the last 30 days.
    public func posts(teamId: String, since: Date? = nil) async throws -> PostsPage {
        try await api.query("huddle.getPosts", Feed(teamId: teamId, since: since.map(ISO8601DateFormatter().string(from:))))
    }

    public func myPost(teamId: String, on postDate: String) async throws -> HuddlePost? {
        try await api.query("huddle.getMyPostForDate", ForDate(teamId: teamId, postDate: postDate), as: PostLookup.self).post
    }

    public func create(_ post: NewPost) async throws -> String {
        try await api.mutate("huddle.createPost", post, as: CreatedID.self).id
    }

    /// With `wrapUp`, the text is appended to the plan as its wrap-up and `wrapUpAt` is stamped.
    public func update(postId: String, content: HuddlePost.Content, wrapUp: Bool) async throws -> String {
        try await api.mutate("huddle.updatePost", Update(postId: postId, content: content, wrapUp: wrapUp), as: CreatedID.self).id
    }
}

public struct NotificationService: Sendable {
    let api: APIClient
    public init(_ api: APIClient) { self.api = api }

    private struct One: Encodable, Sendable { let notificationId: String }
    private struct Many: Encodable, Sendable { let ids: [String] }

    /// Newest first, at most 200.
    public func inbox() async throws -> [AppNotification] {
        try await api.query("notifications.getInbox", as: Inbox.self).notifications
    }

    public func markRead(_ id: String) async throws {
        _ = try await api.mutate("notifications.markOneRead", One(notificationId: id), as: OKResult.self)
    }

    public func markAllRead() async throws {
        _ = try await api.mutate("notifications.markAllRead", as: OKResult.self)
    }

    public func delete(_ ids: [String]) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try await api.mutate("notifications.deleteMany", Many(ids: ids), as: DeletedCount.self).deletedCount
    }
}

extension Date {
    var epochMilliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}
