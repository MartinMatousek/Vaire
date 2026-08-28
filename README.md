# TimeKeeper

Automatický time tracker pro macOS. Odvozuje odpracovaný čas z Claude Code
session transcriptů (`~/.claude/projects/*/*.jsonl`) a git commit historie,
doplněný ruční editací. Menu bar app + WidgetKit widget s denním progress
ringem.

## Struktura

- `TimeKeeperKit/` — sdílený Swift Package (model, SQLite store, importéry,
  slučovací logika, export). Buildovatelný a testovatelný samostatně:
  ```
  cd TimeKeeperKit && swift test
  ```
- `TimeKeeperApp/` — menu bar aplikace (`MenuBarExtra`)
- `TimeKeeperWidget/` — WidgetKit extension
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) manifest;
  `TimeKeeper.xcodeproj` se generuje z něj a není verzovaný

## Vývoj

```
brew install xcodegen   # jednorázově
xcodegen generate
open TimeKeeper.xcodeproj
```

Nebo z příkazové řádky:

```
xcodebuild -project TimeKeeper.xcodeproj -scheme TimeKeeperApp \
  -destination 'platform=macOS' build
```

## Licence

GPL-3.0 — viz [LICENSE](LICENSE).
