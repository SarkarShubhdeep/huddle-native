import Foundation
import Testing
@testable import HuddleKit

@Suite("TicketQuery")
struct TicketQueryTests {
    private let tickets: [Ticket] = {
        let json = #"""
        [
          {"id":"a","teamId":"t","title":"Fix login redirect","status":"in-progress","priority":"high","assignedTo":["me"],"createdAt":"2026-10-10T10:00:00Z","updatedAt":"2026-10-16T10:00:00Z"},
          {"id":"b","teamId":"t","title":"Review onboarding copy","status":"open","priority":"medium","assignedTo":["me","ak"],"createdAt":"2026-10-12T10:00:00Z","updatedAt":"2026-10-12T10:00:00Z"},
          {"id":"c","teamId":"t","title":"Export shows UTC","status":"blocked","priority":"critical","assignedTo":["ak"],"createdAt":"2026-10-14T10:00:00Z"},
          {"id":"d","teamId":"t","title":"Release notes","status":"closed","assignedTo":["me"],"createdAt":"2026-10-15T10:00:00Z","updatedAt":"2026-10-15T12:00:00Z"}
        ]
        """#
        return try! APIClient.makeDecoder().decode([Ticket].self, from: Data(json.utf8))
    }()

    @Test("By default: open tickets assigned to me, recently updated first")
    func defaults() {
        let ids = TicketQuery().apply(to: tickets, me: "me").map(\.id)
        #expect(ids == ["a", "b"])
        #expect(TicketQuery().activeFilterCount == 2)
    }

    @Test("Status, assignee and priority filters combine")
    func filters() {
        var query = TicketQuery()
        query.assignee = .anyone
        query.status = .all
        #expect(query.apply(to: tickets, me: "me").count == 4)
        #expect(query.activeFilterCount == 0)

        query.status = .only("blocked")
        #expect(query.apply(to: tickets, me: "me").map(\.id) == ["c"])

        query.status = .open
        query.assignee = .user("ak")
        query.priorities = [.critical, .medium]
        #expect(query.apply(to: tickets, me: "me").map(\.id).sorted() == ["b", "c"])
        #expect(query.activeFilterCount == 3)
    }

    @Test("A ticket without a priority counts as none")
    func noPriority() {
        var query = TicketQuery()
        query.status = .all
        query.priorities = [.none]
        #expect(query.apply(to: tickets, me: "me").map(\.id) == ["d"])
    }

    @Test("Sorts by priority, title, time today and age, in either direction")
    func sorts() {
        var query = TicketQuery()
        query.assignee = .anyone
        query.status = .all

        query.sort = .priority
        #expect(query.apply(to: tickets, me: "me").map(\.id) == ["c", "a", "b", "d"])

        query.sort = .title
        query.ascending = true
        #expect(query.apply(to: tickets, me: "me").map(\.id) == ["c", "a", "d", "b"])

        query.sort = .timeToday
        query.ascending = false
        #expect(Array(query.apply(to: tickets, me: "me", secondsToday: ["b": 600, "a": 60]).map(\.id).prefix(2)) == ["b", "a"])

        query.sort = .created
        query.ascending = true
        #expect(query.apply(to: tickets, me: "me").map(\.id) == ["a", "b", "c", "d"])
    }

    @Test("Search ignores case and accents and returns the matched range")
    func search() {
        let title = "Café menu redirect"
        let range = TicketQuery.match("CAFE", in: title)
        #expect(range.map { String(title[$0]) } == "Café")
        #expect(TicketQuery.match("  ", in: title) == nil)
        #expect(TicketQuery.match("zzz", in: title) == nil)
    }
}
