# Vaire

*English: [README.md](README.md)*

Automatický sledovač času pro macOS. Vaire odvozuje odpracovaný čas z
přepisů Claude Code session (`~/.claude/projects/*/*.jsonl`) a z historie
git commitů, s ručním zadáváním a úpravami navrch. Aplikace v menu baru +
WidgetKit widget s denním ukazatelem postupu.

## Co umí

- **Automaticky sleduje čas** z Claude Code sessions přes
  `SessionStart`/`SessionEnd` hooky — žádné ruční spouštění/zastavování,
  když pracuješ s Claude Code.
- **Ruční start/stop** pro jednotlivé projekty z menu baru, pro práci mimo
  Claude Code.
- **Týdenní pohled** s rozšiřitelnou časovou osou, běžící/dokončené bloky
  vizuálně odlišené, drag-and-drop mezi dny a inline úpravy času, poznámek
  a odhadů pracnosti.
- **Odhady úspory času** — zaznamenává, jak dlouho by task trval bez AI,
  porovnané s reálně naloggovaným časem, aby bylo vidět přidanou hodnotu.
- **Ukazatel postupu v menu baru** a desktopový widget s dnešními
  odpracovanými hodinami vůči dennímu cíli.
- **Průvodce dokončením dne/týdne**, který krok za krokem projde kratší
  dny a navrhne nezalogované commity, prodloužení bloku nebo ruční záznam.
- **Nahrání do Trask** (volitelné) — poloautomaticky zaloguje čas do
  vlastního timesheetu Trask přes okno Chrome, které zkontroluješ a
  potvrdíš, s volitelným automatickým vyplněním přihlášení přes 1Password.

## Instalace

Vyžaduje macOS 14 nebo novější.

```
brew tap MartinMatousek/vaire
brew install --cask vaire
```

Vaire není notarizovaný (zatím žádný placený Apple Developer účet), takže
macOS zablokuje první spuštění. Jak ho otevřít:

1. Zkus Vaire otevřít — Gatekeeper to odmítne a nenabídne přímý obchvat.
2. Jdi do **Nastavení systému → Soukromí a zabezpečení**, sjeď dolů a
   klikni na **Přesto otevřít** vedle upozornění na Vaire.
3. Potvrď v dialogu, který se objeví. Vaire pak už bude spouštět normálně.

### Integrace s Claude Code (volitelné)

Aby Vaire automaticky loggoval čas z Claude Code sessions, nainstaluj CLI
a zaregistruj hooky:

```
./scripts/install_cli.sh
```

Tím se nainstaluje `vaire` do `~/.local/bin/`. Pak zaregistruj tyto
skripty v `~/.claude/settings.json`, s velkorysým `timeout`
(SessionStart/SessionEnd hooky otevřou skutečné okno Vaire přes `vaire://`
URL a čekají až 180s, než na něj zareaguješ — 200s+ je bezpečná rezerva):

- `hooks/vaire-session-start.sh` pod `SessionStart`
- `hooks/vaire-session-end.sh` pod `SessionEnd`
- `hooks/vaire-stop-enforce-estimate.sh` pod `Stop` (volitelné — pobídne
  Claude, aby před ukončením tasku zapsal odhad úspory času; pokud to
  nechceš, vynech ho)

`hooks/vaire-stop-and-review.sh` se neregistruje přímo — je to sdílená
logika, kterou ostatní skripty sourcují. Co který skript dělá, viz sekce
o struktuře projektu níže.

Hooky sledují jen repozitáře, které jsi výslovně zapnul — u ostatních
`cwd` zůstávají zticha místo aby se ptaly při každé session. Jak zapnout
repozitář:

1. Otevři okno Nastavení ve Vaire.
2. Přidej repozitář, pokud tam ještě není — buď tam už bude z dřívější
   Claude Code session (automaticky vytvořený, ale vypnutý), nebo vyber
   jeho složku přes **Choose…** a klikni na **Add**.
3. Zaškrtni vedle něj **Track**.

Jen repozitáře se zaškrtnutým **Track** budou zobrazovat dialogy
SessionStart / SessionEnd a loggovat čas. Seznam projektů v menu baru
taky zobrazuje jen sledované repozitáře, každý s odkazem **Remove** pro
odhlášení (vypnutý, dokud běží jeho časovač) — funguje stejně jako
odškrtnutí **Track** v Nastavení.

