import ActivityKit
import AppIntents
import HuddleKit
import SwiftUI
import WidgetKit

/// The open shift on the Lock Screen and in the Dynamic Island: the shift
/// time, the ticket and its time, and Break / Back / Pause.
struct ShiftLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            LockScreenShiftView(snapshot: context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(WidgetPalette.lime)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.caption).foregroundStyle(.secondary)
                        ShiftTimeText(snapshot: s, size: 24)
                            .foregroundStyle(s.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let title = s.ticketTitle {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            TicketTimeText(snapshot: s, alignment: .trailing).font(.headline.monospacedDigit())
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ShiftActivityButtons(snapshot: s)
                }
            } compactLeading: {
                Image(systemName: s.phase == .onBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(s.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime)
            } compactTrailing: {
                ShiftTimeText(snapshot: s, size: 14)
                    .foregroundStyle(s.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: s.phase == .onBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(s.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime)
            }
            .keylineTint(WidgetPalette.lime)
        }
    }
}

private struct LockScreenShiftView: View {
    let snapshot: ShiftSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.phase == .onBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(WidgetPalette.onLime)
                    .frame(width: 28, height: 28)
                    .background(snapshot.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime, in: RoundedRectangle(cornerRadius: 8))
                Text([snapshot.label, snapshot.teamName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let meal = snapshot.mealBreakAt, snapshot.phase == .onBreak, meal > .now {
                    Text("Meal in \(Text(timerInterval: Date.now...meal, countsDown: true))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .lastTextBaseline) {
                ShiftTimeText(snapshot: snapshot, size: 40)
                    .foregroundStyle(snapshot.phase == .onBreak ? WidgetPalette.breakText : WidgetPalette.lime)
                Spacer()
                if let title = snapshot.ticketTitle {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        TicketTimeText(snapshot: snapshot, alignment: .trailing).font(.headline.monospacedDigit())
                    }
                }
            }
            ShiftActivityButtons(snapshot: snapshot)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

private struct ShiftActivityButtons: View {
    let snapshot: ShiftSnapshot

    var body: some View {
        HStack(spacing: 8) {
            if snapshot.phase == .onBreak {
                Button(intent: BackToWorkIntent()) { Label("Back to work", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .tint(WidgetPalette.lime).foregroundStyle(WidgetPalette.onLime)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(intent: TakeBreakIntent()) { Label("Break", systemImage: "cup.and.saucer.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(.white)
                if snapshot.ticketSince != nil {
                    Button(intent: PauseTicketIntent()) { Label("Pause ticket", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(.white)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonBorderShape(.capsule)
    }
}
