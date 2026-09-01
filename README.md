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

This installs `vaire` to `~/.local/bin/`. Then add the scripts under
`hooks/` to your `~/.claude/settings.json` under `SessionStart` and
`SessionEnd`, with a generous `timeout` (the hooks show interactive
dialogs — 120s is a safe margin). See `hooks/` for the scripts and the
project structure section below for what each one does.

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
time blocks, and opens a review sheet before writing anything — you can
edit each candidate's note or start/end time, uncheck any you don't want,
and choose whether to replace previously git-imported blocks for that
week or add alongside them. Nothing is written until you click **Import**
in the sheet. Use it to backfill time you spent working on a project
outside Claude Code — Vaire has no other way to see that work.

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
- `hooks/` — `SessionStart`/`SessionEnd` hook scripts for automatic time
  logging from Claude Code sessions
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
