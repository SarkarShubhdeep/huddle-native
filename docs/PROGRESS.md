# Progress

Each step ends at a checkpoint. **You** = the developer's action on a Mac or device; everything else happens in the repo. Every step is its own commit.

### Step 0: Design review ✅
- [x] Build the design review canvas: tokens, 3 accent options, icon concepts, every screen in light and dark, Live Activity, Control Center and widget mocks.
- [x] Add the UX decision list, comparing each current Capacitor flow with the proposed one.
- [x] Revise from review comments: no progress rings; edge-to-edge lists; a timer strip merged into the dock; search behind an icon; filter and sort pills; a rich composer with @ mentions; Liquid Glass on controls only.
- [x] Lock the decisions (see [DESIGN.md](DESIGN.md)).

### Step 1: Repo skeleton ✅
- [x] **You:** create the empty GitHub repo `SarkarShubhdeep/huddle-native`.
- [x] `project.yml` with three targets: the app, the widget/Live Activity extension, and the local `HuddleKit` package. iOS 26, Swift 6, strict concurrency.
- [x] Info.plist keys: `NSLocalNetworkUsageDescription`, `NSAllowsLocalNetworking`, Live Activities. Plus the App Group and bundle id.
- [x] `Config/Base.xcconfig`, plus a gitignored `Local.xcconfig` for the signing team and LAN address.
- [x] README: prerequisites, `xcodegen`, running against the local backend, troubleshooting the local network prompt.
- [x] App icon from the approved concept (lime ring on graphite, plus dark and tinted variants).
- [x] `.gitignore`, `docs/DESIGN.md`, `docs/PLAN.md` (plan and guidelines), this file.
- [x] HuddleKit's first unit, `ServerEndpoint`, with Swift Testing tests.
- [x] Push to https://github.com/SarkarShubhdeep/huddle-native.
- [x] **You:** run `brew install xcodegen && xcodegen`, open the project in Xcode, and confirm the empty app builds and runs. Confirmed in the iOS 26.5 Simulator (iPhone 17 Pro).

### Step 2: HuddleKit core ✅
- [x] `APIClient` (a `Sendable` struct over an injectable `HTTPTransport`):
  - [x] timeouts
  - [x] `query` vs `mutate`
  - [x] a single retry on transient errors
  - [x] envelope decoding
  - [x] `APIError`
- [x] `MeteorLogin`: a one-shot WebSocket connect → login → close, capped at 10 s, sending the SHA-256 digest plus `raw`.
- [x] `Keychain` + `SessionStore`: save, restore, and sign out on `unauthorized`.
- [x] Models:
  - [x] Team
  - [x] ClockEvent and Break
  - [x] Ticket
  - [x] WorkItem and TimerSession
  - [x] HuddlePost and Attachment
  - [x] Notification
  - [x] PublicUser
  - [x] Timesheet
  - [x] media-URL re-basing
- [x] Services: Clock (with timesheet), Timers, Tickets, Huddle, Notifications, Users, Teams.
- [x] `Resource<T>` refresh engine:
  - [x] single-flight
  - [x] a detached fetch
  - [x] the 6 s cap
  - [x] keeps stale data
  - [x] snapshot cache (JSON files in Caches; portable, so it runs in tests)
- [x] Shift-time calculator (`ShiftClock`) that mirrors the web app's `getActiveClockSeconds`, plus the meal-break countdown.
- [x] Swift Testing tests:
  - [x] envelope and null handling
  - [x] error mapping
  - [x] media re-basing
  - [x] Resource single-flight and the 6 s cap
  - [x] shift-time math, including the 20-minute meal rule
- [x] `swift test`: 72 tests pass on Swift 6.2 (Linux), with no warnings under strict concurrency.
- [x] **You:** run `swift test` in `Packages/HuddleKit` on your Mac (or ⌘U in Xcode). Confirmed: passes in Terminal and in Xcode.

### Step 3: Design system in code
- [x] Tokens from DESIGN.md: color sets in light and dark, type, spacing, radius, motion.
  - 17 color sets under `Assets.xcassets/Palette`, reached through `Palette`. The canvas's soft tints (lime, done), raised surface, fill and bar colors are included.
  - `Typography` (system text styles, SF Rounded tabular times, `HeroTimeText`), `Spacing`, `Radius`, `Motion` (the spring, off under Reduce Motion), and `controlGlass` (solid under Reduce Transparency).
  - A debug-only `ComponentGallery` is the app's root for now, so every component can be screenshotted in the Simulator.
