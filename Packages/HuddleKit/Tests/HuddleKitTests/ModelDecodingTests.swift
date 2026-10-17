import Foundation
import Testing
@testable import HuddleKit

/// Fixtures shaped like the backend's real responses (see meteor-backend/server).
@Suite("Model decoding")
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("A clock event: epoch-ms times, open break, missing optionals")
    func clockEvent() throws {
        let event = try decode(ClockEvent.self, """
        {"id":"65f0aa","userId":"u1","teamId":"t1","startTime":1760605320000,"accumulatedTime":0,
         "breaks":[{"startTime":1760618640000,"endTime":null}],
         "workSeconds":13320,"deductedBreakSeconds":0,"totalBreakSeconds":760,"isPaused":true,"endTime":null,
         "shiftReminderResponse":null}
        """)
        #expect(event.startTime == Date(timeIntervalSince1970: 1_760_605_320))
        #expect(event.isOpen)
        #expect(event.isPaused)
        #expect(event.openBreak?.type == nil)
        #expect(event.ticketSessions.isEmpty)
    }

    @Test("A clock event with fields left out entirely still decodes")
    func sparseClockEvent() throws {
        let event = try decode(ClockEvent.self, #"{"id":"e","teamId":"t","startTime":1760605320000}"#)
        #expect(event.breaks.isEmpty)
        #expect(event.isPaused == false)
        #expect(event.deductedBreakSeconds == 0)
    }

    @Test("A team's plan requirement prefers the resolved setting")
    func team() throws {
        let teams = try decode(TeamsList.self, """
        {"teams":[{"id":"t1","orgId":"o1","parentTeamId":null,"name":"Design Team","description":null,
          "members":["u1","u2"],"admins":["u1"],"code":"ABC","isPersonal":false,
          "settings":{"requirePlanForClock":false,"autoAcceptJoins":true},
          "resolvedSettings":{"requirePlanForClock":{"value":true,"source":"org","locked":true}},
          "createdAt":"2026-01-02T03:04:05.000Z","updatedAt":null}],
         "pendingRequests":[]}
        """)
        let team = try #require(teams.teams.first)
        #expect(team.requiresPlan)
        #expect(team.isAdmin("u1"))
        #expect(!team.isAdmin("u2"))
    }

    @Test("Tickets: _id fallback, string assignee, missing status, empty github", arguments: [
        #"{"_id":"k1","teamId":"t","title":"Fix login","assignedTo":"u1","github":"","createdAt":"2026-10-16T09:00:00.000Z"}"#,
        #"{"id":"k1","teamId":"t","title":"Fix login","assignedTo":["u1"],"status":"open"}"#,
    ])
    func ticket(json: String) throws {
        let ticket = try decode(Ticket.self, json)
        #expect(ticket.id == "k1")
        #expect(ticket.assignedTo == ["u1"])
        #expect(ticket.status == "open")
        #expect(ticket.github == nil)
    }

    @Test("tickets.list is a bare array")
    func ticketList() throws {
        let list = try decode([Ticket].self, #"[{"id":"a","teamId":"t","title":"A"},{"id":"b","teamId":"t","title":"B","priority":"high"}]"#)
        #expect(list.map(\.id) == ["a", "b"])
        #expect(list[1].priority == "high")
    }

    @Test("Today's work items and their timer sessions")
    func dayEntries() throws {
        let day = try decode(DayEntries.self, """
        {"entries":[{"entry":{"id":"w1","userId":"u1","source":"huddle","ticketId":"k1","displayTitle":"Fix login",
          "displayUrl":null,"date":"2026-10-16","note":null,"sortOrder":null,"createdAt":"2026-10-16T09:00:00.000Z","updatedAt":null},
          "sessions":[{"id":"s1","workItemId":"w1","userId":"u1","clockEventId":"e1","date":"2026-10-16",
                       "startTime":1760605320000,"endTime":1760607120000,"durationSeconds":1800,"createdAt":"2026-10-16T09:02:00.000Z"},
                      {"id":"s2","workItemId":"w1","userId":"u1","clockEventId":"e1","date":"2026-10-16",
                       "startTime":1760610000000,"endTime":null,"durationSeconds":null,"createdAt":"2026-10-16T10:20:00.000Z"}]}]}
        """)
        let entry = try #require(day.entries.first)
        #expect(entry.entry.displayTitle == "Fix login")
        #expect(entry.sessions[1].isRunning)
        let now = Date(timeIntervalSince1970: 1_760_610_600) // 10 minutes into s2
        #expect(entry.totalSeconds(at: now) == 1800 + 600)
    }

    @Test("A Huddle post: plan vs wrap-up, absolute media, ISO dates")
    func huddlePost() throws {
        let page = try decode(PostsPage.self, """
        {"posts":[{"id":"p1","teamId":"t1","userId":"u1","userName":"You","userInitials":"Y",
          "content":{"text":"Finish the **iPad** fix","mentions":["u2"]},"ticketId":"k1","ticketTitle":"Fix login",
          "attachments":[{"mediaId":"m1","type":"image","url":"http://10.0.0.9:3100/uploads/media/a.png"}],
          "likes":[],"commentCount":2,"postDate":"2026-10-16","clockEventId":"e1",
          "session":{"startTime":1760605320000,"endTime":null},"wrapUpAt":null,
          "createdAt":"2026-10-16T09:01:00.000Z","updatedAt":"2026-10-16T09:01:00.000Z"}],"hasMore":false}
        """)
        let post = try #require(page.posts.first)
        #expect(post.kind == .plan)
        #expect(post.content.mentions == ["u2"])
        #expect(post.attachments.first?.isImage == true)
        #expect(!post.isEdited)
        #expect(post.session?.endTime == nil)
    }

    @Test("A post with a wrap-up is a wrap-up")
    func wrapUp() throws {
        let post = try decode(HuddlePost.self, #"{"id":"p","teamId":"t","userId":"u","content":{"text":"x"},"clockEventId":"e","wrapUpAt":"2026-10-16T17:20:00Z","createdAt":"2026-10-16T09:01:00Z"}"#)
        #expect(post.kind == .wrapUp)
        #expect(post.likes.isEmpty)
    }

    @Test("Inbox notifications expose type and route path from free-form data")
    func inbox() throws {
        let inbox = try decode(Inbox.self, """
        {"notifications":[{"id":"n1","userId":"u1","title":"Time change approved","body":"Tuesday",
          "data":{"type":"clock-session-changed","url":"/app/dashboard?tab=timesheet","teamId":"t1"},
          "read":false,"createdAt":"2026-10-16T10:20:00.000Z"},
          {"id":"n2","read":true,"createdAt":"2026-10-15T10:20:00.000Z"}]}
        """)
        #expect(inbox.notifications[0].type == "clock-session-changed")
        #expect(inbox.notifications[0].path == "/app/dashboard?tab=timesheet")
        #expect(inbox.notifications[1].title == nil)
        #expect(inbox.notifications[1].read)
    }

    @Test("Timesheet summary with a fractional average")
    func timesheet() throws {
        let sheet = try decode(Timesheet.self, """
        {"sessions":[{"id":"e1","teamId":"t","startTime":1760605320000,"endTime":1760633580000,"accumulatedTime":26580,
           "ticketSessions":[{"id":"s1","workItemId":"w1","source":"huddle","ticketId":"k1","title":"Fix","url":null,
                              "startTime":1760605320000,"endTime":1760607120000,"durationSeconds":1800}]}],
         "summary":{"totalSeconds":26580,"totalBreakSeconds":1680,"totalSessions":1,"completedSessions":1,
                    "averageSessionSeconds":26580.5,"workingDays":1}}
        """)
        #expect(sheet.sessions.first?.ticketSessions.first?.durationSeconds == 1800)
        #expect(sheet.summary.averageSessionSeconds == 26580.5)
    }

    @Test("Initials from a display name")
    func initials() throws {
        let user = try decode(PublicUser.self, #"{"id":"u","name":"Shubhdeep Sarkar","username":"shub"}"#)
        #expect(user.initials == "SS")
    }
}
