// Fills one Trask "Log time" entry from a JSON argument and clicks Save —
// fully automatic. Confirmed live that a plain `.fill()` on the
// Hours/Minutes numeric inputs works with no comma-decimal handling
// needed, and that the date field already defaults to today, so this
// script only touches it when the requested date isn't today, by typing
// directly into it (see `setDatePickerDate` in attach.mjs).
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
// reappear, revert this Save click first before suspecting the dedup
// logic — that's the part that changed here.
//
// Usage:
//   node src/fillEntry.mjs '{"projectLabel":"...","taskLabel":"...","dateISO":"2026-09-02","hours":1,"minutes":30,"description":"...","remoteWork":false}'
//
// Prints "ready" to stdout and exits 0 once the form is filled and saved.
// Prints a human-readable error to stderr and exits 1 on any failure (bad
// input, project/task not found, dropdown never enabled, etc).
import { attachToTraskTab, dropdownByInputName, selectDropdownOption, setDatePickerDate } from './attach.mjs';

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

// Trask's date field renders dd.MM.yyyy; dateISO comes in as yyyy-MM-dd.
function formatTraskDate(dateISO) {
  const [year, month, day] = dateISO.split('-');
  if (!year || !month || !day) {
    throw new Error(`dateISO must be yyyy-MM-dd, got "${dateISO}"`);
  }
  return `${day}.${month}.${year}`;
}

async function main() {
  const entry = parseEntryArg(process.argv);
  const { browser, page } = await attachToTraskTab();

  if (!page.url().endsWith('my.trask.cz/') && !page.url().includes('/timesheet')) {
    await page.goto('https://my.trask.cz/');
    await page.waitForLoadState('networkidle');
  }

  const projectDropdown = dropdownByInputName(page, 'DropDownProject');
  const taskDropdown = dropdownByInputName(page, 'DropDownTimeEntryTask');

  await projectDropdown.waitFor({ state: 'visible', timeout: 15000 });

  try {
    await selectDropdownOption(page, projectDropdown, entry.projectLabel);
  } catch (error) {
    throw new Error(`Could not select project "${entry.projectLabel}" — it may no longer exist in Trask. Re-run the catalog refresh. (${error.message})`);
  }

  const taskInput = page.locator('input[name="DropDownTimeEntryTask"]');
  await taskInput.waitFor({ state: 'attached', timeout: 5000 });
  try {
    await page.waitForFunction(
      () => {
        const input = document.querySelector('input[name="DropDownTimeEntryTask"]');
        return input && !input.disabled;
      },
      { timeout: 10000 }
    );
  } catch {
    throw new Error(`Task dropdown never enabled after selecting project "${entry.projectLabel}".`);
  }

  try {
    await selectDropdownOption(page, taskDropdown, entry.taskLabel);
  } catch (error) {
    throw new Error(`Could not select task "${entry.taskLabel}" under project "${entry.projectLabel}" — it may no longer exist. Re-run the catalog refresh. (${error.message})`);
  }

  // Date: only touch the field if the requested date isn't already showing
  // — confirmed live that it defaults to today, so same-day entries (the
  // common case for the day-finish flow) need no date interaction at all.
  const wantedDate = formatTraskDate(entry.dateISO);
  const dateInput = page.locator('input.rz-daterangepicker-single-input');
  const currentDate = await dateInput.inputValue().catch(() => '');
  if (currentDate.trim() !== wantedDate) {
    try {
      await setDatePickerDate(page, entry.dateISO);
    } catch (error) {
      throw new Error(`Could not set the date field to "${wantedDate}": ${error.message}`);
    }
  }

  await page.locator('#NumericHours').fill(String(entry.hours));
  await page.keyboard.press('Tab');
  await page.locator('#NumericMinutes').fill(String(entry.minutes));
  await page.keyboard.press('Tab');

  await page.locator('#Description').fill(entry.description);

  if (entry.remoteWork) {
    const checkbox = page.locator('#RemoteWorkCheckBox');
    const isChecked = await checkbox.isChecked().catch(() => false);
    if (!isChecked) {
      await page.locator('label[for="RemoteWorkCheckBox"]').click();
    }
  }

  // Confirm the fields actually hold what we set before clicking Save — a
  // silently-rejected fill (e.g. a disabled field) should surface as an
  // error here, not show up as a confusing failure after Save.
  const finalHours = await page.locator('#NumericHours').inputValue();
  const finalMinutes = await page.locator('#NumericMinutes').inputValue();
  if (finalHours !== String(entry.hours) || finalMinutes !== String(entry.minutes)) {
    throw new Error(`Hours/Minutes did not hold the requested values (wanted ${entry.hours}/${entry.minutes}, form shows ${finalHours}/${finalMinutes}).`);
  }

  // The Save button has no stable id (Radzen auto-generates a fresh one
  // per page load), so select by its exact visible text instead.
  const saveButton = page.locator('button.rz-button', { hasText: 'Save' }).first();
  await saveButton.waitFor({ state: 'visible', timeout: 5000 });
  await saveButton.click();

  // Wait for the form to clear/close, confirming the save round-trip
  // actually completed before this script exits — an unconfirmed click
  // would look identical to success from the caller's side.
  await page.locator('#Description').waitFor({ state: 'hidden', timeout: 15000 }).catch(async () => {
    // Some Trask flows keep the form open and just clear its fields
    // instead of hiding it — fall back to checking the Description field
    // emptied out as evidence the save happened.
    const remaining = await page.locator('#Description').inputValue().catch(() => '');
    if (remaining === entry.description) {
      throw new Error('Save click did not appear to complete — form still shows the filled description.');
    }
  });

  await browser.close(); // detaches only, browser window stays open

  process.stdout.write('ready\n');
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