- [x] Button styles, the status chip, the empty, error and offline states, and the refresh banner.
  - `HNButtonStyle` (primary lime capsule, secondary, destructive text, quiet lime text; large, regular and small) and `HNIconButtonStyle` (play/pause, new), all with 44 pt touch targets.
  - `StatusChip` with a `Tone` (neutral, working, on break, done), also used for the Plan and Wrap-up badges.
  - Edge-to-edge rows: `Hairline`, `EdgeToEdgeList`, `TicketRow` (status dot, wrapping facts line via `FlowLayout`, lime tint while timing), `WorkRow`, `TimeRow`, `Avatar`.
  - `RefreshBanner` and `StatusView` (empty, unreachable, offline).
- [x] Signature components:
  - [x] the glass dock with the timer strip
    - `AppDock` is one custom Liquid Glass shape, as on the canvas: `TimerStrip` on top (timing, on shift, on break; hidden off the clock), a hairline, then the five tabs with a lime selection pill and an Inbox badge.
    - Tabs still live in a `TabView` with the system tab bar hidden, so each tab keeps its own navigation and scroll state. The dock sits in the bottom safe area and content scrolls under it. It doesn't minimize on scroll.
    - Solid under Reduce Transparency; the strip stops growing at xLarge text and offers the large content viewer, like system bars.
    - Nothing hides behind it: the dock's measured height becomes a bottom content margin for every scroll view and List in every tab, pushed screens included, and follows the strip as it shows or hides. Non-scrolling screens use `.clearsDock()`. (A safe-area inset on the `TabView` doesn't reach Lists inside the tabs' navigation stacks.)
  - [x] filter and sort pills: `FilterPill` (native glass menu), `MultiSelectPill` (stays open while you tick), `SortPill` (field, then direction), `FilterCountPill`, `PillBar`
  - [x] the Now hero: `NowHero` in all four states (tiles fall back to a list at large text sizes) and `TicketTimerCard`
  - [x] the ticket row
  - [x] the post row: `PostRow` (avatar, Plan and Wrap-up badges, inline markdown, ticket chip, image, counts)
  - [x] the week bars: `WeekBars` (week total; tap a day; bars scale to at least a 9-hour day; each bar is a VoiceOver button)
  - [x] the rich composer toolbar: `ComposerToolbar` on control glass (bold, italic, strikethrough, bullets, numbers, checklist, @). The editor itself is Step 8.
  - [x] `SectionHeader`, which moves its detail under the title at accessibility text sizes
- [x] A `#Preview` for each, in light and dark.
- [x] Simulator check (iPhone 17 Pro, iOS 26.5) against the canvas boards: every gallery tab in light and dark, tab switching, the largest accessibility text size, and Reduce Transparency.
  - Run the gallery with `-tab now|tickets|huddle|time|inbox`, `-demo off|timing|shift|break|ended` and `-showcase <id>`.
  - Light-mode controls on the canvas background use the gray `Fill` token, because the raised-surface color is the same as the canvas.
- [ ] **You:** compare the previews with the design canvas.

### Step 4: First run (server and sign-in)
- [x] Server picker: This Wi‑Fi, Development, Production, Custom URL.
  - Development and Production come from `HN_DEV_SERVER_URL` / `HN_PROD_SERVER_URL` in `Local.xcconfig`, and stay hidden until set. Not set yet.
  - Edge-to-edge rows, as DESIGN.md requires; the canvas board draws them in a box.
- [x] "Test connection" via `GET /`, which also triggers the local network prompt. `ServerProbe` (HuddleKit, tested): runs as you type and before Continue, capped at 5 s, and reports reachable with latency, not a TimeHuddle server, or unreachable.
- [x] Email and password sign-in with inline errors: wrong password, suspended account, reset required. The messages come from `LoginError`. There's no "Forgot password?" link, because the app has no reset flow in v1.
- [x] Restore the last-used team, and the team switcher in the nav title. `TeamChoice` (HuddleKit, tested): the saved team, else the first shared team, else the personal one. Teams are cached per user and refresh when the app becomes active. The avatar menu has Sign out, until Settings in Step 9.
- [x] Checked in the Simulator against the local backend, signed in as a test user. The connection test answers in about 55 ms. Sign-in lands on the saved team, switching teams works, and both the session and the team survive a relaunch.
- [ ] **You:** sign in against your local backend from a device.

### Step 5: Now screen
- [x] Shift states: idle → working → on break → working → ended, each with its single primary action.
  - Off the clock: Start day. Working: Take a break, with a quieter End day. On break: Back to work. Day done: See timesheet, with a quiet "Start another shift".
  - Clock actions use the active shift's team; starting uses the selected team.
