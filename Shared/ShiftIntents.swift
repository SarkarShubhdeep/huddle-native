import AppIntents
import Foundation
import HuddleKit
import UserNotifications

// The shift actions for Siri, Shortcuts, the Action button, Control Center,
// widgets and the Live Activity. They're `LiveActivityIntent`s, so they run
// in the app's process (launched in the background if needed), which is the
// only place that can update the Live Activity.

/// Runs one shift action, then republishes the state everywhere.
@MainActor
enum ShiftIntentRunner {
    /// Runs `action`. When the team asks for a plan or wrap-up, which only the
    /// app can write, it asks to open Huddle on that sheet instead of failing
    /// silently (Control Center shows nothing for a failed action).
    static func run(_ intent: some AppIntent, _ action: @escaping (ShiftActions) async throws -> Void) async throws {
        guard let actions = SharedContainer.actions() else {
            throw ShiftActions.Failure.needsApp("Open Huddle and sign in first.")
        }
        do {
            try await action(actions)
        } catch let failure as ShiftActions.Failure where failure == .needsPlan || failure == .needsWrapUp {
            SharedContainer.pendingSheet = failure == .needsPlan ? .plan : .wrapUp
            let message = failure.errorDescription ?? ""
            do {
                try await intent.continueInForeground(IntentDialog(stringLiteral: message), alwaysConfirm: false)
            } catch {
                // Control Center can't bring the app forward; a notification
                // says what's needed, and tapping it opens that sheet.
                await ShiftNotice.post(failure == .needsPlan ? "Write your plan to start the day." : "Post your wrap-up to end the day.")
            }
            return
        }
        let snapshot = try await SharedContainer.refresh()
        await ShiftLiveActivity.sync(snapshot)
        NotificationCenter.default.post(name: .shiftChangedOutsideApp, object: nil)
    }

    static func startDay(_ intent: some AppIntent, _ actions: ShiftActions) async throws {
        let teamId = SharedContainer.teamId
        try await actions.startDay(teamId: teamId, requiresPlan: teamId.map(SharedContainer.planTeams.contains) ?? false)
    }
}

struct StartDayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Day"
    /// Runs in the background, but may come forward to write a plan or wrap-up.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    static let description = IntentDescription("Clocks you in to your current team.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShiftIntentRunner.run(self) { try await ShiftIntentRunner.startDay(self, $0) }
        return .result(dialog: "You’re on the clock.")
    }
}

struct TakeBreakIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static let description = IntentDescription("Starts a break and pauses your ticket timer.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShiftIntentRunner.run(self) { try await $0.takeBreak() }
        return .result(dialog: "Enjoy the break. After 20 minutes it counts as an unpaid meal break.")
    }
}

struct BackToWorkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back to Work"
    static let description = IntentDescription("Ends your break and restarts the ticket timer it paused.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShiftIntentRunner.run(self) { try await $0.resume() }
        return .result(dialog: "Welcome back.")
    }
}

struct EndDayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Day"
    /// Runs in the background, but may come forward to write a plan or wrap-up.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    static let description = IntentDescription("Clocks you out. If your team asks for a wrap-up, open Huddle to post it first.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShiftIntentRunner.run(self) { try await $0.endDay() }
        return .result(dialog: "You’re off the clock.")
    }
}

struct PauseTicketIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Ticket Timer"
    static let description = IntentDescription("Stops the ticket timer that’s running.")

    func perform() async throws -> some IntentResult {
        try await ShiftIntentRunner.run(self) { try await $0.pauseTicket() }
        return .result()
    }
}

/// A ticket on your current team, for "Start ticket timer".
struct TicketEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ticket"
    static let defaultQuery = TicketEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TicketEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TicketEntity] {
        try await openTickets().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [TicketEntity] {
        try await openTickets().filter { TicketQuery.match(string, in: $0.title) != nil }
    }

    func suggestedEntities() async throws -> [TicketEntity] {
        Array(try await openTickets().prefix(20))
    }

    private func openTickets() async throws -> [TicketEntity] {
        guard let session = SharedContainer.session, let teamId = SharedContainer.teamId else { return [] }
        let token = session.token
        let api = APIClient(endpoint: session.endpoint, token: { token })
        return try await TicketService(api).list(teamId: teamId)
            .filter { $0.status != "closed" && $0.assignedTo.contains(session.userId) }
            .map { TicketEntity(id: $0.id, title: $0.title) }
    }
}

struct StartTicketTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Ticket Timer"
    static let description = IntentDescription("Starts the timer for one of your tickets. You need to be on the clock.")

    @Parameter(title: "Ticket") var ticket: TicketEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = ticket.id
        try await ShiftIntentRunner.run(self) { try await $0.startTicket(id) }
        return .result(dialog: "Timing \(ticket.title).")
    }
}

/// A local notification for an action that needs the app.
enum ShiftNotice {
    static let identifier = "huddle.shift.needsApp"

    static func post(_ body: String) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Huddle"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Asks once, and only for someone on a team that uses plans.
    static func requestPermissionIfUseful() async {
        guard !SharedContainer.planTeams.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
