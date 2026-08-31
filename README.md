# Vaire

Automatický time tracker pro macOS. Odvozuje odpracovaný čas z Claude Code
session transcriptů (`~/.claude/projects/*/*.jsonl`) a git commit historie,
doplněný ruční editací. Menu bar app + WidgetKit widget s denním progress
ringem.

## Struktura

- `VaireKit/` — sdílený Swift Package (model, SQLite store, importéry,
  slučovací logika, export). Buildovatelný a testovatelný samostatně:
  ```
  cd VaireKit && swift test
  ```
- `VaireApp/` — menu bar aplikace (`MenuBarExtra`)
- `VaireWidget/` — WidgetKit extension
- `VaireKit/Sources/VaireCLI/` — `vaire`, CLI most mezi
  Claude Code hooky a sdílenou App Group databází
- `hooks/` — `SessionStart`/`SessionEnd` hook skripty pro automatické
  logování času Claude Code sessions (viz níže)
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) manifest;
  `Vaire.xcodeproj` se generuje z něj a není verzovaný

## Claude Code integrace

`vaire` čte/zapisuje přímo do sdílené App Group SQLite databáze
(stejná, kterou používá app i widget). Hook skripty v `hooks/` ho volají ze
`SessionStart`/`SessionEnd` Claude Code hooků a používají `osascript` dialogy
pro synchronní dotazy na poznámku a úpravu času.

Instalace CLI (nutná po každé změně `VaireCLI`):

```
./scripts/install_cli.sh
```

Nainstaluje `vaire` do `~/.local/bin/`. Hook skripty musí být
zaregistrované v `~/.claude/settings.json` pod `SessionStart`/`SessionEnd`
s dostatečným `timeout` (dialogy čekají na interakci — 120 s je bezpečná
rezerva).

## Vývoj

```
brew install xcodegen   # jednorázově
xcodegen generate
open Vaire.xcodeproj
```

Nebo z příkazové řádky:

```
xcodebuild -project Vaire.xcodeproj -scheme VaireApp \
  -destination 'platform=macOS' build
```

## Licence

GPL-3.0 — viz [LICENSE](LICENSE).
