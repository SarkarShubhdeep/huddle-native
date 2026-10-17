import AppIntents
import Foundation
import HuddleKit

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
            try await intent.continueInForeground(IntentDialog(stringLiteral: failure.errorDescription ?? ""), alwaysConfirm: false)
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
