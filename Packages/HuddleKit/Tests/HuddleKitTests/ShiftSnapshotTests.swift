import Foundation
import Testing
@testable import HuddleKit

@Suite("ShiftSnapshot")
struct ShiftSnapshotTests {
    private let decoder = APIClient.makeDecoder()
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T { try! decoder.decode(type, from: Data(json.utf8)) }

    private var entries: [DayEntry] {
        decode([DayEntry].self, #"""
        [{"entry":{"id":"w1","ticketId":"k1","displayTitle":"Fix login","date":"2026-10-17"},
          "sessions":[{"id":"s1","workItemId":"w1","startTime":"2026-10-17T13:00:00Z","endTime":"2026-10-17T13:10:00Z","durationSeconds":600},
                      {"id":"s2","workItemId":"w1","startTime":"2026-10-17T14:00:00Z","endTime":null}]}]
        """#)
    }

    @Test("Working with a ticket: reference dates tick, and equal state compares equal")
    func working() {
        let active = decode(ClockEvent.self, #"{"id":"c","teamId":"t","startTime":"2026-10-17T12:00:00Z","endTime":null,"deductedBreakSeconds":1500}"#)
        let running = decode(TimerSession.self, #"{"id":"s2","workItemId":"w1","startTime":"2026-10-17T14:00:00Z","endTime":null}"#)
        let now = date("2026-10-17T15:00:00Z")
        let snapshot = ShiftSnapshot.make(active: active, running: running, entries: entries, todayShifts: [],
                                          teamName: { _ in "Dev" }, now: now)
        #expect(snapshot.phase == .working)
        #expect(snapshot.teamName == "Dev")
        // 3 h since start, minus a 25-minute meal break.
        #expect(snapshot.worked(at: now) == 3 * 3600 - 1500)
        #expect(snapshot.worked(at: now) == ShiftClock.workSeconds(active, at: now))
        // 10 closed minutes plus the hour running.
        #expect(snapshot.ticketTitle == "Fix login")
        #expect(snapshot.ticket(at: now) == 600 + 3600)
        // A minute later the same state builds the same snapshot.
        let later = ShiftSnapshot.make(active: active, running: running, entries: entries, todayShifts: [],
                                       teamName: { _ in "Dev" }, now: now.addingTimeInterval(60))
        #expect(later == snapshot)
    }

    @Test("On break: worked time freezes, the meal-break time is set, the paused ticket shows")
    func onBreak() {
        let active = decode(ClockEvent.self, #"""
        {"id":"c","teamId":"t","startTime":"2026-10-17T12:00:00Z","endTime":null,"isPaused":true,"workSeconds":7200,
         "breaks":[{"startTime":"2026-10-17T14:30:00Z","endTime":null}]}
        """#)
        let paused = decode([DayEntry].self, #"""
        [{"entry":{"id":"w1","ticketId":"k1","displayTitle":"Fix login","date":"2026-10-17"},
          "sessions":[{"id":"s1","workItemId":"w1","startTime":"2026-10-17T13:00:00Z","endTime":"2026-10-17T14:30:00Z","durationSeconds":5400}]}]
        """#)
        let now = date("2026-10-17T14:40:00Z")
        let snapshot = ShiftSnapshot.make(active: active, running: nil, entries: paused, todayShifts: [],
                                          teamName: { _ in nil }, now: now)
        #expect(snapshot.phase == .onBreak)
        #expect(snapshot.worked(at: now.addingTimeInterval(600)) == 7200)
        #expect(snapshot.mealBreakAt == date("2026-10-17T14:50:00Z"))
        #expect(snapshot.ticketTitle == "Fix login")
        #expect(snapshot.ticket(at: now) == 5400)
        #expect(snapshot.ticketSince == nil)
    }

    @Test("Off the clock: day done with the day's total, or not started")
    func offClock() {
        let shifts = decode([ClockEvent].self, #"""
        [{"id":"a","teamId":"t","startTime":"2026-10-17T12:00:00Z","endTime":"2026-10-17T14:00:00Z","workSeconds":7000},
         {"id":"b","teamId":"t2","startTime":"2026-10-17T15:00:00Z","endTime":"2026-10-17T16:00:00Z","workSeconds":3600}]
        """#)
        let done = ShiftSnapshot.make(active: nil, running: nil, entries: [], todayShifts: shifts,
                                      teamName: { $0 == "t2" ? "Ops" : nil }, now: date("2026-10-17T17:00:00Z"))
        #expect(done.phase == .dayDone)
        #expect(done.workedSeconds == 10600)
        #expect(done.teamName == "Ops")
        #expect(!done.isOnShift)

        let idle = ShiftSnapshot.make(active: nil, running: nil, entries: [], todayShifts: [],
                                      teamName: { _ in nil }, now: .now)
        #expect(idle == ShiftSnapshot(phase: .offClock))
    }
}

@Suite("ShiftActions")
struct ShiftActionsTests {
    private func actions(_ stub: StubTransport) -> ShiftActions {
        ShiftActions(api: APIClient(endpoint: testEndpoint, transport: stub, retryDelay: .zero, token: { "t" }), userId: "u")
    }

    @Test("A break uses the open shift's team")
    func breakUsesShiftTeam() async throws {
        let stub = StubTransport([
            .json(200, #"{"result":{"id":"c","teamId":"t9","startTime":1792252800000,"endTime":null}}"#),
            .json(200, #"{"result":{"id":"c","teamId":"t9","startTime":1792252800000,"endTime":null,"isPaused":true}}"#),
        ])
        try await actions(stub).takeBreak()
        #expect(stub.requests.last?.url?.path == "/api/clock_pause")
        #expect(stub.requests.last?.bodyJSON?["teamId"] as? String == "t9")
    }

    @Test("Off the clock, a break or end day says so without calling the server again")
    func notOnShift() async {
        let stub = StubTransport([.json(200, #"{"result":null}"#), .json(200, #"{"result":null}"#)])
        await #expect(throws: ShiftActions.Failure.notOnShift) { try await actions(stub).takeBreak() }
        await #expect(throws: ShiftActions.Failure.notOnShift) { try await actions(stub).endDay() }
        #expect(stub.callCount == 2)
    }

    @Test("plan-required becomes a plain 'open the app' message")
    func planRequired() async {
        let stub = StubTransport([
            .json(200, #"{"result":{"id":"c","teamId":"t","startTime":1792252800000,"endTime":null}}"#),
            .json(400, #"{"error":"plan-required","reason":"Add a wrap-up"}"#),
        ])
        await #expect(throws: ShiftActions.Failure.needsWrapUp) { try await actions(stub).endDay() }
    }

    @Test("A team that asks for a plan isn't clocked in from outside the app")
    func planFirst() async {
        let stub = StubTransport([.json(200, #"{"result":null}"#)])
        await #expect(throws: ShiftActions.Failure.needsPlan) { try await actions(stub).startDay(teamId: "t", requiresPlan: true) }
        #expect(stub.requests.map { $0.url?.path } == ["/api/clock_activeForUser"])
    }

    @Test("Start day without a team asks to pick one")
    func noTeam() async {
        let stub = StubTransport([.json(200, #"{"result":null}"#)])
        await #expect(throws: ShiftActions.Failure.noTeam) { try await actions(stub).startDay(teamId: nil) }
    }
}

@Suite("FallbackSecretStore")
struct FallbackSecretStoreTests {
    @Test("A key only in the legacy store moves to the primary one")
    func migrates() throws {
        let primary = InMemorySecretStore(), legacy = InMemorySecretStore()
        try legacy.write(Data("s".utf8), for: "session")
        let store = FallbackSecretStore(primary: primary, legacy: legacy)
        #expect(try store.read("session") == Data("s".utf8))
        #expect(try primary.read("session") == Data("s".utf8))
        #expect(try legacy.read("session") == nil)
        try store.delete("session")
        #expect(try store.read("session") == nil)
    }
}
