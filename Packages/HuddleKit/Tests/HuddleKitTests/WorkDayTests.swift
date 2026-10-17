import Foundation
import Testing
@testable import HuddleKit

@Suite("WorkDay")
struct WorkDayTests {
    private let day = WorkDay(timeZone: TimeZone(identifier: "America/New_York")!)

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test("Day keys use the local date, not UTC")
    func keys() {
        // 02:30 UTC on the 18th is still the evening of the 17th in New York.
        #expect(day.key(for: date("2026-10-18T02:30:00Z")) == "2026-10-17")
        #expect(day.key(for: date("2026-10-18T05:00:00Z")) == "2026-10-18")
    }

    @Test("Weeks start on Monday at local midnight")
    func weekStart() {
        // Saturday 17 October 2026 → Monday 12 October.
        let start = day.startOfWeek(date("2026-10-17T15:00:00Z"))
        #expect(day.key(for: start) == "2026-10-12")
        #expect(day.calendar.component(.hour, from: start) == 0)
        // A Monday is its own week start.
        #expect(day.key(for: day.startOfWeek(date("2026-10-12T14:00:00Z"))) == "2026-10-12")
    }

    @Test("Worked seconds per day add up closed shifts and an open one")
    func workedSeconds() throws {
        let json = #"""
        [
          {"id":"a","teamId":"t","startTime":"2026-10-16T13:00:00Z","endTime":"2026-10-16T21:00:00Z","workSeconds":27000},
          {"id":"b","teamId":"t","startTime":"2026-10-17T13:00:00Z","endTime":null,"deductedBreakSeconds":0}
        ]
        """#
        let sessions = try APIClient.makeDecoder().decode([ClockEvent].self, from: Data(json.utf8))
        let now = date("2026-10-17T14:00:00Z")
        #expect(day.workedSeconds(on: date("2026-10-16T15:00:00Z"), in: sessions, now: now) == 27000)
        #expect(day.workedSeconds(on: now, in: sessions, now: now) == 3600)
        #expect(day.workedSeconds(in: sessions, now: now) == 30600)
    }
}

@Suite("WrapUpText")
struct WrapUpTextTests {
    @Test("A wrap-up keeps the plan and goes under it")
    func withPlan() {
        #expect(WrapUpText.compose(plan: "Ship the iPad fix.\n", note: " Shipped it. ")
                == "Ship the iPad fix.\n\n**Wrap-up:** Shipped it.")
    }

    @Test("Without a plan, the wrap-up stands alone")
    func withoutPlan() {
        #expect(WrapUpText.compose(plan: nil, note: "Done for today") == "**Wrap-up:** Done for today")
        #expect(WrapUpText.compose(plan: "  ", note: "Done") == "**Wrap-up:** Done")
    }
}
