import Foundation
import Testing
@testable import HuddleKit

/// Services must hit the right method with the params the server reads.
@Suite("Services")
struct ServiceTests {
    private func api(_ stub: StubTransport) -> APIClient {
        APIClient(endpoint: testEndpoint, transport: stub, retryDelay: .zero, token: { "tok" })
    }

    private func path(_ stub: StubTransport) -> String? { stub.requests.last?.url?.path }
    private func body(_ stub: StubTransport) -> [String: Any] { stub.requests.last?.bodyJSON ?? [:] }

    @Test("clock.activeForUser returns nil when off the clock")
    func activeShift() async throws {
        let stub = StubTransport([.json(200, #"{"result":null}"#)])
        #expect(try await ClockService(api(stub)).active() == nil)
        #expect(path(stub) == "/api/clock_activeForUser")
    }

    @Test("clock.start sends the plan post only when there is one")
    func clockStart() async throws {
        let event = #"{"result":{"id":"e1","teamId":"t1","startTime":1760605320000}}"#
        let stub = StubTransport([.json(200, event), .json(200, event)])
        let clock = ClockService(api(stub))

        _ = try await clock.start(teamId: "t1")
        #expect(body(stub)["teamId"] as? String == "t1")
        #expect(body(stub)["planPostId"] == nil)

        _ = try await clock.start(teamId: "t1", planPostId: "p1")
        #expect(body(stub)["planPostId"] as? String == "p1")
    }

    @Test("A plan-required clock-out surfaces the server code")
    func planRequired() async throws {
        let stub = StubTransport([.json(400, #"{"error":"plan-required","reason":"Post a wrap-up before clocking out."}"#)])
        do {
            _ = try await ClockService(api(stub)).stop(teamId: "t1")
            Issue.record("expected plan-required")
        } catch let error as APIError {
            #expect(error.serverCode == "plan-required")
        }
    }

    @Test("clock.timesheet sends epoch-ms bounds")
    func timesheet() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"sessions":[],"summary":{"totalSeconds":0}}}"#)])
        _ = try await ClockService(api(stub)).timesheet(userId: "u1", from: Date(timeIntervalSince1970: 1_760_000_000), to: Date(timeIntervalSince1970: 1_760_604_800))
        #expect(body(stub)["startMs"] as? Int == 1_760_000_000_000)
        #expect(body(stub)["endMs"] as? Int == 1_760_604_800_000)
    }

    @Test("Starting a ticket timer creates today's entry with startNow and the time zone")
    func startTicket() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"entry":{"id":"w1","ticketId":"k1","date":"2026-10-16"},"session":{"id":"s1","workItemId":"w1","startTime":1760605320000}}}"#)])
        let created = try await TimerService(api(stub)).startTicket("k1", on: "2026-10-16", timeZone: TimeZone(identifier: "America/Indiana/Indianapolis")!)
        #expect(path(stub) == "/api/timers_createEntry")
        #expect(body(stub)["startNow"] as? Bool == true)
        #expect(body(stub)["tz"] as? String == "America/Indiana/Indianapolis")
        #expect(body(stub)["source"] as? String == "huddle")
        #expect(created.session?.isRunning == true)
    }

    @Test("Ticket timers need an open shift")
    func noActiveShift() async throws {
        let stub = StubTransport([.json(400, #"{"error":"no-active-shift","reason":"Clock in to start a ticket timer"}"#)])
        await #expect(throws: APIError.server(code: "no-active-shift", reason: "Clock in to start a ticket timer", status: 400)) {
            _ = try await TimerService(api(stub)).startTicket("k1", on: "2026-10-16")
        }
    }

    @Test("A new ticket leaves out fields you didn't fill in")
    func createTicket() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"id":"k9","teamId":"t1","title":"New"}}"#)])
        let ticket = try await TicketService(api(stub)).create(.init(teamId: "t1", title: "New", priority: "high"))
        #expect(ticket.id == "k9")
        #expect(body(stub)["priority"] as? String == "high")
        #expect(body(stub)["description"] == nil)
        #expect(body(stub)["assignedToUserIds"] == nil)
    }

    @Test("A plan post carries the shift and ticket")
    func createPost() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"id":"p1"}}"#)])
        let id = try await HuddleService(api(stub)).create(.init(teamId: "t1", content: .init(text: "- [ ] Ship it", mentions: ["u2"]), ticketId: "k1", postDate: "2026-10-16"))
        #expect(id == "p1")
        let content = body(stub)["content"] as? [String: Any]
        #expect(content?["text"] as? String == "- [ ] Ship it")
        #expect(content?["mentions"] as? [String] == ["u2"])
        #expect(body(stub)["ticketId"] as? String == "k1")
    }

    @Test("Deleting no notifications makes no call")
    func deleteNone() async throws {
        let stub = StubTransport([])
        #expect(try await NotificationService(api(stub)).delete([]) == 0)
        #expect(stub.callCount == 0)
    }

    @Test("teams.getMembers unwraps members")
    func members() async throws {
        let stub = StubTransport([.json(200, #"{"result":{"members":[{"id":"u1","name":"Alex Kim","email":"a@x.org","username":"alex","image":null}]}}"#)])
        let members = try await TeamService(api(stub)).members(teamId: "t1")
        #expect(members.first?.displayName == "Alex Kim")
        #expect(body(stub)["teamId"] as? String == "t1")
    }
}
