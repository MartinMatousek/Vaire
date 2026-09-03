// Fills one Trask "Log time" entry from a JSON argument and stops before
// Save — the user reviews the filled form in their own Chrome window and
// clicks Save themselves. This is the semi-automatic design: the script's
// job ends at "the form is correctly filled," never at "the entry is
// submitted." Confirmed live (2026-09-03) that a plain `.fill()` on the
// Hours/Minutes numeric inputs works with no comma-decimal handling needed,
// and that the date range field already defaults to today, so this script
// only touches the date picker when the requested date isn't today.
//
// Usage:
//   node src/fillEntry.mjs '{"projectLabel":"...","taskLabel":"...","dateISO":"2026-09-02","hours":1,"minutes":30,"description":"...","remoteWork":false}'
//
// Prints "ready" to stdout and exits 0 once the form is filled and waiting
// for the user. Prints a human-readable error to stderr and exits 1 on any
// failure (bad input, project/task not found, dropdown never enabled, etc).
// Never clicks the Save button.
import { attachToTraskTab, dropdownByInputName, selectDropdownOption } from './attach.mjs';

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

  // Date: only touch the picker if the requested date isn't already showing
  // — confirmed live that it defaults to today, so same-day entries (the
  // common case for the day-finish flow) need no date interaction at all.
  const wantedDate = formatTraskDate(entry.dateISO);
  const dateInput = page.locator('input.rz-daterangepicker-single-input');
  const currentDate = await dateInput.inputValue().catch(() => '');
  if (currentDate.trim() !== wantedDate) {
    // The date range picker is a calendar popup, not a typeable field in
    // the confirmed-working path — typing into it was not exercised in the
    // spike. Fail loudly rather than guess at calendar navigation; the
    // finish-day flow only ever uploads for the day it just reviewed, so
    // this path should be rare (e.g. uploading a backdated entry).
    throw new Error(
      `Date field shows "${currentDate}", need "${wantedDate}", and this script doesn't yet drive the date picker. ` +
      'Set the date by hand in the browser, or only upload for today until the picker path is implemented.'
    );
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

  // Deliberately no Save click. Confirm the fields actually hold what we
  // set before declaring success — a silently-rejected fill (e.g. a
  // disabled field) should surface as an error, not a false "ready".
  const finalHours = await page.locator('#NumericHours').inputValue();
  const finalMinutes = await page.locator('#NumericMinutes').inputValue();
  if (finalHours !== String(entry.hours) || finalMinutes !== String(entry.minutes)) {
    throw new Error(`Hours/Minutes did not hold the requested values (wanted ${entry.hours}/${entry.minutes}, form shows ${finalHours}/${finalMinutes}).`);
  }

  await browser.close(); // detaches only, browser window stays open with the filled form

  process.stdout.write('ready\n');
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
