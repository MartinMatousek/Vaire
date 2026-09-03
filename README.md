# Vaire

*Čeština: [README.cs.md](README.cs.md)*

Automatic time tracker for macOS. Vaire derives worked time from Claude Code
session transcripts (`~/.claude/projects/*/*.jsonl`) and git commit history,
with manual entry and editing on top. Menu bar app + WidgetKit widget with a
daily progress ring.

## What it does

- **Tracks time automatically** from Claude Code sessions via
  `SessionStart`/`SessionEnd` hooks — no manual start/stop needed while
  you're coding with Claude Code.
- **Manual start/stop** per project from the menu bar, for work outside
  Claude Code.
- **Week view** with a resizable timeline, live/running blocks shown
  distinctly from finished ones, drag-and-drop between days, and inline
  editing of time, notes, and effort estimates.
- **Time-saved estimates** — records how long a task would have taken
  without AI, compared against actual logged time, to see the added value.
- **Menu bar progress ring** and a desktop widget showing today's hours
  against your daily target.
- **Finish day/week wizard** that walks through short days step by step,
  suggesting unlogged commits, prolonged blocks, or manual entries.
- **Trask timesheet upload** (optional) — semi-automatically logs your
  time into Trask's own timesheet via a Chrome window you review and
  confirm, with optional 1Password autofill for the login step.

## Install

Requires macOS 14 or later.

```
brew tap MartinMatousek/vaire
brew install --cask vaire
```

Vaire is not notarized (no paid Apple Developer account behind it yet), so
macOS will block the first launch. To open it:

1. Try to open Vaire — Gatekeeper will refuse and offer no direct bypass.
2. Go to **System Settings → Privacy & Security**, scroll to the bottom,
   and click **Open Anyway** next to the Vaire warning.
3. Confirm in the dialog that appears. Vaire will launch normally from then
   on.

### Claude Code integration (optional)

To have Vaire automatically log time from Claude Code sessions, install the
CLI and register the hooks:

```
./scripts/install_cli.sh
```

This installs `vaire` to `~/.local/bin/`. Then register these scripts in
your `~/.claude/settings.json`, with a generous `timeout` (the
SessionStart/SessionEnd hooks open VaireApp's real note/edit windows via a
`vaire://` URL and wait up to 180s for you to act on them — 200s+ is a
safe margin):

- `hooks/vaire-session-start.sh` under `SessionStart`
- `hooks/vaire-session-end.sh` under `SessionEnd`
- `hooks/vaire-stop-enforce-estimate.sh` under `Stop` (optional — nudges
  Claude to record a time-saved estimate before ending a task; skip it if
  you don't want that)

`hooks/vaire-stop-and-review.sh` isn't registered directly — it's shared
logic the other scripts source. See the project structure section below
for what each one does.

Hooks only track repositories you've explicitly opted in — they stay
silent for every other `cwd` instead of prompting on each session. To
enable a repository:

1. Open Vaire's Settings window.
2. Add the repository if it isn't listed yet — either it will already be
   there from a prior Claude Code session (auto-created but disabled), or
   pick its folder with **Choose…** and click **Add**.
3. Check the **Track** box next to it.

Only repositories with **Track** checked will show the SessionStart /
SessionEnd dialogs and log time. The menu bar dropdown's project list only
shows followed repositories too, each with a **Remove** link to unfollow
it (disabled while its timer is running) — equivalent to unchecking
**Track** in Settings.

### Importing from git

The Week window has an **Import from git…** button, scoped to the week
currently shown. It reads your commits in the selected project for that
week (filtered to `git config user.email`), groups them into candidate
time blocks, and opens a review sheet before writing anything — each
candidate shows its start time and an editable duration (hours/minutes,
same as everywhere else in the app), its note is editable too, and you
can uncheck any candidate you don't want. Choose whether to replace
previously git-imported blocks for that week or add alongside them.
Nothing is written until you click **Import** in the sheet. Use it to
backfill time you spent working on a project outside Claude Code — Vaire
has no other way to see that work.

### Finishing a short day or week

The Week window has **Finish day…** and **Finish week…** buttons — a
guided, step-by-step way to fill a day that's under your target hours.
Each step offers one suggestion at a time: an unlogged git commit, an
existing block you can prolong (for work done after a session ended), or
a manual entry — Skip or Add & next, until the day's gap is closed or you
run out of suggestions. **Finish week…** runs the same flow across every
day in the week that isn't already at target, skipping days that are.

### Uploading time to Trask

If you work at Trask, the Week window's **Upload day…** / **Upload
week…** buttons can log your time into Trask's own timesheet
(`my.trask.cz`) for you. Since Trask has no API, this drives a real
Chrome window instead: pair each project with its Trask project/task in
Settings first, then Upload fills one Trask entry at a time in a Chrome
window and pauses before Save — you review it and click Save yourself.
Nothing is ever submitted without you looking at it first.

The Chrome window itself launches automatically, and if you enable
**1Password** autofill in Settings and pick your Trask login item, only
approving MFA on your phone is ever needed — no password is stored by
Vaire; it's fetched from 1Password (via the `op` CLI) per attempt.
Requires:

```
brew install --cask 1password-cli
```

Then enable **Integrate with 1Password CLI** in 1Password.app → Settings
→ Developer. See [`VaireUpload/README.md`](VaireUpload/README.md) for
the underlying automation details.

### Language

Vaire's UI (app and hook dialogs) is available in English and Czech.
English is the default; switch to Czech in Settings → **Language** — the
change takes effect after restarting the app.

## Project structure

- `VaireKit/` — shared Swift Package (model, SQLite store, importers,
  merge logic, export). Buildable and testable standalone:
  ```
  cd VaireKit && swift test
  ```
- `VaireApp/` — the menu bar app
- `VaireWidget/` — WidgetKit extension
- `VaireKit/Sources/VaireCLI/` — `vaire`, the CLI bridge between Claude Code
  hooks and the shared SQLite database in
  `~/Library/Application Support/Vaire/`
- `hooks/` — `SessionStart`/`SessionEnd`/`Stop` hook scripts for automatic
  time logging from Claude Code sessions, plus shared logic they source
  (`vaire-stop-and-review.sh`)
- `VaireUpload/` — Node/Playwright scripts behind the Trask upload
  feature; not part of the Swift package, see its own README
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  manifest; `Vaire.xcodeproj` is generated from it and not checked in

## Development

```
brew install xcodegen   # one-time
xcodegen generate
open Vaire.xcodeproj
```

Or from the command line:

```
xcodebuild -project Vaire.xcodeproj -scheme VaireApp \
  -destination 'platform=macOS' build
```

## License

GPL-3.0 — see [LICENSE](LICENSE).