### Import z gitu

Okno Týden má tlačítko **Import from git…**, které pracuje se zrovna
zobrazeným týdnem. Načte tvé commity ve vybraném projektu za tento týden
(filtrované podle `git config user.email`), seskupí je do kandidátních
časových bloků a než cokoliv zapíše, otevře kontrolní okno — u každého
kandidáta vidíš čas začátku a upravuješ délku trvání (hodiny/minuty,
stejně jako všude jinde v aplikaci), poznámka jde upravit taky, a
kandidáty, co nechceš, můžeš odškrtnout. Zvol, jestli se mají nahradit
dříve naimportované bloky za ten týden, nebo se mají jen přidat vedle
nich. Nic se nezapíše, dokud v kontrolním okně neklikneš na **Import**.
Použij ho, pokud jsi na projektu pracoval mimo Claude Code — Vaire jinak
nemá jak takovou práci vidět.

### Dokončení kratšího dne nebo týdne

Okno Týden má tlačítka **Finish day…** a **Finish week…** — průvodce
krok za krokem, jak doplnit den, který nedosahuje cílových hodin. Každý
krok nabídne jeden návrh: nezalogovaný git commit, existující blok, který
lze prodloužit (pro práci po skončení session), nebo ruční záznam —
Přeskočit nebo Přidat a další, dokud se mezera nezavře nebo návrhy
nedojdou. **Finish week…** projede stejně každý den v týdnu, který ještě
není na cíli, dny na cíli přeskočí.

### Nahrání času do Trask

Pokud pracuješ v Trask, tlačítka **Upload day…** / **Upload week…** v
okně Týden můžou zalogovat čas do vlastního timesheetu Trask
(`my.trask.cz`) za tebe. Trask nemá API, takže se místo toho ovládá
skutečné okno Chrome: nejdřív v Nastavení spáruj každý projekt s jeho
Trask projektem/úkolem, pak Upload vyplní jeden záznam Trask po druhém v
okně Chrome a zastaví se před Uložit — zkontroluješ ho a Uložit klikneš
sám. Nic se nikdy neodešle bez tvé kontroly.

Okno Chrome se spouští automaticky, a pokud v Nastavení zapneš
automatické vyplnění přes **1Password** a vybereš svou položku pro
přihlášení do Trask, stačí už jen potvrdit MFA v telefonu — Vaire žádné
heslo neukládá, natahuje ho z 1Password (přes CLI `op`) při každém
pokusu. Vyžaduje:

```
brew install --cask 1password-cli
```

Pak zapni **Integrate with 1Password CLI** v 1Password.app → Settings →
Developer. Podrobnosti o automatizaci viz
[`VaireUpload/README.md`](VaireUpload/README.md).

### Jazyk

Rozhraní Vaire (aplikace i dialogy z hooků) je dostupné v angličtině a
češtině. Výchozí je angličtina; na češtinu přepneš v Nastavení →
**Language** — změna se projeví po restartu aplikace.

## Struktura projektu

- `VaireKit/` — sdílený Swift Package (model, SQLite úložiště,
  importéry, slučovací logika, export). Sestavitelný a testovatelný
  samostatně:
  ```
  cd VaireKit && swift test
  ```
- `VaireApp/` — aplikace v menu baru
- `VaireWidget/` — WidgetKit extension
- `VaireKit/Sources/VaireCLI/` — `vaire`, CLI most mezi Claude Code hooky
  a sdílenou SQLite databází v `~/Library/Application Support/Vaire/`
- `hooks/` — skripty `SessionStart`/`SessionEnd`/`Stop` hooků pro
  automatický logging času z Claude Code sessions, plus sdílená logika,
  kterou sourcují (`vaire-stop-and-review.sh`)
- `VaireUpload/` — Node/Playwright skripty pro nahrávání do Trask; není
  součástí Swift Package, viz vlastní README
- `project.yml` — manifest pro [XcodeGen](https://github.com/yonaskolb/XcodeGen);
  `Vaire.xcodeproj` se z něj generuje a není v repozitáři

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
