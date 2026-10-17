import AppIntents

/// Phrases Siri and Spotlight offer without any setup.
struct HuddleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDayIntent(), phrases: ["Start my day in \(.applicationName)", "Clock in with \(.applicationName)"],
                    shortTitle: "Start Day", systemImageName: "sun.max")
        AppShortcut(intent: TakeBreakIntent(), phrases: ["Take a break in \(.applicationName)"],
                    shortTitle: "Take a Break", systemImageName: "cup.and.saucer")
        AppShortcut(intent: BackToWorkIntent(), phrases: ["Back to work in \(.applicationName)", "End my break in \(.applicationName)"],
                    shortTitle: "Back to Work", systemImageName: "play")
        AppShortcut(intent: EndDayIntent(), phrases: ["End my day in \(.applicationName)", "Clock out with \(.applicationName)"],
                    shortTitle: "End Day", systemImageName: "moon")
        AppShortcut(intent: StartTicketTimerIntent(), phrases: ["Start a ticket timer in \(.applicationName)"],
                    shortTitle: "Start Ticket Timer", systemImageName: "timer")
    }
}
