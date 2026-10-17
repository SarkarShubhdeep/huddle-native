# Design

The full design review lives on a canvas: <https://claude.ai/artifact/XsNMGQQixyBTaAJfwoE3UF> (private to the owner). This file records what was decided there, so the code has a written spec.

## Locked decisions (Step 0)

**Visual language**
- **Accent: Graphite + Lime.**
  - Fill `#C6F135` with `#111111` text on top.
  - Lime-colored text on light backgrounds uses `#4D7A0C`; on dark backgrounds `#C6F135`.
- **Icon:** the open ring. Lime on graphite, with dark and tinted variants.
- **Liquid Glass on the controls layer only:** the bottom dock, floating top buttons, menus and popovers, and the formatting toolbar.
  - Content (lists, posts, the Now hero, sheet backgrounds) stays solid.
  - The primary action is always a solid accent capsule.
  - With Reduce Transparency on, glass falls back to a solid material.
- **No rings or progress bars.** The time itself is the hero, set big in SF Rounded with tabular digits, with a few plain facts under it.
- **Lists run edge to edge** with hairline separators. No boxed or inset sections.

**Navigation and screens**
- **Navigation:** five tabs (Now · Tickets · Huddle · Time · Inbox) inside one glass dock.
  - While on the clock, the dock's top row is the timer strip: shift total, the ticket with its time, and one action. It has three states: timing a ticket, on shift with no ticket, and on break.
  - Profile and settings sit behind the avatar.
- **Tickets:**
  - Search sits behind an icon and opens its own screen.
  - GitHub-style dropdown pills for status, assignee, priority and sort.
  - The sort menu also sets the direction.
- **Composer** (plan, wrap-up, Huddle posts):
  - Rich text, never visible markdown: bold, italic, strikethrough, bullets, numbered lists and checklists.
  - `@` opens one popover that searches both people and tickets.
  - It's saved as the markdown the web app already renders.
  - People go into `content.mentions`, and the first ticket becomes the post's `ticketId`.

**Design tokens**

| Token | Light | Dark |
|---|---|---|
| Background | `#F2F2F7` | `#000000` |
| Elevated surface | `#FFFFFF` | `#1C1C1E` |
| Primary text | `#0B0B0F` | `#F5F5F7` |
| Secondary text | `#6C6C73` | `#A1A1A8` |
| Separator | `rgba(60,60,67,0.14)` | `rgba(84,84,88,0.55)` |
| Working | accent | accent |
| On break / meal | `#8F5300` on `#FFF1D9` | `#FFB340` on `#33240A` |
| Done | `#1F8A3A` | `#30D158` |
| Destructive | `#C4291D` | `#FF6961` |

- **Corner radius:** 12 for controls, 20 for cards, 28 for the hero and sheets, full for capsules.
- **Spacing:** a 4-pt grid, with 16-pt screen margins.
- **Motion:** a spring (0.35 s, bounce 0.15). Numbers animate with `contentTransition(.numericText())`.

## UX decisions

All 12 cards on the "Your calls" board resolve to **option A**, unless the canvas says otherwise:

| # | Topic | Decision |
|---|---|---|
| 1 | Home | A "Now" screen with one action that changes with your state. |
| 2 | Tabs | Five flat tabs. |
| 3 | Plan before clock-in | One sheet: posts the plan, clocks you in, starts the timer. |
| 4 | Timer while off the clock | A sheet asks whether to start the day and the timer together. |
| 5 | Outside the app | Live Activity, Control Center controls, widgets and App Intents, all in v1. |
| 6 | Teams | A team switcher in the nav title. Clock actions always target your active shift. |
| 7 | Breaks | A live note when a break will count as a meal (the 20-minute rule). |
| 8 | End of day | A wrap-up sheet, filled in for you, offered every time; you can skip it. |
| 9 | Fresh data | Refresh when the app opens, every 30 s on the visible screen, and on pull (capped at 6 s). |
| 10 | Accent | Graphite + Lime. |
| 11 | Timesheet | Keep the daily bars. |
| 12 | Push | Polling only in v1. |
