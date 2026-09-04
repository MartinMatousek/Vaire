// Reads every already-logged timesheet entry for the currently-visible week in
// one pass — meant to be called ONCE before a whole batch of fillEntry.mjs
// calls, not once per entry (an earlier version had fillEntry.mjs check
// before every single fill, which meant reloading the page before every
// entry; that was both unnecessary, since the caller already knows the
// full batch up front, and didn't reliably prevent duplicates in practice).
//
// Usage:
//   node src/checkExistingEntries.mjs
//
// Prints one JSON line to stdout:
//   { "2026-09-01": [{"projectLabel":"...","note":"..."}], "2026-09-02": [...] }
// `note` is the entry's free-text description as the timesheet's calendar view
// shows it, not its task category — that view never exposes the task.
// Only dates within the currently-visible week appear as keys — the
// caller should treat a missing date as "couldn't check", not "nothing
// logged". Prints a human-readable error to stderr and exits 1 on
// failure.
import { attachToTimesheetTab, findExistingLoggedEntries } from './attach.mjs';

async function main() {
  const { browser, page } = await attachToTimesheetTab();
  const byDate = await findExistingLoggedEntries(page);
  await browser.close();
  process.stdout.write(JSON.stringify(byDate) + '\n');
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
