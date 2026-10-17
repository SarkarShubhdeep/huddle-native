import Foundation
import HuddleKit
import Observation

/// One team's tickets and members, plus the list's filters and sort.
@MainActor
@Observable
final class TicketsModel {
    let teamId: String
    let tickets: Resource<[Ticket]>
    let members: Resource<[TeamMember]>
    /// Filters and sort; remembered across launches.
    var query: TicketQuery { didSet { Self.save(query) } }

    @ObservationIgnored private let service: TicketService

    init(api: APIClient, teamId: String, snapshots: any SnapshotStore) {
        self.teamId = teamId
        let service = TicketService(api)
        let teams = TeamService(api)
        self.service = service
        tickets = Resource(cacheKey: "tickets.\(teamId)", store: snapshots) { try await service.list(teamId: teamId) }
        members = Resource(cacheKey: "members.\(teamId)", store: snapshots) { try await teams.members(teamId: teamId) }
        query = Self.load()
    }

    func load() async {
        async let a: Void = tickets.load()
        async let b: Void = members.load()
        _ = await (a, b)
    }

    func refresh() async {
        async let a: Void = tickets.refresh()
        async let b: Void = members.refresh()
        _ = await (a, b)
    }

    func name(of userId: String) -> String {
        members.value?.first { $0.id == userId }?.displayName ?? "Teammate"
    }

    func initials(of userId: String) -> String {
        Self.initials(name(of: userId))
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    // MARK: Writes

    /// Creates a ticket and shows it at once; returns it.
    func create(_ ticket: TicketService.NewTicket) async throws -> Ticket {
        let created = try await service.create(ticket)
        tickets.set([created] + (tickets.value ?? []))
        await tickets.refetch()
        return created
    }

    func setStatus(_ status: TicketStatus, of ticket: Ticket) async throws {
        _ = try await service.setStatus(status.rawValue, ticketId: ticket.id)
        await tickets.refetch()
    }

    // MARK: Persistence

    private static let key = "tickets.query"

    private static func load() -> TicketQuery {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(TicketQuery.self, from: $0) } ?? TicketQuery()
    }

    private static func save(_ query: TicketQuery) {
        UserDefaults.standard.set(try? JSONEncoder().encode(query), forKey: key)
    }
}

extension TicketQuery.Sort {
    var title: String {
        switch self {
        case .updated: "Recently updated"
        case .created: "Created"
        case .priority: "Priority"
        case .timeToday: "Time spent today"
        case .title: "Title"
        }
    }

    var descendingTitle: String {
        switch self {
        case .updated, .created: "Newest first"
        case .priority: "Highest first"
        case .timeToday: "Most first"
        case .title: "Z to A"
        }
    }

    var ascendingTitle: String {
        switch self {
        case .updated, .created: "Oldest first"
        case .priority: "Lowest first"
        case .timeToday: "Least first"
        case .title: "A to Z"
        }
    }
}

extension TicketPriority {
    var title: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    var shortTitle: String { self == .none ? "None" : (self == .medium ? "Med" : title) }
}
