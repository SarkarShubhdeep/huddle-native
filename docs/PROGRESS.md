# Progress

Each step ends at a checkpoint. **You** = the developer's action on a Mac or device; everything else happens in the repo. Every step is its own commit.

### Step 0: Design review ✅
- [x] Build the design review canvas: tokens, 3 accent options, icon concepts, every screen in light and dark, Live Activity, Control Center and widget mocks.
- [x] Add the UX decision list, comparing each current Capacitor flow with the proposed one.
- [x] Revise from review comments: no progress rings; edge-to-edge lists; a timer strip merged into the dock; search behind an icon; filter and sort pills; a rich composer with @ mentions; Liquid Glass on controls only.
- [x] Lock the decisions (see [DESIGN.md](DESIGN.md)).

### Step 1: Repo skeleton
- [x] **You:** create the empty GitHub repo `SarkarShubhdeep/huddle-native`.
- [x] `project.yml` with three targets: the app, the widget/Live Activity extension, and the local `HuddleKit` package. iOS 26, Swift 6, strict concurrency.
- [x] Info.plist keys: `NSLocalNetworkUsageDescription`, `NSAllowsLocalNetworking`, Live Activities. Plus the App Group and bundle id.
- [x] `Config/Base.xcconfig`, plus a gitignored `Local.xcconfig` for the signing team and LAN address.
- [x] README: prerequisites, `xcodegen`, running against the local backend, troubleshooting the local network prompt.
- [x] App icon from the approved concept (lime ring on graphite, plus dark and tinted variants).
- [x] `.gitignore`, `docs/DESIGN.md`, `docs/PLAN.md` (plan and guidelines), this file.
- [x] HuddleKit's first unit, `ServerEndpoint`, with Swift Testing tests.
- [x] Push to https://github.com/SarkarShubhdeep/huddle-native.
- [ ] **You:** run `brew install xcodegen && xcodegen`, open the project in Xcode, and confirm the empty app builds and runs on a device.

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
- [ ] **You:** run `swift test` in `Packages/HuddleKit` on your Mac (or ⌘U in Xcode).

### Step 3: Design system in code
- [ ] Tokens from DESIGN.md: color sets in light and dark, type, spacing, radius, motion.
- [ ] Button styles, the status chip, the empty, error and offline states, and the refresh banner.
- [ ] Signature components:
  - [ ] the glass dock with the timer strip
  - [ ] the Now hero
  - [ ] the ticket row
  - [ ] the post row
  - [ ] the week bars
  - [ ] the rich composer toolbar
- [ ] A `#Preview` for each, in light and dark.
- [ ] **You:** compare the previews with the design canvas.

### Step 4: First run (server and sign-in)
- [ ] Server picker: This Wi‑Fi, Development, Production, Custom URL.
- [ ] "Test connection" via `GET /`, which also triggers the local network prompt.
- [ ] Email and password sign-in with inline errors: wrong password, suspended account, reset required.
- [ ] Restore the last-used team, and the team switcher in the nav title.
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
- [ ] Update the docs and list the known gaps.
