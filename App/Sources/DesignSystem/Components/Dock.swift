import SwiftUI

/// The five tabs, in dock order.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case now, tickets, huddle, time, inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .tickets: "Tickets"
        case .huddle: "Huddle"
        case .time: "Time"
        case .inbox: "Inbox"
        }
    }

    var systemImage: String {
        switch self {
        case .now: "clock"
        case .tickets: "list.bullet"
        case .huddle: "bubble.left"
        case .time: "chart.bar"
        case .inbox: "bell"
        }
    }
}

/// What the timer strip shows. `nil` means off the clock, and the strip is hidden.
enum TimerStripState: Equatable, Sendable {
    /// On shift with a ticket timer running.
    case timing(shiftSeconds: Int, ticketTitle: String, ticketSeconds: Int)
    /// On shift, no ticket timer.
    case onShift(shiftSeconds: Int)
    /// On a break; the ticket timer (if any) is paused.
    case onBreak(breakSeconds: Int, pausedTicketTitle: String?, ticketSeconds: Int?)
}

/// The app's one glass dock: the system Liquid Glass tab bar with the timer
/// strip as its bottom accessory. The tab bar minimizes on scroll, and the
/// strip then moves inline beside it.
struct AppDock<Content: View>: View {
    @Binding var selection: AppTab
    var strip: TimerStripState?
    var inboxBadge = 0
    var onStripAction: () -> Void = {}
    @ViewBuilder var content: (AppTab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    content(tab)
                }
                .badge(tab == .inbox ? inboxBadge : 0)
            }
        }
        .tint(Palette.limeText)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(TimerAccessory(state: strip, action: onStripAction))
    }
}

/// Adds the timer strip as the tab view's bottom accessory, or none when off the clock.
private struct TimerAccessory: ViewModifier {
    let state: TimerStripState?
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: state != nil) {
                if let state { TimerStrip(state: state, action: action) }
            }
        } else if let state {
            content.tabViewBottomAccessory { TimerStrip(state: state, action: action) }
        } else {
            content
        }
    }
}

/// The dock's top row while on the clock: the shift total, the ticket and its
/// time, and one action. Inline (tab bar minimized) it shows just the times.
struct TimerStrip: View {
    let state: TimerStripState
    var action: () -> Void = {}

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: Spacing.m) {
            if placement == .inline {
                inlineContent
            } else {
                shiftColumn
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1, height: 28)
                    .accessibilityHidden(true)
                ticketColumn
            }
            Button(actionLabel, systemImage: actionIcon, action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(HNIconButtonStyle(role: actionIsPrimary ? .primary : .secondary, diameter: 36))
        }
        .padding(.leading, Spacing.l)
        .padding(.trailing, Spacing.xs)
        .springAnimation(value: state)
    }

    private var shiftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(shiftColor).frame(width: 6, height: 6)
                Text(shiftLabel).textCase(.uppercase)
            }
            .font(Typography.microLabel)
            .tracking(0.4)
            .foregroundStyle(shiftColor)
            Text(ShiftClockFormat.clock(shiftSeconds))
                .font(Typography.time(.headline))
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shiftLabel)
        .accessibilityValue(ShiftClockFormat.spoken(shiftSeconds))
    }

    private var ticketColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ticketCaption)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Text(ticketLine)
                .font(Typography.time(.subheadline))
                .foregroundStyle(ticketColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inlineContent: some View {
        HStack(spacing: Spacing.s) {
            Circle().fill(shiftColor).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(ShiftClockFormat.clock(shiftSeconds))
                .font(Typography.time(.subheadline))
                .foregroundStyle(Palette.textPrimary)
            if let ticketSeconds {
                Text(ShiftClockFormat.clock(ticketSeconds))
                    .font(Typography.time(.subheadline))
                    .foregroundStyle(ticketColor)
            }
        }
        .contentTransition(.numericText())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shiftLabel)
        .accessibilityValue(ShiftClockFormat.spoken(shiftSeconds))
    }

    // MARK: State → content

    private var shiftSeconds: Int {
        switch state {
        case let .timing(shift, _, _), let .onShift(shift): shift
        case let .onBreak(breakSeconds, _, _): breakSeconds
        }
    }

    private var ticketSeconds: Int? {
        switch state {
        case let .timing(_, _, ticket): ticket
        case .onShift: nil
        case let .onBreak(_, _, ticket): ticket
        }
    }

    private var shiftLabel: String {
        if case .onBreak = state { "On break" } else { "Shift" }
    }

    private var shiftColor: Color {
        if case .onBreak = state { Palette.breakText } else { Palette.limeText }
    }

    private var ticketCaption: String {
        switch state {
        case let .timing(_, title, _): title
        case .onShift: "No ticket timer running"
        case let .onBreak(_, title?, _): "Ticket paused · \(title)"
        case .onBreak: "No ticket timer"
        }
    }

    private var ticketLine: String {
        switch state {
        case let .timing(_, _, seconds): ShiftClockFormat.clock(seconds)
        case .onShift: "Pick a ticket"
        case let .onBreak(_, _, seconds?): ShiftClockFormat.clock(seconds)
        case .onBreak: "Paused"
        }
    }

    private var ticketColor: Color {
        switch state {
        case .timing: Palette.limeText
        case .onShift: Palette.textPrimary
        case .onBreak: Palette.textSecondary
        }
    }

    private var actionLabel: String {
        switch state {
        case .timing: "Pause ticket timer"
        case .onShift: "Pick a ticket to time"
        case .onBreak: "Back to work"
        }
    }

    private var actionIcon: String {
        if case .timing = state { "pause.fill" } else { "play.fill" }
    }

    private var actionIsPrimary: Bool {
        if case .timing = state { false } else { true }
    }
}

// MARK: - Previews

private struct DockPreview: View {
    @State private var tab: AppTab = .tickets
    let strip: TimerStripState?

    var body: some View {
        AppDock(selection: $tab, strip: strip, inboxBadge: 3) { tab in
            NavigationStack {
                List(0..<30) { Text("Row \($0)") }
                    .listStyle(.plain)
                    .navigationTitle(tab.title)
            }
        }
    }
}

#Preview("Timing · Light") {
    DockPreview(strip: .timing(shiftSeconds: 13338, ticketTitle: "Fix login redirect on iPad", ticketSeconds: 2530))
}
#Preview("Timing · Dark") {
    DockPreview(strip: .timing(shiftSeconds: 13338, ticketTitle: "Fix login redirect on iPad", ticketSeconds: 2530))
        .preferredColorScheme(.dark)
}
#Preview("On shift") { DockPreview(strip: .onShift(shiftSeconds: 13338)) }
#Preview("On break · Dark") {
    DockPreview(strip: .onBreak(breakSeconds: 760, pausedTicketTitle: "Fix login redirect", ticketSeconds: 2530))
        .preferredColorScheme(.dark)
}
#Preview("Off the clock") { DockPreview(strip: nil) }
