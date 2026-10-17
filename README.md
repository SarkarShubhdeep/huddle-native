# Huddle Native

An experimental native iOS app for [TimeHuddle](https://github.com/mieweb/timehuddle), written in SwiftUI.

It talks to the **existing TimeHuddle Meteor backend, unchanged**: your local dev stack on the same Wi‑Fi, or the dev/prod servers. It has its own design and user flow, and doesn't reuse anything from the Capacitor app or `@mieweb/ui`.

- Design review (screens, tokens, decisions): see [`docs/DESIGN.md`](docs/DESIGN.md)
- Plan and guidelines every change follows: see [`docs/PLAN.md`](docs/PLAN.md)
- Step-by-step progress: see [`docs/PROGRESS.md`](docs/PROGRESS.md)

## Requirements

- macOS with **Xcode 26** or later
- An iPhone on **iOS 26** or later, or the iOS 26 simulator
- [Homebrew](https://brew.sh) for XcodeGen: `brew install xcodegen`
- An Apple Developer account, to run on a device (a free account works)

## Getting started

```sh
git clone https://github.com/SarkarShubhdeep/huddle-native.git
cd huddle-native
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then edit it, see below
xcodegen                                                 # generates HuddleNative.xcodeproj
open HuddleNative.xcodeproj
```

In `Config/Local.xcconfig` set:

| Setting | What to put |
|---|---|
| `DEVELOPMENT_TEAM` | Your team ID (Xcode › Settings › Accounts). |
| `HN_DEFAULT_SERVER_URL` | Your Mac's Wi‑Fi address and the backend port. Get the address with `ipconfig getifaddr en0`. Keep the `http:/$()/` spelling, because `//` starts a comment in xcconfig files. |
| `HN_BUNDLE_ID` *(optional)* | Your own reverse-DNS id, if your team can't register `com.sarkarshubhdeep.huddlenative`. |

Pick the **HuddleNative** scheme and run it.

Re-run `xcodegen` whenever `project.yml` changes or you add or remove files. The `.xcodeproj` is generated and not committed.

## Running against your local TimeHuddle stack

1. In your `timehuddle` checkout, start MongoDB (it holds your local test users), then the Meteor backend pointed at it:
   ```sh
   docker compose up -d mongodb
   cd meteor-backend
   set -a; . ./.env.local; set +a
   MONGO_URL='mongodb://127.0.0.1:27017/timehuddle?directConnection=true' pm2 start npm --name timehuddle-meteor -- start
   ```
   It listens on port **3100**.
   - Without `MONGO_URL`, Meteor uses its own empty database, and no test account can sign in.
   - Without `.env.local` (it sets `REDMINE_ENCRYPTION_KEY`), the timer methods fail and the Now screen can't load.
2. Put your iPhone on the same Wi‑Fi as the Mac.
3. Launch Huddle and enter the Mac's address, e.g. `192.168.1.24`. The port defaults to 3100.
4. When iOS asks to find devices on your local network, tap **Allow**.

### If the app can't reach your Mac
- **You declined the local network prompt.** Turn it on in Settings › Privacy & Security › Local Network › Huddle.
- **The Mac's IP changed** (a new DHCP lease). Check it again with `ipconfig getifaddr en0`.
- **The macOS firewall is blocking Node.** Allow incoming connections for `node` in System Settings › Network › Firewall.
- **Check from another device.** Open `http://<ip>:3100/` in the phone's Safari. It should answer `{"service":"timehuddle-meteor-backend","status":"ok"}`.

## Project layout

```
project.yml              XcodeGen spec (targets, Info.plist keys, entitlements)
Config/                  Shared and per-developer build settings
App/                     The SwiftUI app
Widgets/                 Widget, Control Center and Live Activity extension
Packages/HuddleKit/      Networking, models, services, refresh engine (no UI)
docs/                    Design notes and the step-by-step progress checklist
```

## Tests

HuddleKit is a plain Swift package with no UI, so its tests run anywhere Swift 6 does:

```sh
cd Packages/HuddleKit && swift test
```

In Xcode, ⌘U runs the same tests through the HuddleNative scheme.

## Ground rules

- **No backend changes.** Everything uses the REST API the backend already exposes (`POST /api/<method>`). The only exception is sign-in, which does a one-shot WebSocket login because that's the only password login the server has.
- **No code or assets from the Capacitor app or `@mieweb/ui`.**
- **Pull-to-refresh can't hang.** Every request has a timeout, and the spinner always stops within 6 seconds.
