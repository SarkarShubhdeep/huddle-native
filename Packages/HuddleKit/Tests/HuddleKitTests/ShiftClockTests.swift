import Foundation
import Testing
@testable import HuddleKit

@Suite("ShiftClock")
struct ShiftClockTests {
    // 9:02 AM on the sample day.
    private let start = Date(timeIntervalSince1970: 1_760_605_320)

    private func event(_ json: String) throws -> ClockEvent {
        try APIClient.makeDecoder().decode(ClockEvent.self, from: Data(json.utf8))
    }

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test("Off the clock")
    func idle() {
        #expect(ShiftClock.phase(nil) == .idle)
        #expect(ShiftClock.workSeconds(nil, at: .now) == 0)
    }

    @Test("Working: time since start, ticking locally")
    func working() throws {
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000,"workSeconds":60,"deductedBreakSeconds":0}"#)
        #expect(ShiftClock.phase(shift) == .working)
        #expect(ShiftClock.workSeconds(shift, at: at(222.3)) == 13_338)
        #expect(ShiftClock.clockString(13_338) == "3:42:18")
    }

    @Test("On break: frozen at the server's snapshot, with a meal-break countdown")
    func onBreak() throws {
        // Break started at 12:44 (222 min in); server snapshot says 13,320 s worked.
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000,"isPaused":true,"workSeconds":13320,"breaks":[{"startTime":1760618640000,"endTime":null}]}"#)
        #expect(ShiftClock.phase(shift) == .onBreak)
        #expect(ShiftClock.workSeconds(shift, at: at(240)) == 13_320)
        #expect(ShiftClock.breakSeconds(shift, at: at(235)) == 13 * 60)
        #expect(ShiftClock.mealBreakCountdown(shift, at: at(235)) == TimeInterval(7 * 60))
        #expect(ShiftClock.mealBreakCountdown(shift, at: at(260)) == 0)
    }

    @Test("A paid rest break doesn't reduce worked time once it ends")
    func restBreakJumpsForward() throws {
        // A 12-minute rest break that has ended: nothing deducted.
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000,"deductedBreakSeconds":0,"breaks":[{"startTime":1760610000000,"endTime":1760610720000,"type":"rest"}]}"#)
        #expect(ShiftClock.phase(shift) == .working)
        #expect(ShiftClock.workSeconds(shift, at: at(120)) == 7_200)
        #expect(ShiftClock.mealBreakCountdown(shift, at: at(120)) == nil)
    }

    @Test("A meal break is deducted")
    func mealBreakDeducted() throws {
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000,"deductedBreakSeconds":1680,"breaks":[{"startTime":1760618640000,"endTime":1760620320000,"type":"meal"}]}"#)
        #expect(ShiftClock.workSeconds(shift, at: at(300)) == 18_000 - 1_680)
        #expect(shift.breaks.first?.isMeal == true)
    }

    @Test("A finished shift shows its recorded total")
    func ended() throws {
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000,"endTime":1760633580000,"accumulatedTime":26580,"workSeconds":26580}"#)
        #expect(ShiftClock.phase(shift) == .ended)
        #expect(ShiftClock.workSeconds(shift, at: .now) == 26_580)
        #expect(ShiftClock.durationString(26_580) == "7h 23m")
        #expect(ShiftClock.durationString(2_520) == "42m")
    }

    @Test("A clock skewed ahead of the device never shows negative time")
    func neverNegative() throws {
        let shift = try event(#"{"id":"e","teamId":"t","startTime":1760605320000}"#)
        #expect(ShiftClock.workSeconds(shift, at: at(-5)) == 0)
    }
}
