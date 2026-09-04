// Scrapes the live Project/Task catalog from the timesheet's "Log time"
// form and prints it as JSON to stdout. Read-only: this never selects
// Type, sets Hours/Minutes, or touches Save — it only opens dropdowns to
// read their options. VaireApp shells out to this (via Process) every time
// an upload runs, per the "re-scrape every upload" design decision, so the
// local timesheetProject/timesheetTask cache never drifts silently out of
// date.
//
// Usage: node src/scrapeCatalog.mjs
// Output (stdout, single JSON object, one line):
//   { "<project label>": { "tasks": ["<task label>", ...] }, ... }
// On failure: a human-readable error on stderr, exit code 1. Nothing is
// printed to stdout on failure — callers should treat "empty stdout" as
// well as a non-zero exit code as failure.
import { attachToTimesheetTab, dropdownByInputName, selectDropdownOption, readDropdownOptions } from './attach.mjs';

async function main() {
  const { browser, page } = await attachToTimesheetTab();

  // Reload to the timesheet root defensively — if the tab is on some other
  // my.trask.cz page (e.g. Export, Dashboard) the Log-time form and its
  // dropdowns won't exist yet.
  if (!page.url().endsWith('my.trask.cz/') && !page.url().includes('/timesheet')) {
    await page.goto('https://my.trask.cz/');
    await page.waitForLoadState('networkidle');
  }

  const projectDropdown = dropdownByInputName(page, 'DropDownProject');
  const taskDropdown = dropdownByInputName(page, 'DropDownTimeEntryTask');

  await projectDropdown.waitFor({ state: 'visible', timeout: 15000 });

  const projectLabels = await readDropdownOptions(page, projectDropdown);
  if (projectLabels.length === 0) {
    throw new Error('Project dropdown returned no options — the timesheet page layout may have changed.');
  }

  const catalog = {};
  for (const label of projectLabels) {
    await selectDropdownOption(page, projectDropdown, label);

    // Selecting a project triggers a Blazor Server round-trip that enables
    // and repopulates the Task dropdown. Wait for it to leave the disabled
    // state rather than a fixed sleep — this is the one true async
    // dependency in the whole flow.
    const taskInput = page.locator('input[name="DropDownTimeEntryTask"]');
    await taskInput.waitFor({ state: 'attached', timeout: 5000 });

    let enabled = true;
    try {
      await page.waitForFunction(
        () => {
          const input = document.querySelector('input[name="DropDownTimeEntryTask"]');
          return input && !input.disabled;
        },
        { timeout: 10000 }
      );
    } catch {
      enabled = false;
    }

    if (!enabled) {
      catalog[label] = { tasks: [], error: 'task dropdown stayed disabled for this project' };
      continue;
    }

    const taskLabels = await readDropdownOptions(page, taskDropdown);
    catalog[label] = { tasks: taskLabels };
  }

  // Detach only — this is the user's real browser session, never close it.
  await browser.close();

  process.stdout.write(JSON.stringify(catalog) + '\n');
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