- [x] Live shift timer, and the "counts as a meal break in N min" note. Both tick on the device (`ShiftClock`), and the dock's timer strip ticks on every tab.
- [x] Plan and wrap-up sheets when the team requires them, including handling the `plan-required` error.
  - Plan sheet: posts the plan (`huddle.createPost`), then clocks in with its id, which links it to the shift.
  - Wrap-up sheet, offered on every End day: shows the day's time and work, with a note pre-filled from today's tickets.
    - It keeps the plan and adds "**Wrap-up:**" under it, because `huddle.updatePost` replaces the whole text.
    - With no plan, it creates a wrap-up post linked to the shift, as the web app does.
    - "End day without posting" is hidden when the team requires a wrap-up. `plan-required` shows as a plain message.
  - Checked on the local Development team, which requires plans. The plan was posted and linked to the new shift. At End day the sheet found the plan and hid "End day without posting". The wrap-up went under the plan in the same post, stamped, and the server accepted the clock-out.
  - The plan and wrap-up text are plain text until the rich composer in Step 8.
- [x] Today's ticket timer and today's work list: the running ticket with Pause, the ticket a break paused, and today's work items with their times.
- [x] Optimistic updates, a refetch after each action, and haptics.
  - Each action shows the shift the server returns right away.
  - `Resource.refetch()` (HuddleKit, tested) then confirms. It drops the result of a poll that was already in flight, which would otherwise bring back the pre-write state.
  - Data refreshes when the app becomes active and every 30 s while it's in front. Success and error haptics.
- [x] Checked in the Simulator against the local backend: start day, take a break, back to work, end day with a wrap-up. The server state matched each step (breaks closed, wrap-up linked and stamped, no open shift).
  - "Day done" covers the whole day: every shift since midnight, with their total and the span.
  - When the backend crashed mid-test, the screen kept its data and showed the refresh banner, as designed.
- [ ] **You:** start the day, take a break, resume, end the day, and confirm it all in the web app.

### Step 6: Tickets and timers
- [x] Edge-to-edge list, filter and sort pills, the search screen, swipe actions.
  - Pills: a filter count (with "Clear filters"), Status ("Open" by default, meaning anything not done), Assignee (me, anyone, or a teammate), Priority (multi-select), and Sort (field and direction).
  - Filtering and sorting run on the device through `TicketQuery` (HuddleKit, tested), and the choice is remembered.
  - Rows show status, priority, assignees and today's time; the running row is tinted and ticks.
  - Swipe right to start or pause the timer; swipe left for Done or In progress.
  - Search is its own screen with the native search field. Scopes: this team, all your teams (loaded when picked), and assigned to me. Matches are bold, and the last five searches are kept.
  - The avatar now sits only on Now, as on the canvas; Tickets uses that space for Search and New.
- [x] Start and stop timers (`timers.createEntry` / `startSession` / `stopSession`), offering "Start day & timer" when you're clocked out.
  - Play on any row starts that ticket. The server stops whatever was running, so only one runs.
  - Off the clock, a sheet offers "Start day & timer". When the team requires a plan, the plan sheet opens instead with "Working on <ticket>." filled in, then posts the plan, clocks in and starts the timer.
- [x] New-ticket sheet: title, details, priority, assignees (team members), GitHub link (https only), and "Start timer now" (on shift only). The ticket shows at once, then a refetch confirms it.
- [x] Checked in the Simulator against the local backend:
  - Off the clock: "Start day & timer" → plan sheet → one shift and one running timer on that ticket.
  - Switching tickets leaves exactly one timer running.
  - A new ticket was created (High, assigned to me) with its timer started.
  - Pausing from the row stopped the timer.
  - Search with highlights and scopes.
  - Swipe actions and every filter menu checked against the server.
    - In progress, Done and Reopen change the status, and swipe start/pause run the timer.
    - Status, assignee, multi-priority and sort filter live. The count pill and empty-state "Clear filters" reset them.
    - Fixes from that pass:
      - A new sort field starts in its natural direction (Title A to Z, the others newest/highest first).
      - The summary keeps "A to Z" capitalized.
      - The menus' dividers render.
      - The default "Open" filter has a subtitle ("Everything not done") in its menu, so it's distinct from the Open status below it.
      - In progress swipes gray, Done green.
      - Done tickets get Reopen.
- [ ] **You:** run a timer, switch tickets, and confirm only one runs at a time.

### Step 7: Timesheet
- [x] Week total and daily bars (`timers.getWeek`).
  - The bars count ticket-timer time per day, like the web app's Work page. Bars scale to at least a 9-hour day, and today is selected.
  - Week menu (this week, last week, four more), previous/next buttons (not past this week), cached per week, refetched after any clock or timer action.
  - The Time tab spans all teams, so its bar holds the week instead of the team switcher.
