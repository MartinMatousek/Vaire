# Vaire

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

## Project structure

- `VaireKit/` — shared Swift Package (model, SQLite store, importers,
  merge logic, export). Buildable and testable standalone:
  ```
  cd VaireKit && swift test
  ```
- `VaireApp/` — the menu bar app
- `VaireWidget/` — WidgetKit extension
- `VaireKit/Sources/VaireCLI/` — `vaire`, the CLI bridge between Claude Code
  hooks and the shared App Group database
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
