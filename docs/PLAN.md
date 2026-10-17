# Huddle Native: plan and guidelines

This is the working plan and the guidelines every step follows. Two other files go with it:
- `docs/DESIGN.md`, the locked design spec
- `docs/PROGRESS.md`, the live checklist

## Context
Huddle Native is an experimental native iOS app in SwiftUI. It talks to the **existing, unchanged** TimeHuddle Meteor backend: the local stack at `http://<mac-LAN-IP>:3100`, or the dev/prod hosts. It has three goals:
1. A modern, Apple-style app with its own identity.
2. A better UX than the Capacitor app.
3. Refresh that never hangs.

## Current status (2026-10-17)
- **Step 0 (design review): done.**
  - Canvas: https://claude.ai/artifact/XsNMGQQixyBTaAJfwoE3UF (20 boards).
  - Locked: Graphite + Lime accent, the ring icon, option A on all 12 UX cards.
  - The review comments that shaped the design:
    - no progress rings or bars
    - lists edge to edge
    - a glass dock with the timer strip
    - search behind an icon
    - GitHub-style filter and sort pills
    - a rich composer with @ people and tickets
    - Liquid Glass on controls only
- **Step 1 (repo skeleton): built and committed**, 18 files.
  - HuddleKit tests: 7 of 7 pass on Swift 6.2 (Linux).
  - **Not pushed yet.** `SarkarShubhdeep/huddle-native` doesn't exist on GitHub, or this session can't reach it. This session also can't create repos.
- **Blocking on you:**
  1. Create the empty public repo `SarkarShubhdeep/huddle-native` at https://github.com/new, with no README or license.
  2. If pushing still fails, give the Claude GitHub App access to it at https://claude.ai/connect-github, or start a new session with the repo selected.
  3. Run `xcodegen` on your Mac and confirm the app builds on a device.

## Guidelines (apply to every step)

**Hard rules**
- `mieweb/timehuddle` is never modified. It's a read-only reference for the API.
- No backend changes of any kind: no new endpoints, config or migrations.
- No `@mieweb/ui`, no MIE branding or colors, no code or assets copied from the Capacitor app.

**Talking to the backend**
- Data goes over REST only: `POST /api/<method_with_underscores>` with `Authorization: Bearer <token>`. Responses are `{result}` on success, `{error, reason}` on failure.
- The one exception is sign-in. It's a one-shot DDP WebSocket `login{emailPassword}`: connect, login, close, capped at 10 s. Nothing stays connected.
- The resume token goes in the Keychain. It lasts 30 days.
- Backend rules the app must respect:
  - A ticket timer needs an active shift, and only one timer runs at a time.
  - Pause, resume and stop also stop or restart the running timer.
  - `plan-required` can block clock-out.
  - A break of 20 minutes or more is an unpaid meal break.
  - Clock actions use the active shift's `teamId`.

**Refresh, which must never hang**
- Every request has a timeout: 10 s per request, 20 s per resource. No waiting for connectivity.
- Reads retry once on transient errors such as `-1005` or a timeout. Writes never retry.
- `Resource<T>`:
  - stale data stays on screen
  - single-flight: a second pull joins the first
  - the fetch runs in its own Task, so SwiftUI cancellation can't kill it
  - the spinner stops within 6 s, and late data still lands
  - errors show as a non-blocking banner
- Live data without DDP: refresh when the app becomes active, poll every 30 s on the visible screen, refetch after every action, with optimistic updates.

**Design** (full spec in `docs/DESIGN.md`)
- Native iOS 26 components first.
- Liquid Glass only on the controls layer: the dock, floating top buttons, menus and popovers, the composer toolbar. Content stays solid.
- One accent per screen marks the primary action.
- No progress rings or bars: the time is the hero, in SF Rounded with tabular digits.
- Lists edge to edge with hairlines, no boxed sections.
- Accessibility is part of "done": Dynamic Type, VoiceOver labels, Reduce Motion and Reduce Transparency.

**Stack**
- iOS 26 minimum, Swift 6 with strict concurrency, SwiftUI with `@Observable`.
- XcodeGen `project.yml`. The `.xcodeproj` is never committed.
- `HuddleKit` local package for everything that isn't UI: no third-party dependencies, builds on macOS and Linux.
- SwiftData for the cache, Swift Testing for tests.
- App Intents, ActivityKit and WidgetKit for system integration.

**Working agreement**
- One step per commit (or a few small commits), on `main`.
- Every commit updates `docs/PROGRESS.md`. The plan changes only when a decision changes.
- HuddleKit changes come with tests, and `swift test` must pass before a commit.
- I can't run Xcode here. After each UI step you build on device and send me errors. I fix them before starting the next step.
- Design changes go on the canvas first, then into `DESIGN.md`, then into code.
- Commits end with the Claude co-author and session trailers.

## Steps
(Step-by-step detail and checkboxes live in `docs/PROGRESS.md`.)

0. ✅ **Design review.**
1. 🟡 **Repo skeleton.** Built locally. Waiting on the GitHub repo and your first Xcode build.
2. **HuddleKit core:**
   - APIClient
   - MeteorLogin
   - Keychain / SessionStore
   - models (with media-URL re-basing)
   - services
   - `Resource<T>`
   - shift-time calculator
   - tests
3. **Design system in code:**
   - tokens
   - glass dock with timer strip
   - Now hero
   - edge-to-edge rows
   - pills
   - composer toolbar
   - banners and states
   - `#Preview`s
4. **First run:** server picker plus connection test, sign-in, team restore and switcher.
5. **Now screen:** shift states, meal-break note, plan and wrap-up sheets, today's work.
6. **Tickets and timers:** filter and sort pills, search screen, start/stop timers, "Start day & timer", new ticket.
7. **Timesheet:** week total with daily bars, day detail.
8. **Huddle:** feed, plus the rich composer (formatting, checklists, @ people and tickets, markdown round-trip).
9. **Inbox and Settings:** polling, badge, swipe actions, diagnostics.
10. **System integration:** App Intents, Control Center, Live Activity and Dynamic Island, widgets.
11. **Hardening:** refresh torture test, accessibility pass, docs.

**Not in v1:**
- Remote push (needs the backend's `APNS_BUNDLE_ID`)
- Attachment and Pulse uploads
- Likes and comments
- Redmine
- OAuth, PAT and dev login
- Admin, org and enterprise screens
- Server-side logout

## Verification
- `cd Packages/HuddleKit && swift test` passes, both here and on your Mac.
- On your Mac:
  - `xcodegen`, then build and run the HuddleNative scheme on an iOS 26 device.
  - The placeholder screen shows your `HN_DEFAULT_SERVER_URL`.
  - The widget appears in the gallery.
- From Step 4 on, manual checks against the local backend, listed per step in `docs/PROGRESS.md`.
