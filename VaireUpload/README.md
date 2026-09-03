# VaireUpload

Node/Playwright helpers that drive the Trask timesheet at `my.trask.cz`. Shelled out to by VaireApp via `Process`, the same pattern `GitImporter` uses for `/usr/bin/git`. Not part of the Swift package or app bundle.

## Why a separate Chrome, not a spawned one

`my.trask.cz` is Blazor Server — no REST endpoint, no CSV import, and login is Keycloak with 2FA. Rather than storing credentials or fighting 2FA in a headless browser, these scripts attach over the Chrome DevTools Protocol (CDP) to a real Chrome window you launch and log into by hand. No credentials ever touch Vaire or this code.

## One-time setup

```bash
cd VaireUpload
npm install
npx playwright install chromium
```

## Every time you want to scrape or upload

1. Launch a **separate** debug Chrome profile — Chrome 127+ silently ignores `--remote-debugging-port` on your normal/default profile, so this must be a distinct `--user-data-dir`:
   ```bash
   open -na "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir="$HOME/chrome-trask-debug"
   ```
2. In that window, go to `https://my.trask.cz/` and log in (first time only — the profile persists after that).
3. Confirm the debug port is up:
   ```bash
   curl -s http://localhost:9222/json/version
   ```
4. Now `scrapeCatalog.mjs` / `fillEntry.mjs` can attach to that tab.

## Scripts

- **`src/scrapeCatalog.mjs`** — read-only. Walks the Project dropdown, and for each project reads its Task dropdown. Prints one JSON line to stdout: `{ "<project label>": { "tasks": ["<task label>", ...] } }`. Never touches Save.
- **`src/fillEntry.mjs`** — fills one Log-time entry from a JSON argument and stops before Save:
  ```bash
  node src/fillEntry.mjs '{"projectLabel":"...","taskLabel":"...","dateISO":"2026-09-02","hours":1,"minutes":30,"description":"...","remoteWork":false}'
  ```
  Prints `ready` and exits 0 once filled — you review and click Save yourself in the Chrome window. `minutes` must be 0/15/30/45 (Trask's own field limit). Only same-day entries are supported today — see `attach.mjs`'s comments if the date field ever needs driving via the calendar picker.

## Known constraints

- Radzen (the UI library Trask uses) re-marks/reorders dropdown options after a selection — both scripts always select by exact label text, never by index. Confirmed live: an index-based click caused a stale-element timeout on the 2nd project.
- If a project or task label has changed or been removed in Trask, `fillEntry.mjs` fails with a message telling you to re-run the catalog refresh — it does not guess or fall back to a similar label.
- The Trask project/task catalog changes over time (fiscal year rollovers rename the client/FY prefix; the trailing code, e.g. `ET97`, is the stable part). Re-scrape rather than relying on a cached list from months ago.
