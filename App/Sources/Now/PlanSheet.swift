import HuddleKit
import SwiftUI

/// "What's the plan today?" One sheet posts the plan to Huddle and clocks you
/// in with it linked to the new shift.
struct PlanSheet: View {
    let teamName: String
    /// The ticket you're about to time, written in as a mention.
    var ticket: Ticket?
    /// Posts the plan and starts the day; returns whether it worked.
    var start: (ComposedText) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now
    @State private var controller: RichEditorController
    @State private var directory: MentionDirectory?
    @State private var isStarting = false

    init(teamName: String, ticket: Ticket? = nil, start: @escaping (ComposedText) async -> Bool) {
        self.teamName = teamName
        self.ticket = ticket
        self.start = start
        let initial = ticket.map { ticket in
            RichDocument([RichBlock(.paragraph, [
                RichRun("Working on "), RichRun(ticket.title, mention: .ticket(ticketId: ticket.id)), RichRun("."),
            ])])
        } ?? RichDocument([RichBlock(.paragraph, [])])
        _controller = State(initialValue: RichEditorController(initial))
    }

    private var canStart: Bool { !controller.isEmpty && !isStarting }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("What’s the plan today?")
                        .font(.title.bold())
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(teamName) asks for one. It’s posted to Huddle and linked to this shift.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                Hairline()
                if let error = now.actionError {
                    InlineError(message: error)
                }
                Composer(controller: controller, directory: directory, placeholder: "A few lines on what you’ll work on…")
                Text("Start day posts this plan and clocks you in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.s)
            .background(Palette.canvas)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) {
                        if isStarting { ProgressView() } else { Text("Start day") }
                    }
                    .buttonStyle(HNButtonStyle(role: .primary, size: .small))
                    .disabled(!canStart)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isStarting)
        .onAppear {
            now.actionError = nil
            if directory == nil, let api = app.api, let teamId = app.team?.id {
                directory = MentionDirectory(api: api, teamId: teamId, snapshots: app.snapshotStore)
            }
        }
    }

    private func submit() {
        guard canStart else { return }
        isStarting = true
        Task {
            if await start(controller.composed) { dismiss() }
            isStarting = false
        }
    }
}
