# ReleaseNotes/

**One markdown file per build.** The whole folder ships inside the app and is shown in **Settings › What’s new**. The newest note also appears as a “Huddle got updated” banner on Now, once, the first time the app opens after an update.

These notes are for **testers** during pre-beta: what you can do now, and how to try it. If a change is invisible to the person using Huddle, it belongs in the commit or PR, not here.

## The rules

```
ReleaseNotes/
  README.md            ← you are here (never shown in the app)
  0.3.0.md             ← the note for version 0.3.0
  assets/
    0.3.0/             ← every picture or clip that 0.3.0.md uses
      now.jpg
      break.mp4
```

- **The filename is the version.** `0.3.0.md` is the note for `0.3.0`. Its `version:` must match the filename, or the app drops the note without saying so. Check Settings › What’s new after adding one.
- **Anything that isn’t `<version>.md` is ignored**, so this README never shows up.
- **A note only shows once the app reaches its version** (`MARKETING_VERSION` in `Config/Base.xcconfig`). You can write it ahead of a release.
- **Assets live in `assets/<version>/`**, one folder per release, so deleting an old note never breaks another’s pictures.

## Front matter

```markdown
---
version: 0.3.0
date: 2026-10-17
title: Your day on one screen
channel: pre-beta
---
```

`channel` is `pre-beta` for now and shows as a chip next to the version.

## Writing the body

- Plain markdown: paragraphs, `- ` bullets, `1. ` numbers, `- [ ]` checklists, `**bold**`, `*italic*`, links.
- `## Heading` and `### Smaller heading`.
- **A picture or clip goes on a line of its own:** `![What it shows](assets/0.3.0/now.jpg)`. The text in brackets is the caption, and VoiceOver reads it, so describe what the picture shows.
- **Clips, not GIFs.** A `.mp4` or `.mov` plays muted and loops. It starts paused under Reduce Motion, and a tap plays or pauses it. Keep clips short (under 10 s) and small (under 2 MB).
- **Screenshots** are JPEG, about 600 px wide, from the iPhone 17 Pro Simulator with the status bar set to 9:41:

  ```sh
  xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
  xcrun simctl io booted screenshot shot.png
  sips -Z 1200 -s format jpeg -s formatOptions 70 shot.png --out assets/0.3.0/now.jpg
  ```
