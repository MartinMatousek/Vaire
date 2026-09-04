// Fills one Trask "Log time" entry from a JSON argument and clicks Save —
// fully automatic. One-shot CLI wrapper kept for manual debugging; VaireApp
// no longer calls this directly for the upload flow — see session.mjs,
// which shares the exact same fill logic via attach.mjs's `runFillEntry`.
//
// History: reverted to semi-automatic (2026-09-04) after a fully-automatic
// version created real duplicate entries in the user's live Trask
// timesheet on repeated attempts, root cause never fully pinned down
// (suspected: a gap between the batch dedup check's snapshot and what
// Trask's UI actually reflects by the time each fill runs). Re-enabled
// (2026-09-04) after several live full upload+Save cycles, including
// re-runs over already-uploaded weeks, showed no duplicates with the
// existing batch dedup (UploadFlowView.isDuplicate, checked once via
// checkExistingEntries.mjs before the fill loop starts). If duplicates
// reappear, revert the Save click in `runFillEntry` (attach.mjs) first
// before suspecting the dedup logic — that's the part that changed here.
//
// Usage:
//   node src/fillEntry.mjs '{"projectLabel":"...","taskLabel":"...","dateISO":"2026-09-02","hours":1,"minutes":30,"description":"...","remoteWork":false}'
//
// Prints "ready" to stdout and exits 0 once the form is filled and saved.
// Prints a human-readable error to stderr and exits 1 on any failure (bad
// input, project/task not found, dropdown never enabled, etc).
import { attachToTraskTab, runFillEntry } from './attach.mjs';

function parseEntryArg(argv) {
  const raw = argv[2];
  if (!raw) {
    throw new Error('Missing entry JSON argument. Usage: node src/fillEntry.mjs \'{"projectLabel":...}\'');
  }
  let entry;
  try {
    entry = JSON.parse(raw);
  } catch (error) {
    throw new Error(`Entry argument is not valid JSON: ${error.message}`);
  }

  const required = ['projectLabel', 'taskLabel', 'dateISO', 'hours', 'minutes', 'description'];
  const missing = required.filter((key) => entry[key] === undefined || entry[key] === null);
  if (missing.length > 0) {
    throw new Error(`Entry JSON is missing required field(s): ${missing.join(', ')}`);
  }
  if (!Number.isInteger(entry.hours) || entry.hours < 0 || entry.hours > 24) {
    throw new Error(`hours must be an integer between 0 and 24, got ${JSON.stringify(entry.hours)}`);
  }
  if (!Number.isInteger(entry.minutes) || entry.minutes < 0 || entry.minutes > 45 || entry.minutes % 15 !== 0) {
    throw new Error(`minutes must be an integer 0, 15, 30, or 45 (Trask's own field limit), got ${JSON.stringify(entry.minutes)}`);
  }
  return entry;
}

async function main() {
  const entry = parseEntryArg(process.argv);
  const { browser, page } = await attachToTraskTab();

  await runFillEntry(page, entry);

  await browser.close(); // detaches only, browser window stays open

  process.stdout.write('ready\n');
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
