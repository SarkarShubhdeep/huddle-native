#if DEBUG
import HuddleKit
import SwiftUI

/// Debug-only app shell that shows every design-system component inside the
/// real dock, so it can be screenshotted in the Simulator and compared with
/// the design canvas. Replaced as the app's root by the first-run flow in Step 4.
///
/// Launch arguments (all optional):
/// - `-tab now|tickets|huddle|time|inbox`
/// - `-demo off|timing|shift|break|ended` sets the shift state and timer strip
/// - `-showcase tokens|buttons|chips|rows|pills|hero|posts|week|composer|states` opens one showcase (Inbox tab)
struct ComponentGallery: View {
    enum Demo: String, CaseIterable, Identifiable {
        case off, timing, shift, `break`, ended
        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off the clock"
            case .timing: "Timing a ticket"
            case .shift: "On shift, no ticket"
            case .break: "On break"
            case .ended: "Day done"
            }
        }

        var phase: ShiftPhase {
            switch self {
            case .off: .idle
            case .timing, .shift: .working
            case .break: .onBreak
            case .ended: .ended
            }
        }
    }

    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "")
        ?? (UserDefaults.standard.string(forKey: "showcase") != nil ? .inbox : .now)
    @State private var demo = Demo(rawValue: UserDefaults.standard.string(forKey: "demo") ?? "") ?? .timing
    @State private var launched = Date.now

    var body: some View {
        TimelineView(.periodic(from: launched, by: 1)) { context in
            let tick = Int(context.date.timeIntervalSince(launched))
            AppDock(selection: $tab, strip: strip(tick: tick), inboxBadge: 3, onStripAction: advanceDemo) { tab in
                NavigationStack {
                    page(for: tab, tick: tick)
                        .navigationTitle(tab.title)
                        .toolbar { demoMenu }
                }
            }
        }
    }

    // MARK: Pages

    @ViewBuilder private func page(for tab: AppTab, tick: Int) -> some View {
        switch tab {
        case .now: NowGalleryPage(demo: demo, tick: tick, onAction: advanceDemo)
        case .tickets: TicketsGalleryPage()
        case .huddle: PostRowPreview()
        case .time: WeekBarsPreview()
        case .inbox: ShowcaseList()
        }
    }

    private var demoMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Demo state", systemImage: "slider.horizontal.3") {
                Picker("Demo state", selection: $demo) {
                    ForEach(Demo.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    // MARK: Demo state

    private func strip(tick: Int) -> TimerStripState? {
        switch demo {
        case .off, .ended: nil
        case .timing: .timing(shiftSeconds: 13338 + tick, ticketTitle: "Fix login redirect on iPad", ticketSeconds: 2530 + tick)
        case .shift: .onShift(shiftSeconds: 13338 + tick)
        case .break: .onBreak(breakSeconds: 760 + tick, pausedTicketTitle: "Fix login redirect", ticketSeconds: 2530)
        }
    }

    private func advanceDemo() {
        demo = switch demo {
        case .off: .timing
        case .timing: .break
        case .shift: .timing
        case .break: .timing
        case .ended: .off
        }
    }
}

private struct NowGalleryPage: View {
    let demo: ComponentGallery.Demo
    let tick: Int
    let onAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                hero
                if demo == .timing {
                    TicketTimerCard(title: "Fix login redirect on iPad", time: ShiftClockFormat.clock(2530 + tick), onToggle: onAction)
                } else if demo == .break {
                    TicketTimerCard(title: "Fix login redirect on iPad", time: ShiftClockFormat.clock(2530), isPaused: true)
                }
                SectionHeader(title: "Today", detail: "3 tickets · 3h 12m")
                    .padding(.top, Spacing.xs)
                EdgeToEdgeList {
                    WorkRow(title: "Fix login redirect on iPad", duration: "0:42", isActive: demo == .timing)
                    WorkRow(title: "Review onboarding copy", duration: "1:15")
                    WorkRow(title: "Standup notes", duration: "1:15")
                }
                .padding(.horizontal, -Spacing.margin)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Palette.canvas)
    }

    @ViewBuilder private var hero: some View {
        let sample = NowHero.sample(demo.phase)
        switch demo {
        case .timing, .shift:
            NowHero(phase: .working, time: ShiftClockFormat.clock(13338 + tick),
                    timeAccessibilityLabel: ShiftClockFormat.spoken(13338 + tick), subtitle: sample.subtitle,
                    facts: sample.facts, primaryTitle: sample.primaryTitle, primaryAction: onAction, onEndDay: {})
        case .break:
            NowHero(phase: .onBreak, time: ShiftClockFormat.clock(760 + tick),
                    timeAccessibilityLabel: ShiftClockFormat.spoken(760 + tick), subtitle: sample.subtitle,
                    facts: sample.facts, primaryTitle: sample.primaryTitle, primaryAction: onAction)
        case .off, .ended:
            sample
        }
    }
}

