import Foundation
import Testing
@testable import HuddleKit

@Suite("NotificationRoute")
struct NotificationRouteTests {
    @Test("Web paths map to tabs")
    func paths() {
        #expect(NotificationRoute(path: "/app/huddle?postId=p&teamId=t1", type: "clock-out-self") == .huddle(teamId: "t1"))
        #expect(NotificationRoute(path: "/app/tickets/abc", type: nil) == .tickets)
        #expect(NotificationRoute(path: "/app/profile/u1?tab=work", type: "clock-out-self") == .time)
        #expect(NotificationRoute(path: "/app/dashboard?tab=timesheet", type: nil) == .time)
        #expect(NotificationRoute(path: "/app/dashboard", type: nil) == .now)
    }

    @Test("Without a path we know, the type decides")
    func types() {
        #expect(NotificationRoute(path: nil, type: "shift-4h-reminder") == .now)
        #expect(NotificationRoute(path: "/app/settings", type: "ticket-assigned") == .tickets)
        #expect(NotificationRoute(path: nil, type: "huddle-mention") == .huddle(teamId: nil))
        #expect(NotificationRoute(path: nil, type: "something-new") == .none)
        #expect(NotificationRoute(path: nil, type: nil) == .none)
    }
}

@Suite("RequestLog")
struct RequestLogTests {
    @Test("Records method names, status and failures, newest first")
    func records() async throws {
        let log = RequestLog()
        let ok = LoggingTransport(StubTransport([.json(200, #"{"result":null}"#)]), log: log)
        let api = APIClient(endpoint: testEndpoint, transport: ok, retryDelay: .zero, token: { "t" })
        let _: ClockEvent? = try await api.query("clock.activeForUser")

        let down = LoggingTransport(StubTransport([.failure(.cannotConnectToHost)]), log: log)
        _ = await ServerProbe(transport: down).check(testEndpoint)

        let entries = log.entries
        #expect(entries.map(\.name) == ["GET /", "clock.activeForUser"])
        #expect(entries[1].status == 200 && entries[1].succeeded)
        #expect(entries[0].status == nil && entries[0].failure == "Can’t reach the server.")
    }

    @Test("Keeps only the most recent entries")
    func capacity() {
        let log = RequestLog(capacity: 3)
        for i in 0..<5 { log.record(name: "m\(i)", startedAt: .now, milliseconds: 1, status: 200, failure: nil) }
        #expect(log.entries.map(\.name) == ["m4", "m3", "m2"])
    }
}
