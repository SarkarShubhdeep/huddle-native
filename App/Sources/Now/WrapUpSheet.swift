import HuddleKit
import SwiftUI

/// End of day: what you did, a wrap-up note (filled in from today's work, so
/// it's one tap), then clock out. Offered every time; skippable unless the
/// team requires a wrap-up.
struct WrapUpSheet: View {
    /// The shift's team requires a wrap-up before clock-out.
    let requiresWrapUp: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(NowModel.self) private var now
    @State private var note = ""
    @State private var plan: HuddlePost?
    @State private var loadedPlan = false
    @State private var ending: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    summary
                    if !now.entries.isEmpty {
                        EdgeToEdgeList {
                            ForEach(now.entries, id: \.entry.id) { entry in
                                WorkRow(title: entry.entry.displayTitle ?? "Ticket",
                                        duration: hoursMinutes(entry.totalSeconds(at: .now)))
                            }
                        }
                        .padding(.horizontal, -Spacing.xl)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Wrap-up").font(.footnote).foregroundStyle(Palette.textSecondary)
                        ComposerField(text: $note, placeholder: "What got done, what’s next…")
                            .padding(.horizontal, Spacing.s)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
                    }
                    if let error = now.actionError {
                        InlineError(message: error)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.l)
            }
            .background(Palette.canvas)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(plan != nil ? "Adds to this morning’s plan" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(ending != nil)
        .task {
            now.actionError = nil
            if note.isEmpty { note = suggestedNote }
            plan = await now.sessionPost()
            loadedPlan = true
        }
    }

    private var summary: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let worked = ShiftClock.workSeconds(now.active, at: context.date)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Wrap up your day")
                    .font(.title.bold())
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(ShiftClockFormat.duration(worked))
                    .font(Typography.time(.largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel("Worked \(ShiftClockFormat.spoken(worked))")
                Text(rangeLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.s) {
            Button { end(withNote: true) } label: {
                if ending == true { ProgressView().tint(Palette.onLime) } else { Text("Post wrap-up & end day") }
            }
            .buttonStyle(.primaryLarge)
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ending != nil || !loadedPlan)
            if !requiresWrapUp {
                Button { end(withNote: false) } label: {
                    if ending == false { ProgressView() } else { Text("End day without posting") }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: 44)
                .disabled(ending != nil)
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.s)
        .background(Palette.canvas)
    }

    private func end(withNote: Bool) {
        ending = withNote
        Task {
            if await now.endDay(note: withNote ? note : nil, plan: plan) { dismiss() }
            ending = nil
        }
    }

    /// Today's tickets with their times, as a starting point.
    private var suggestedNote: String {
        let worked = now.entries.filter { $0.totalSeconds(at: .now) >= 60 }
        guard !worked.isEmpty else { return "" }
        return "Worked on " + worked.map { "\($0.entry.displayTitle ?? "a ticket") (\(hoursMinutes($0.totalSeconds(at: .now))))" }
            .joined(separator: ", ") + "."
    }

    private var rangeLine: String {
        guard let active = now.active else { return "" }
        var line = "\(active.startTime.formatted(date: .omitted, time: .shortened)) – now"
        if active.deductedBreakSeconds > 0 {
            line += " · \(active.deductedBreakSeconds / 60) min unpaid meal"
        }
        return line
    }

    private func hoursMinutes(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
