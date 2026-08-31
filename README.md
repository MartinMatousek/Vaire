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
- `TimeKeeperKit/Sources/TimeKeeperCLI/` — `timekeeper-cli`, CLI most mezi
  Claude Code hooky a sdílenou App Group databází
- `hooks/` — `SessionStart`/`SessionEnd` hook skripty pro automatické
  logování času Claude Code sessions (viz níže)
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) manifest;
  `TimeKeeper.xcodeproj` se generuje z něj a není verzovaný

## Claude Code integrace

`timekeeper-cli` čte/zapisuje přímo do sdílené App Group SQLite databáze
(stejná, kterou používá app i widget). Hook skripty v `hooks/` ho volají ze
`SessionStart`/`SessionEnd` Claude Code hooků a používají `osascript` dialogy
pro synchronní dotazy na poznámku a úpravu času.

Instalace CLI (nutná po každé změně `TimeKeeperCLI`):

```
./scripts/install_cli.sh
```

Nainstaluje `timekeeper-cli` do `~/.local/bin/`. Hook skripty musí být
zaregistrované v `~/.claude/settings.json` pod `SessionStart`/`SessionEnd`
s dostatečným `timeout` (dialogy čekají na interakci — 120 s je bezpečná
rezerva).

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
