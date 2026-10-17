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
- [ ] Shift states: idle → working → on break → working → ended, each with its single primary action.
- [ ] Live shift timer, and the "counts as a meal break in N min" note.
- [ ] Plan and wrap-up sheets when the team requires them, including handling the `plan-required` error.
- [ ] Today's ticket timer and today's work list.
- [ ] Optimistic updates, a refetch after each action, and haptics.
- [ ] **You:** start the day, take a break, resume, end the day, and confirm it all in the web app.

### Step 6: Tickets and timers
- [ ] Edge-to-edge list, filter and sort pills, the search screen, swipe actions.
- [ ] Start and stop timers (`timers.createEntry` / `startSession` / `stopSession`), offering "Start day & timer" when you're clocked out.
- [ ] New-ticket sheet.
- [ ] **You:** run a timer, switch tickets, and confirm only one runs at a time.

### Step 7: Timesheet
- [ ] Week total and daily bars (`timers.getWeek`).
- [ ] Day detail (`clock.timesheet`).
- [ ] **You:** check the totals against the web app.

### Step 8: Huddle
- [ ] Feed (`huddle.getPosts`): edge-to-edge posts with plan and wrap-up badges, images, ticket chips.
- [ ] Rich composer: formatting, checklists, and @ people and tickets, converted to and from markdown, with round-trip tests.
- [ ] **You:** post from the app and see the post in the web app.

### Step 9: Inbox and Settings
- [ ] Notifications with an unread badge, swipe to mark read or delete, and Mark all read.
- [ ] 30 s polling while the screen is visible, plus a refresh whenever the app becomes active.
- [ ] Settings: profile, server, sign out, and diagnostics (recent requests and how long they took).

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