private struct TicketsGalleryPage: View {
    var body: some View {
        List {
            PillsPreview.Bar()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.canvas)
            Group {
                TicketRow(title: "Fix login redirect on iPad", status: .inProgress, priority: "High",
                          assigneeInitials: ["SD"], timeText: "Now 0:42:10 · today 2:58", isRunning: true)
                    .listRowBackground(Palette.limeSoft)
                TicketRow(title: "Review onboarding copy", status: .open, priority: "Medium",
                          assigneeInitials: ["SD"], timeText: "Today 1:15")
                TicketRow(title: "Timesheet export shows UTC instead of the team time zone", status: .blocked,
                          priority: "High", assigneeInitials: ["SD", "AK"], timeText: "No time yet")
                TicketRow(title: "Huddle images load slowly", status: .open, priority: "Low", assigneeInitials: ["SD"], timeText: "Mon 0:35")
                TicketRow(title: "Rename team settings labels", status: .reviewed, priority: "Low", timeText: "Tue 1:05")
                TicketRow(title: "Release notes for 1.0.8", status: .closed, priority: "No priority", timeText: "Wed 0:50")
                // Enough rows to scroll, so the tab bar minimizes and the strip goes inline.
                ForEach(1..<9) { index in
                    TicketRow(title: "Sample ticket \(index)", status: .open, priority: "Low", timeText: "No time yet")
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.canvas)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 42 }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
    }
}

private struct ShowcaseList: View {
    enum Showcase: String, CaseIterable, Identifiable {
        case tokens, buttons, chips, rows, pills, hero, posts, week, composer, states

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tokens: "Tokens"
            case .buttons: "Buttons"
            case .chips: "Status chips"
            case .rows: "Edge-to-edge rows"
            case .pills: "Filter and sort pills"
            case .hero: "Now hero, all states"
            case .posts: "Post rows"
            case .week: "Week bars"
            case .composer: "Composer toolbar"
            case .states: "Banner and states"
            }
        }

        @MainActor @ViewBuilder var view: some View {
            switch self {
            case .tokens: ScrollView { TokenSwatches() }.background(Palette.canvas)
            case .buttons: ButtonsPreview()
            case .chips: StatusChipPreview()
            case .rows: RowsPreview()
            case .pills: PillsPreview()
            case .hero: NowHeroPreview()
            case .posts: PostRowPreview()
            case .week: WeekBarsPreview()
            case .composer: ComposerToolbarPreview()
            case .states: StatesPreview()
            }
        }
    }

    @State private var path: [Showcase] = UserDefaults.standard.string(forKey: "showcase")
        .flatMap(Showcase.init(rawValue:)).map { [$0] } ?? []

    var body: some View {
        List(Showcase.allCases) { showcase in
            Button(showcase.title) { path = [showcase] }
                .foregroundStyle(Palette.textPrimary)
        }
        .listStyle(.plain)
        .navigationDestination(isPresented: Binding(get: { !path.isEmpty }, set: { if !$0 { path = [] } })) {
            if let showcase = path.first {
                showcase.view
                    .navigationTitle(showcase.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

#Preview("Light") { ComponentGallery() }
#Preview("Dark") { ComponentGallery().preferredColorScheme(.dark) }
#endif