- [x] Day detail (`clock.timesheet`, one call per week): each shift that started that day, then its ticket timers and breaks, newest first.
  - Running items count up to now. Breaks read "Rest break · paid" or "Meal break · unpaid" (20-minute rule when the server gives no type), and a shift past midnight names the day it ended.
  - Built by `DayTimeline` (HuddleKit, 3 tests).
  - The canvas's "Request a change" link isn't built: timesheet change requests aren't in v1.
- [x] Checked against the local backend: this week's 2h 05m equals the closed timer seconds in the database plus the running timer; previous-week navigation; dark mode.
- [ ] **You:** check the totals against the web app.

### Step 8: Huddle
- [x] Feed (`huddle.getPosts`): edge-to-edge posts with plan and wrap-up badges, images, ticket chips.
  - Team / Mine, pull to refresh, a 30 s refresh while the tab is open, and a cache per team.
  - Post bodies render paragraphs, bullets, numbers and checklists (done items struck through), bold/italic/strike, @mentions and links in lime. Images written into the text and image attachments show, re-based onto the current server.
  - The canvas's like and comment counts show; likes and comments themselves are not in v1.
- [x] Rich composer: formatting, checklists, and @ people and tickets, converted to and from markdown, with round-trip tests.
  - `RichDocument` and `RichMarkdown` (HuddleKit, 11 tests) cover:
    - GitHub markdown: `**`, `*`, `~~`, `- `, `1. `, `- [ ]` / `- [x]`
    - escaping, links (the backend's activity posts use them), and dropping trailing spaces
    - `@Firstname` mention tokens, matched the way the web app matches them (shared first names stay plain)
  - The editor is a `UITextView` bridge:
    - The toolbar toggles styles on the selection or for what you type next.
    - Lists continue on Return and end on an empty item. Numbers renumber, and a tap on a checkbox ticks it.
    - `@` opens one popover of teammates and open tickets.
    - People go to `content.mentions`; the first ticket becomes `ticketId` and is written as its title.
  - New post, plan and wrap-up all use it. The plan opened from "Start day & timer" starts with the ticket as a mention, and the wrap-up starts from today's tickets.
- [x] Checked against the local backend: a post with bold text, a ticked and an open checklist item, a person mention and a ticket mention was saved as the expected markdown, with Rachel in `mentions` and the ticket as `ticketId`. The feed then showed it with the checklist, mention and ticket chip.
  - Fixed along the way:
    - an infinite loop in list paragraph styling
    - keystrokes dropped because typing attributes were reset on every key
    - list text inheriting the marker's gray
- [x] **You:** post from the app and see the post in the web app. Confirmed: a post from the app shows correctly in the web app's Huddle feed.

### Step 9: Inbox and Settings
- [x] Notifications with an unread badge, swipe to mark read or delete, and Mark all read.
  - The dock's Inbox tab shows the unread count. Rows say what kind each one is (clock, shift reminder, ticket, mention) and when, and unread ones have a lime dot.
  - Tap marks read and goes where it points: `NotificationRoute` (HuddleKit, tested) maps the web paths to Now, Tickets, Huddle (switching team if needed) or Time.
  - Swipe right to mark read, left to delete. The menu has Mark all read and Delete read. Each change shows at once, then a refetch confirms it.
- [x] 30 s polling while the screen is visible, plus a refresh whenever the app becomes active. The inbox polls with the shift on every tab, so the badge stays current.
- [x] Settings: profile, server, sign out, and diagnostics (recent requests and how long they took).
  - Opens from the avatar on Now: name and handle, team, server, session expiry, version, and Sign out (with a confirmation).
  - Diagnostics lists the last 50 requests: method, time, status or failure, and milliseconds. `LoggingTransport` and `RequestLog` (HuddleKit, tested) wrap every call. It also has a Test connection button.
  - Switching servers means signing out; there's no in-place server change.
- [x] Checked against the local backend:
  - The badge matched the database's unread count.
  - A tap marked one read (37 → 36) and opened Huddle.
  - Swipe-delete removed one (43 → 42).
  - Diagnostics listed each of those calls.

### Step 10: System integration
- [ ] App Intents: Start day, Take break, End day, Start ticket timer.
- [ ] Control Center controls and interactive widgets.
- [ ] Live Activity and Dynamic Island.
- [ ] Lock Screen and Home Screen widgets.
- [ ] **You:** clock in from Control Center and watch the Live Activity tick.

### Step 11: Hardening
- [ ] Refresh torture test: background the app for 5+ minutes, use airplane mode, kill the backend mid-refresh. On every tab the spinner must stop within 6 s and the old data must stay.
- [ ] VoiceOver, the largest Dynamic Type size, Reduce Motion, Reduce Transparency.
- [ ] Dock clearance: on every screen, scroll to the end with and without the timer strip and at the largest text size, and confirm nothing is hidden behind the dock.
- [ ] Update the docs and list the known gaps.
