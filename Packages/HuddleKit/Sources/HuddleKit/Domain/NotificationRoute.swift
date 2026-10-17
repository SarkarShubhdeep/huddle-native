import Foundation

/// Where tapping a notification goes in the app, from the web path it carries.
public enum NotificationRoute: Equatable, Sendable {
    case now
    case tickets
    case huddle(teamId: String?)
    case time
    /// Nothing better to show; stay in the inbox.
    case none

    public init(_ notification: AppNotification) {
        self.init(path: notification.path, type: notification.type)
    }

    public init(path: String?, type: String?) {
        let components = path.flatMap { URLComponents(string: $0) }
        let route = components?.path ?? ""
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })

        if route.hasPrefix("/app/huddle") {
            self = .huddle(teamId: query["teamId"])
        } else if route.hasPrefix("/app/tickets") {
            self = .tickets
        } else if query["tab"] == "timesheet" || query["tab"] == "work" || route.hasPrefix("/app/timesheet") || route.hasPrefix("/app/work") {
            self = .time
        } else if route.hasPrefix("/app/clock") || route.hasPrefix("/app/dashboard") {
            self = .now
        } else if let type {
            switch type {
            case _ where type.hasPrefix("clock") || type.hasPrefix("shift"): self = .now
            case _ where type.hasPrefix("ticket"): self = .tickets
            case _ where type.hasPrefix("huddle") || type.contains("mention"): self = .huddle(teamId: nil)
            case _ where type.hasPrefix("timesheet"): self = .time
            default: self = .none
            }
        } else {
            self = .none
        }
    }
}
