import HuddleKit
import SwiftUI

/// Tapping play while off the clock: ticket timers only run during a shift,
/// so offer to start the day and the timer together.
struct StartTimerSheet: View {
    let ticket: Ticket
    let teamName: String
    /// Starts the day and the timer; returns whether it worked. (When the team
    /// needs a plan, it hands over to the plan sheet and returns false.)
    var start: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(NowModel.self) private var now
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            VStack(spacing: Spacing.m) {
                Image(systemName: "sun.max")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.limeText)
                    .frame(width: 60, height: 60)
                    .background(Palette.limeSoft, in: Circle())
                    .accessibilityHidden(true)
                Text("You’re off the clock")
                    .font(.title2.bold())
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Ticket timers only run during a shift. Start your day and the timer for this ticket together?")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.l)

            HStack(spacing: Spacing.m) {
                Circle().fill(TicketStatus(raw: ticket.status).color).frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(ticket.title).font(.body.weight(.medium)).foregroundStyle(Palette.textPrimary).lineLimit(2)
                Spacer(minLength: 0)
                Text(teamName).font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .padding(.vertical, Spacing.m)
            .padding(.horizontal, 14)
            .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)

            if let error = now.actionError { InlineError(message: error) }

            VStack(spacing: Spacing.s) {
                Button {
                    isStarting = true
                    Task {
                        if await start() { dismiss() }
                        isStarting = false
                    }
                } label: {
                    if isStarting { ProgressView().tint(Palette.onLime) } else { Text("Start day & timer") }
                }
                .buttonStyle(.primaryLarge)
                .disabled(isStarting)
                Button("Not now") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: 44)
            }
            Text("If your team asks for a plan first, the plan sheet opens next, with this ticket filled in.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
        .onAppear { now.actionError = nil }
    }
}
