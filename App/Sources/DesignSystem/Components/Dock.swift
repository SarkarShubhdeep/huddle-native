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

/// The app's one glass dock, as on the canvas: a single Liquid Glass shape
/// holding the timer strip on top (while on the clock) and the five tabs below.
///
/// Tabs still live in a `TabView`, so each keeps its own navigation and scroll
/// state; only the system tab bar is hidden.
///
/// Nothing may end up hidden behind the dock. The dock's measured height is
/// added as a bottom content margin for every scroll view and `List` in every
/// tab, pushed screens included, so the last row always scrolls clear of it.
/// (A safe-area inset doesn't work: it doesn't reach into the tabs'
/// navigation stacks.) Screens that don't scroll use `.clearsDock()`.
struct AppDock<Content: View>: View {
    @Binding var selection: AppTab
    var strip: TimerStripState?
    /// A ticking strip: called once a second with the current time. Takes
    /// precedence over `strip`, and only the dock redraws each second.
    var liveStrip: ((Date) -> TimerStripState?)?
    var inboxBadge = 0
    var onStripAction: () -> Void = {}
    @ViewBuilder var content: (AppTab) -> Content

    /// Dock height plus the gap under it; updated when the strip shows or hides.
    @State private var clearance: CGFloat = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    content(tab)
                        // Margins travel through the environment, so they reach every
                        // scroll view and List, including ones inside NavigationStacks.
                        .contentMargins(.bottom, clearance, for: .scrollContent)
                        .contentMargins(.bottom, clearance, for: .scrollIndicators)
                        .environment(\.dockClearance, clearance)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        .tint(Palette.limeText)
        .overlay(alignment: .bottom) {
            Group {
                if let liveStrip {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Dock(selection: $selection, strip: liveStrip(context.date), inboxBadge: inboxBadge, onStripAction: onStripAction)
                    }
                } else {
                    Dock(selection: $selection, strip: strip, inboxBadge: inboxBadge, onStripAction: onStripAction)
                }
            }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Self.bottomGap)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    clearance = height + Self.contentGap
                }
        }
    }

    /// Space between the dock and the home indicator.
    private static var bottomGap: CGFloat { Spacing.xs }
    /// Space between the end of scrolled content and the top of the dock.
    private static var contentGap: CGFloat { Spacing.s }
}

extension EnvironmentValues {
    /// How much of the bottom of the screen the dock covers, above the safe area.
    @Entry var dockClearance: CGFloat = 0
}

private struct ClearsDock: ViewModifier {
    @Environment(\.dockClearance) private var clearance

    func body(content: Content) -> some View {
        content.padding(.bottom, clearance)
    }
}

extension View {
    /// Keeps a non-scrolling screen, or a control pinned to the bottom, above the dock.
    /// Scroll views and Lists don't need this; they get the clearance as a content margin.
    func clearsDock() -> some View {
        modifier(ClearsDock())
    }
}

/// The glass shape itself: strip, hairline, tabs.
struct Dock: View {
    @Binding var selection: AppTab
    var strip: TimerStripState?
    var inboxBadge = 0
    var onStripAction: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let strip {
                TimerStrip(state: strip, action: onStripAction)
                    .frame(minHeight: 58)
                Hairline().padding(.horizontal, 18)
                    .transition(.opacity)
            }
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    DockTabButton(tab: tab, isSelected: selection == tab, badge: tab == .inbox ? inboxBadge : 0) {
                        selection = tab
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 62)
        }
        .controlGlass(in: RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.12), radius: 15, y: 10)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: strip == nil)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: selection)
    }
}

private struct DockTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Palette.destructive, in: Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Palette.limeText : Palette.textSecondary)
            .frame(maxWidth: 66, minHeight: 50)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule().fill(Palette.limeSoft).frame(maxWidth: 66)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(badge > 0 ? (badge == 1 ? "1 unread" : "\(badge) unread") : "")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
    }
}

/// The dock's top row while on the clock: the shift total, the ticket and its
/// time, and one action.
struct TimerStrip: View {
    let state: TimerStripState
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.m) {
            shiftColumn
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 32)
                .accessibilityHidden(true)
            ticketColumn
            Button(actionLabel, systemImage: actionIcon, action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(HNIconButtonStyle(role: actionIsPrimary ? .primary : .secondary))
        }
        .padding(.leading, 18)
        .padding(.trailing, Spacing.xs)
        // Like system bars, the strip stops growing at xLarge; long-press shows it enlarged.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
        .accessibilityShowsLargeContentViewer {
            Text("\(shiftLabel) \(ShiftClockFormat.clock(shiftSeconds))")
        }
    }

    private var ticketColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ticketCaption)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Text(ticketLine)
                .font(Typography.time(.callout))
                .foregroundStyle(ticketColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityShowsLargeContentViewer {
            Text("\(ticketCaption) \(ticketLine)")
        }
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
        case .onBreak: "No ticket was running"
        }
    }

    private var ticketLine: String {
        switch state {
        case let .timing(_, _, seconds): ShiftClockFormat.clock(seconds)
        case .onShift: "Pick a ticket"
        case let .onBreak(_, _, seconds?): ShiftClockFormat.clock(seconds)
        case .onBreak: "Shift paused"
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
