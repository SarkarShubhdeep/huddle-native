import Foundation

// Shapes returned by the Meteor methods the app uses, read from the backend source
// (meteor-backend/server/*.js). Ids are strings. Clock and timer times arrive as
// epoch milliseconds; posts, notifications and timer `createdAt` as ISO strings —
// `APIClient.makeDecoder()` reads both into `Date`. Calendar days stay
// `"YYYY-MM-DD"` strings, because the server keys work items by the local date.

// MARK: - Teams and people

public struct Team: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let orgId: String?
    public let parentTeamId: String?
    public let description: String?
    @DefaultEmpty public var members: [String]
    @DefaultEmpty public var admins: [String]
    @DefaultFalse public var isPersonal: Bool
    public let settings: Settings?
    public let resolvedSettings: ResolvedSettings?

    public struct Settings: Codable, Sendable, Hashable {
        public let requirePlanForClock: Bool?
    }

    public struct ResolvedSettings: Codable, Sendable, Hashable {
        public let requirePlanForClock: Resolved?
        public struct Resolved: Codable, Sendable, Hashable { public let value: Bool }
    }

    /// The team asks for a plan post before clocking in, and a wrap-up before clocking out.
    public var requiresPlan: Bool {
        resolvedSettings?.requirePlanForClock?.value ?? settings?.requirePlanForClock ?? false
    }

    public func isAdmin(_ userId: String) -> Bool { admins.contains(userId) }
}

public struct TeamsList: Codable, Sendable { @DefaultEmpty public var teams: [Team] }

public struct TeamMember: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let email: String?
    public let username: String?
    public let image: String?

    public var displayName: String { name ?? username ?? email ?? "Teammate" }
}

public struct TeamMembers: Codable, Sendable { @DefaultEmpty public var members: [TeamMember] }

public struct PublicUser: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String?
    public let username: String?
    public let image: String?
    public let bio: String?

    public var displayName: String { name ?? username ?? "You" }

    /// "Shubhdeep Sarkar" → "SS"; falls back to the first letter of the handle.
    public var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

public struct UserEnvelope: Codable, Sendable { public let user: PublicUser }

// MARK: - Clock

public struct ClockEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let userId: String?
    public let teamId: String
    public let startTime: Date
    public let endTime: Date?
    @DefaultZero public var accumulatedTime: Int
    @DefaultEmpty public var breaks: [Break]
    public let workSeconds: Int?
    @DefaultZero public var deductedBreakSeconds: Int
    @DefaultZero public var totalBreakSeconds: Int
    @DefaultFalse public var isPaused: Bool
    /// Only `clock.timesheet` includes these.
    @DefaultEmpty public var ticketSessions: [ShiftTicketSession]

    public var isOpen: Bool { endTime == nil }
    public var openBreak: Break? { breaks.last { $0.endTime == nil } }
}

public struct Break: Codable, Sendable, Hashable {
    public let startTime: Date
    public let endTime: Date?
    /// `rest` (paid, under 20 min) or `meal` (unpaid, 20 min or more). Missing while open.
    public let type: String?
    public let notes: String?

    public var isMeal: Bool { type == "meal" }
}

public struct ClockStatus: Codable, Sendable, Hashable {
    public let event: ClockEvent
    public let workSeconds: Int
    public let isPaused: Bool
}

public struct ShiftTicketSession: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let ticketId: String?
    public let title: String?
    public let startTime: Date
    public let endTime: Date?
    public let durationSeconds: Int?
}

public struct Timesheet: Codable, Sendable, Hashable {
    @DefaultEmpty public var sessions: [ClockEvent]
    public let summary: Summary

    public struct Summary: Codable, Sendable, Hashable {
        @DefaultZero public var totalSeconds: Int
        @DefaultZero public var totalBreakSeconds: Int
        @DefaultZero public var totalSessions: Int
        @DefaultZero public var completedSessions: Int
        public let averageSessionSeconds: Double?
        @DefaultZero public var workingDays: Int
    }
}

// MARK: - Tickets

