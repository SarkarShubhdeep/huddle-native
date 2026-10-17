import Foundation

/// Ticket priorities, lowest to highest, as the backend spells them.
public enum TicketPriority: String, CaseIterable, Sendable, Codable, Identifiable {
    case none, low, medium, high, critical

    public var id: String { rawValue }

    public init(raw: String?) { self = raw.flatMap(TicketPriority.init(rawValue:)) ?? .none }

    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The Tickets list's filters and sort, applied on the device to the team's
/// tickets (the backend returns them all).
public struct TicketQuery: Equatable, Sendable, Codable {
    public enum StatusFilter: Hashable, Sendable, Codable {
        /// Everything that isn't done.
        case open
        case all
        case only(String)
    }

    public enum AssigneeFilter: Hashable, Sendable, Codable {
        case me
        case anyone
        case user(String)
    }

    public enum Sort: String, CaseIterable, Sendable, Codable {
        case updated, created, priority, timeToday, title
    }

    public var status: StatusFilter = .open
    public var assignee: AssigneeFilter = .me
    public var priorities: Set<TicketPriority> = []
    public var sort: Sort = .updated
    public var ascending = false

    public init() {}

    /// How many filters narrow the list compared with showing everything.
    public var activeFilterCount: Int {
        (status == .all ? 0 : 1) + (assignee == .anyone ? 0 : 1) + (priorities.isEmpty ? 0 : 1)
    }

    /// Filters and sorts `tickets`. `secondsToday` gives each ticket's tracked
    /// time today, by ticket id, for the time sort.
    public func apply(to tickets: [Ticket], me: String, secondsToday: [String: Int] = [:]) -> [Ticket] {
        let filtered = tickets.filter { ticket in
            switch status {
            case .open: if ticket.status == "closed" { return false }
            case .all: break
            case let .only(value): if ticket.status != value { return false }
            }
            switch assignee {
            case .me: if !ticket.assignedTo.contains(me) { return false }
            case .anyone: break
            case let .user(id): if !ticket.assignedTo.contains(id) { return false }
            }
            if !priorities.isEmpty, !priorities.contains(TicketPriority(raw: ticket.priority)) { return false }
            return true
        }
        // Each comparison says whether `a` comes first in descending order;
        // ties fall back to newest first so the order is stable.
        let descending: (Ticket, Ticket) -> Bool = { a, b in
            switch sort {
            case .updated:
                let (x, y) = (a.updatedAt ?? a.createdAt ?? .distantPast, b.updatedAt ?? b.createdAt ?? .distantPast)
                if x != y { return x > y }
            case .created:
                let (x, y) = (a.createdAt ?? .distantPast, b.createdAt ?? .distantPast)
                if x != y { return x > y }
            case .priority:
                let (x, y) = (TicketPriority(raw: a.priority).rank, TicketPriority(raw: b.priority).rank)
                if x != y { return x > y }
            case .timeToday:
                let (x, y) = (secondsToday[a.id] ?? 0, secondsToday[b.id] ?? 0)
                if x != y { return x > y }
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedDescending }
            }
            return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
        }
        return filtered.sorted { ascending ? descending($1, $0) : descending($0, $1) }
    }

    /// Case- and diacritic-insensitive title search; nil when it doesn't match,
    /// otherwise where the match is, for highlighting.
    public static func match(_ query: String, in title: String) -> Range<String.Index>? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
    }
}
