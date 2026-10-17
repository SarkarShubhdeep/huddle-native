import Foundation
import Testing
@testable import HuddleKit

@Suite("DayTimeline")
struct DayTimelineTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private let sessions: [ClockEvent] = {
        let json = #"""
        [
          {"id":"s1","teamId":"t","startTime":"2026-10-16T13:00:00Z","endTime":null,"deductedBreakSeconds":0,
           "breaks":[{"startTime":"2026-10-16T15:30:00Z","endTime":"2026-10-16T15:42:00Z","type":"rest"},
                     {"startTime":"2026-10-16T17:00:00Z","endTime":null}],
           "ticketSessions":[{"id":"x","title":"Fix login","startTime":"2026-10-16T15:42:00Z","endTime":"2026-10-16T16:00:00Z","durationSeconds":1080},
                             {"id":"y","startTime":"2026-10-16T14:00:00Z","endTime":"2026-10-16T15:00:00Z"}]},
          {"id":"s0","teamId":"t","startTime":"2026-10-15T13:00:00Z","endTime":"2026-10-15T21:00:00Z","workSeconds":28800}
        ]
        """#
        return try! APIClient.makeDecoder().decode([ClockEvent].self, from: Data(json.utf8))
    }()

    @Test("A day lists its shift first, then its timers and breaks, newest first")
    func order() {
        let now = date("2026-10-16T17:10:00Z")
        let items = DayTimeline.items(on: date("2026-10-16T16:00:00Z"), from: sessions, calendar: calendar, now: now)
        #expect(items.map(\.id) == ["s1", "b-s1-1", "t-x", "b-s1-0", "t-y"])
        #expect(items[0].kind == .shift)
        // Open break: still running, counted to now.
        #expect(items[1].kind == .rest(isMeal: nil))
        #expect(items[1].seconds == 600)
        #expect(items[2] == TimelineItem(id: "t-x", kind: .ticket(title: "Fix login"),
                                         start: date("2026-10-16T15:42:00Z"), end: date("2026-10-16T16:00:00Z"), seconds: 1080))
        #expect(items[3].kind == .rest(isMeal: false))
        // No title, no stored duration: a generic name and the time between start and end.
        #expect(items[4].kind == .ticket(title: "Ticket"))
        #expect(items[4].seconds == 3600)
    }

    @Test("Only shifts that started that day, in local time")
    func dayBoundaries() {
        let now = date("2026-10-16T17:10:00Z")
        let previous = DayTimeline.items(on: date("2026-10-15T16:00:00Z"), from: sessions, calendar: calendar, now: now)
        #expect(previous.map(\.id) == ["s0"])
        #expect(previous[0].seconds == 28800)
        #expect(DayTimeline.items(on: date("2026-10-17T16:00:00Z"), from: sessions, calendar: calendar, now: now).isEmpty)
    }

    @Test("A closed break without a type is classed by the 20-minute rule")
    func untypedBreak() throws {
        let json = #"""
        [{"id":"s","teamId":"t","startTime":"2026-10-16T13:00:00Z","endTime":"2026-10-16T20:00:00Z","workSeconds":0,
          "breaks":[{"startTime":"2026-10-16T16:00:00Z","endTime":"2026-10-16T16:25:00Z"}]}]
        """#
        let shifts = try APIClient.makeDecoder().decode([ClockEvent].self, from: Data(json.utf8))
        let items = DayTimeline.items(on: date("2026-10-16T16:00:00Z"), from: shifts, calendar: calendar, now: .now)
        #expect(items.last?.kind == .rest(isMeal: true))
    }
}