public struct Ticket: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let teamId: String
    public let title: String
    public let description: String?
    public let github: String?
    public let status: String
    public let priority: String?
    public let createdBy: String?
    public let assignedTo: [String]
    public let createdAt: Date?
    public let updatedAt: Date?

    public static let statuses = ["open", "in-progress", "blocked", "reviewed", "closed"]

    private enum CodingKeys: String, CodingKey {
        case id, _id, teamId, title, description, github, status, priority, createdBy, assignedTo, createdAt, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: ._id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "Ticket has neither id nor _id"))
        }
        self.id = id
        teamId = try c.decode(String.self, forKey: .teamId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        github = try c.decodeIfPresent(String.self, forKey: .github).flatMap { $0.isEmpty ? nil : $0 }
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        // Older tickets stored a single assignee as a string.
        if let many = try? c.decode([String].self, forKey: .assignedTo) {
            assignedTo = many
        } else {
            assignedTo = (try? c.decode(String.self, forKey: .assignedTo)).map { [$0] } ?? []
        }
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(teamId, forKey: .teamId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(github, forKey: .github)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encode(assignedTo, forKey: .assignedTo)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Ticket timers

/// One ticket on one day for one user; its timer sessions hang off it.
public struct WorkItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let source: String?
    public let ticketId: String
    public let displayTitle: String?
    public let date: String
    public let note: String?
}

public struct TimerSession: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let workItemId: String
    public let clockEventId: String?
    public let date: String?
    public let startTime: Date
    public let endTime: Date?
    public let durationSeconds: Int?

    public var isRunning: Bool { endTime == nil }

    public func seconds(at now: Date = .now) -> Int {
        durationSeconds ?? max(0, Int(now.timeIntervalSince(startTime)))
    }
}

public struct DayEntry: Codable, Sendable, Hashable {
    public let entry: WorkItem
    @DefaultEmpty public var sessions: [TimerSession]

    public func totalSeconds(at now: Date = .now) -> Int {
        sessions.reduce(0) { $0 + $1.seconds(at: now) }
    }
}

public struct DayEntries: Codable, Sendable, Hashable { @DefaultEmpty public var entries: [DayEntry] }

public struct WeekDay: Codable, Sendable, Hashable {
    public let date: String
    @DefaultZero public var totalSeconds: Int
}

public struct Week: Codable, Sendable, Hashable { @DefaultEmpty public var days: [WeekDay] }

public struct RunningTimer: Codable, Sendable, Hashable { public let session: TimerSession? }

public struct TimerStarted: Codable, Sendable, Hashable {
    public let session: TimerSession
    public let closedSessionId: String?
}

public struct TimerStopped: Codable, Sendable, Hashable { public let session: TimerSession }

public struct EntryCreated: Codable, Sendable, Hashable {
    public let entry: WorkItem
    public let session: TimerSession?
}

public struct TicketTotal: Codable, Sendable, Hashable { @DefaultZero public var totalSeconds: Int }

// MARK: - Huddle

public struct HuddlePost: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let teamId: String
    public let userId: String
    public let userName: String?
    public let userInitials: String?
    public let content: Content
    public let ticketId: String?
    public let ticketTitle: String?
    @DefaultEmpty public var attachments: [Attachment]
    @DefaultEmpty public var likes: [String]
    @DefaultZero public var commentCount: Int
    public let postDate: String?
    public let clockEventId: String?
    public let session: PostSession?
    public let wrapUpAt: Date?
    public let createdAt: Date
    public let updatedAt: Date?

    public struct Content: Codable, Sendable, Hashable {
        public let text: String
        @DefaultEmpty public var mentions: [String]

        public init(text: String, mentions: [String] = []) {
            self.text = text
            self.mentions = mentions
        }
    }

    public struct PostSession: Codable, Sendable, Hashable {
        public let startTime: Date
        public let endTime: Date?
    }

    public enum Kind: Sendable { case post, plan, wrapUp }

    /// A post tied to a shift is its plan until a wrap-up is added to it.
    public var kind: Kind {
        if wrapUpAt != nil { return .wrapUp }
        return clockEventId != nil ? .plan : .post
    }

    public var isEdited: Bool {
        guard let updatedAt else { return false }
        return abs(updatedAt.timeIntervalSince(createdAt)) > 1
    }
}

public struct Attachment: Codable, Sendable, Hashable {
    public let mediaId: String?
    public let type: String
    public let url: String
    public let thumbnailUrl: String?
    public let filename: String?

    public var isImage: Bool { type == "image" }
}

public struct PostsPage: Codable, Sendable, Hashable {
    @DefaultEmpty public var posts: [HuddlePost]
    @DefaultFalse public var hasMore: Bool
}

public struct PostLookup: Codable, Sendable, Hashable { public let post: HuddlePost? }

public struct CreatedID: Codable, Sendable, Hashable { public let id: String }

// MARK: - Inbox

public struct AppNotification: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let body: String?
    public let data: JSONValue?
    @DefaultFalse public var read: Bool
    public let createdAt: Date

    /// e.g. `clock-session-changed`, `ticket-assigned`.
    public var type: String? { data?["type"]?.stringValue }
    /// A web-app path such as `/app/dashboard?tab=timesheet`, used to route a tap.
    public var path: String? { data?["url"]?.stringValue }
}

public struct Inbox: Codable, Sendable, Hashable { @DefaultEmpty public var notifications: [AppNotification] }

public struct OKResult: Codable, Sendable, Hashable { @DefaultFalse public var ok: Bool }

public struct DeletedCount: Codable, Sendable, Hashable { @DefaultZero public var deletedCount: Int }
