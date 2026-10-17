import AppIntents
import HuddleKit
import SwiftUI
import WidgetKit

struct ShiftEntry: TimelineEntry {
    let date: Date
    let snapshot: ShiftSnapshot
    let signedIn: Bool
}

/// Shows the last published state at once, then asks the backend (capped at
/// 6 s, like every refresh in the app). Times tick on their own, so the
/// timeline only needs a new entry when the state changes.
struct ShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShiftEntry {
        ShiftEntry(date: .now, snapshot: ShiftSnapshot(phase: .working, workingSince: .now.addingTimeInterval(-13338),
                                                       ticketTitle: "Fix login redirect", ticketSince: .now.addingTimeInterval(-2530)),
                   signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        // WidgetKit calls this completion once, from any thread.
        nonisolated(unsafe) let completion = completion
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = try? await SharedContainer.refresh() }
                group.addTask { try? await Task.sleep(for: .seconds(6)) }
                await group.next()
                group.cancelAll()
            }
            // Check back in 15 minutes (the system decides exactly when); at
            // midnight the day's totals reset.
            let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
            let next = min(Date.now.addingTimeInterval(15 * 60), tomorrow)
            completion(Timeline(entries: [current()], policy: .after(next)))
        }
    }

    private func current() -> ShiftEntry {
        ShiftEntry(date: .now, snapshot: SharedContainer.snapshot, signedIn: SharedContainer.session != nil)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: ShiftProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your shift and the ticket you’re timing.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: ShiftEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: ShiftSnapshot { entry.snapshot }

    var body: some View {
        if !entry.signedIn {
            Text("Open Huddle to sign in").font(.footnote).foregroundStyle(.secondary)
        } else {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
    }

    // MARK: Lock Screen

    private var inline: some View {
        HStack {
            Image(systemName: snapshot.symbol)
            if snapshot.isOnShift { ShiftTimeText(snapshot: snapshot) } else { Text(snapshot.label) }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: snapshot.symbol).font(.caption)
                if snapshot.isOnShift {
                    ShiftTimeText(snapshot: snapshot, size: 11)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(snapshot.label, systemImage: snapshot.symbol).font(.caption.weight(.semibold))
                .widgetAccentable()
            ShiftTimeText(snapshot: snapshot, size: 20)
            if let title = snapshot.ticketTitle {
                Text(title).font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            ShiftTimeText(snapshot: snapshot)
            ticketLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                ShiftTimeText(snapshot: snapshot, size: 34)
                ticketLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            actionButton
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle().fill(snapshot.tint).frame(width: 7, height: 7)
            Text(snapshot.label).font(.caption.weight(.semibold)).foregroundStyle(snapshot.tint)
            Spacer(minLength: 0)
            if let team = snapshot.teamName {
                Text(team).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var ticketLine: some View {
        if let title = snapshot.ticketTitle {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                TicketTimeText(snapshot: snapshot, alignment: .trailing).monospacedDigit()
                    .foregroundStyle(snapshot.ticketSince != nil ? WidgetPalette.limeText : .secondary)
            }
            .font(.caption)
        } else {
            Text(snapshot.phase == .working ? "No ticket timer" : (snapshot.phase == .dayDone ? "Nice work today" : "Not started today"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The one next step, run right from the widget.
    @ViewBuilder private var actionButton: some View {
        switch snapshot.phase {
        case .offClock, .dayDone:
            Button(intent: StartDayIntent()) { Label("Start day", systemImage: "play.fill") }
                .tint(WidgetPalette.lime).foregroundStyle(WidgetPalette.onLime)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        case .working:
            Button(intent: TakeBreakIntent()) { Label("Break", systemImage: "cup.and.saucer.fill") }
                .tint(.primary)
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
        case .onBreak:
            Button(intent: BackToWorkIntent()) { Label("Back", systemImage: "play.fill") }
                .tint(WidgetPalette.lime).foregroundStyle(WidgetPalette.onLime)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }
}

#Preview("Working", as: .systemMedium) {
    TodayWidget()
} timeline: {
    ShiftEntry(date: .now, snapshot: ShiftSnapshot(phase: .working, teamName: "Development team",
                                                   workingSince: .now.addingTimeInterval(-13338),
                                                   ticketTitle: "Fix login redirect", ticketSince: .now.addingTimeInterval(-2530)),
               signedIn: true)
    ShiftEntry(date: .now, snapshot: ShiftSnapshot(phase: .onBreak, workedSeconds: 13338, breakStart: .now.addingTimeInterval(-400)),
               signedIn: true)
}
