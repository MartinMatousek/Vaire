// Shared CDP-attach helper for the timesheet automation scripts. Connects
// to a dedicated debug Chrome profile — never the user's regular Chrome —
// that Vaire launches itself on demand (ensureDebugChrome), so uploading
// never requires the user to run a shell command by hand. Credentials
// still never touch this codebase: login is either done by the user in
// that window, or (if enabled in Settings) via loginIfNeeded.mjs pulling
// from 1Password through the `op` CLI's biometric-gated per-call mode —
// no stored secret, no service-account token.
//
// A stale/expired CDP connection or a missing/wrong tab are both routine,
// expected failure modes here (the profile isn't running yet, the
// timesheet logged the session out, etc.) — every export throws a plain
// Error with an actionable message rather than letting a raw Playwright
// timeout surface, since VaireApp will show these messages to the user
// directly.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';

const CDP_URL = 'http://localhost:9222';
const DEBUG_PORT = 9222;
// Resolved to an absolute path, not the literal string "$HOME" — spawn()
// passes argv entries directly to the child process with no shell in
// between, so "$HOME" would reach `open`/Chrome unexpanded and Chrome would
// launch against a literal ./"$HOME" directory relative to its own cwd,
// which silently fails to bring up the debug port at all. Confirmed live:
// an absolute path launches correctly in well under a second; the literal
// "$HOME" string hangs indefinitely with no window ever opening.
const PROFILE_DIR = path.join(os.homedir(), 'chrome-timesheet-debug');

/**
 * Returns the user's configured timesheet root URL (Settings), throwing a
 * clear, actionable error if it hasn't been set yet — Vaire has no
 * built-in default, since the timesheet is specific to the user's own
 * organization. Called lazily (not at module load) so importing this file
 * never fails just because the setting is unset; only an actual attempt to
 * use the timesheet does.
 */
export function timesheetURL() {
  const url = process.env.TIMESHEET_URL;
  if (!url) {
    throw new Error(
      'No timesheet URL configured. Set it in Vaire\'s Settings before uploading or scraping.'
    );
  }
  return url;
}

/**
 * Whether `pageURL` is on the configured timesheet's host — compares
 * hostnames rather than a plain substring match, so a page on an unrelated
 * site that merely contains the configured domain as a substring
 * (theoretically) can't false-match. Returns false (never throws) for a
 * malformed `pageURL`, e.g. Chrome's transient "about:blank" on a brand
 * new tab.
 */
function isTimesheetHost(pageURL) {
  try {
    return new URL(pageURL).hostname === new URL(timesheetURL()).hostname;
  } catch {
    return false;
  }
}

async function isDebugPortUp() {
  try {
    const response = await fetch(`${CDP_URL}/json/version`, { signal: AbortSignal.timeout(1500) });
    return response.ok;
  } catch {
    return false;
  }
}

/**
 * Launches the dedicated debug Chrome profile if it isn't already running,
 * then waits for the CDP port to come up. Never touches the user's regular
 * Chrome — a separate --user-data-dir is required because Chrome silently
 * ignores --remote-debugging-port when another instance is already running
 * on the default profile (confirmed live during development).
 */
export async function ensureDebugChrome() {
  if (await isDebugPortUp()) return;

  const child = spawn(
    'open',
    ['-na', 'Google Chrome', '--args', `--remote-debugging-port=${DEBUG_PORT}`, `--user-data-dir=${PROFILE_DIR}`],
    { detached: true, stdio: 'ignore' }
  );
  child.unref(); // Chrome outlives this script; don't let it hold the process open

  const timeoutMs = 15000;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await isDebugPortUp()) return;
    await new Promise((resolve) => setTimeout(resolve, 300));
  }

  throw new Error(
    `Launched Chrome with a debug profile but it never came up on port ${DEBUG_PORT} within ${timeoutMs / 1000}s. ` +
    'Check that Google Chrome is installed and not blocked from launching.'
  );
}

/**
 * Connects to the debug Chrome and returns the Playwright `Browser` handle.
 * Callers that want auto-launch should call `ensureDebugChrome()` first —
 * this function only connects, it never spawns anything itself, so a
 * caller that deliberately wants "fail if not already running" (e.g. a
 * read-only diagnostic) can still get that behavior.
 */
export async function connectToDebugChrome() {
  try {
    return await chromium.connectOverCDP(CDP_URL);
  } catch (error) {
    throw new Error(
      'Could not connect to Chrome on the debug port (localhost:9222). ' +
      `Original error: ${error.message}`
    );
  }
}

/**
 * Connects to the debug Chrome, launching it first if needed, and returns
 * an open tab on the configured timesheet — navigating a fresh tab there
 * if none exists yet. This is the auto-launch entry point
 * `ensureReady.mjs` uses; plain `attachToTimesheetTab()` below stays as
 * the "tab must already exist" variant used by scripts that assume a
 * prior successful ensureReady/login.
 */
export async function ensureTimesheetTab() {
  await ensureDebugChrome();
  const browser = await connectToDebugChrome();

  // Repeated runs (retried logins, repeated uploads) can leave more than
  // one timesheet tab open — e.g. an old logged-out tab alongside a
  // freshly-logged-in one. Prefer the most recently opened match rather
  // than the first one found, and close the rest so they don't keep
  // accumulating or get picked up by mistake on a later run.
  const matches = [];
  for (const context of browser.contexts()) {
    for (const page of context.pages()) {
      if (isTimesheetHost(page.url())) {
        matches.push(page);
      }
    }
  }

  if (matches.length > 0) {
    const page = matches[matches.length - 1];
    for (const stale of matches.slice(0, -1)) {
      await stale.close().catch(() => {});
    }
    await page.bringToFront();
    await recoverFromStaleConnection(page);
    return { browser, page };
  }

  const context = browser.contexts()[0] ?? (await browser.newContext());
  const page = await context.newPage();
  await page.goto(timesheetURL());
  return { browser, page };
}

/**
 * Finds the open timesheet tab among the debug Chrome's windows. Throws a
 * clear, distinct message for "no such tab" vs. "tab is stuck on the
 * Keycloak login page" so the caller can show the right instruction.
 */
export async function findTimesheetPage(browser) {
  for (const context of browser.contexts()) {
    for (const page of context.pages()) {
      if (isTimesheetHost(page.url())) {
        if (page.url().includes('/auth/')) {
          throw new Error(
            'The timesheet tab is showing the Keycloak login page. ' +
            'Log in (including 2FA) in that Chrome window, then try again.'
          );
        }
        return page;
      }
    }
  }
  throw new Error(
    `No open tab found on the configured timesheet (${timesheetURL()}) in the debug Chrome window. ` +
    `Open ${timesheetURL()} there and log in, then try again.`
  );
}

/**
 * Blazor Server's SignalR connection drops after the tab sits idle for a
 * while (confirmed live: a debug Chrome tab left open across several
 * automation runs) and the timesheet throws up its own reconnect overlay
 * (`#components-reconnect-modal`) covering the whole page. The overlay
 * intercepts every click but doesn't remove any existing DOM content, so a
 * script reading text/attributes off the stale page looks like it's
 * succeeding right up until the actual click — which then hangs for the
 * full actionability timeout waiting on a target that's permanently
 * covered. A plain reload re-establishes the connection and is safe/
 * idempotent for the timesheet page.
 */
export async function recoverFromStaleConnection(page) {
  const modal = page.locator('#components-reconnect-modal');
  if (await modal.isVisible().catch(() => false)) {
    // 'networkidle' isn't a reliable signal for a Blazor Server page — it
    // keeps a persistent SignalR WebSocket open, which can make the page
    // look "network idle" before the app has actually finished
    // re-rendering after reconnecting. Wait for the modal to be gone and
    // for the project dropdown (present on every load of this page) to
    // reappear, rather than trusting a load-state heuristic.
    await page.reload();
    await modal.waitFor({ state: 'hidden', timeout: 15000 }).catch(() => {});
    await page.locator('input[name="DropDownProject"]').waitFor({ state: 'attached', timeout: 15000 });
  }
}

/**
 * Convenience wrapper: connect + find the tab + bring it to front, the
 * common case for every script here.
 */
export async function attachToTimesheetTab() {
  const browser = await connectToDebugChrome();
  const page = await findTimesheetPage(browser);
  await page.bringToFront();
  await recoverFromStaleConnection(page);
  return { browser, page };
}

/**
 * Locator for a Radzen dropdown wrapper, found via the name attribute on its
 * hidden input — Radzen puts interaction handlers on the wrapper div, not
 * the input, so callers click/interact with this, not the input directly.
 */
export function dropdownByInputName(page, inputName) {
  return page.locator('.rz-dropdown', {
    has: page.locator(`input[name="${inputName}"]`),
  });
}

/**
 * Opens a dropdown and selects the option matching `label` by exact text.
 *
 * Selecting by index is unsafe here: confirmed live against the timesheet's
 * actual Project dropdown that Radzen re-marks/reorders options after a selection,
 * which caused a stale-element timeout on the 2nd project when indexed by
 * position. Exact-label selection is the only implementation used anywhere
 * in this codebase — do not reintroduce index-based selection.
 */
export async function selectDropdownOption(page, dropdown, label) {
  // Confirmed live (2026-09-04) that this exact click sequence — dropdown
  // opens, options render, the target option resolves with a clean match
  // count of 1, `.click()` runs with no error — can still be silently
  // ignored by Radzen/Blazor (no exception, no visible change) for the
  // calendar's month/year dropdowns specifically, reproducibly, though the
  // identical sequence never failed for the Project/Task dropdowns
  // elsewhere in this codebase. Root cause not pinned down. Retrying the
  // whole open-and-click sequence a few times, checking the dropdown's own
  // displayed label actually changed, reliably recovers — a single retry
  // was enough in every reproduction. Only the calendar's dropdowns
  // actually populate `.rz-dropdown-label` with the selected value
  // (confirmed live the Project dropdown's is blank even after a
  // successful selection, showing its choice in the input instead), so
  // the verification is skipped — falling back to trusting a single
  // attempt, same as before — whenever that label is empty.
  const maxAttempts = 3;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await dropdown.click();
    const popup = page.locator('.rz-dropdown-panel:visible').first();
    await popup.waitFor({ state: 'visible', timeout: 5000 });
    // The panel itself becomes visible before Radzen finishes populating
    // its option list — wait for at least one option to actually be
    // present before searching for the specific one.
    await popup.locator('li[role="option"]').first().waitFor({ state: 'visible', timeout: 5000 });

    // Confirmed live (2026-09-03) that a label coming from Vaire (Swift ->
    // JSON -> shell arg -> process.argv) can arrive NFD-decomposed (e.g.
    // "Č" as "C" + combining caron, 2 codepoints) while the timesheet's DOM
    // renders the same text NFC-precomposed (1 codepoint) — visually and
    // even in a plain string diff they look identical, but a CSS
    // attribute selector or getByRole's accessible-name match against the
    // raw (non-normalized) label finds zero matches, and the click then
    // hangs for the full actionability timeout waiting on a match that
    // never appears. Normalize before matching so both forms compare
    // equal.
    const normalizedLabel = label.normalize('NFC');
    const target = popup.locator(`li[aria-label="${normalizedLabel.replace(/"/g, '\\"')}"]`);
    await target.click();

    const selectedLabel = (await dropdown.locator('.rz-dropdown-label').innerText().catch(() => '')).trim();
    if (!selectedLabel || selectedLabel === normalizedLabel || attempt === maxAttempts) return;
    await page.waitForTimeout(200);
  }
}

/**
 * Reads the visible option labels from a dropdown without selecting
 * anything, closing the popup afterward with Escape.
 */
export async function readDropdownOptions(page, dropdown) {
  await dropdown.click();
  const popup = page.locator('.rz-dropdown-panel:visible').first();
  await popup.waitFor({ state: 'visible', timeout: 5000 });
  const labels = await popup.locator('li[role="option"]').allInnerTexts();
  await page.keyboard.press('Escape');
  return labels.map((label) => label.trim());
}

/**
 * Sets the timesheet's date field to `dateISO` by typing directly into the input
 * and pressing Tab, rather than driving the calendar popup — confirmed
 * live (2026-09-04) that `input.rz-daterangepicker-single-input` accepts a
 * typed "dd.mm.yyyy" value and Tab commits it cleanly, closing the popup
 * with no month/year navigation needed at all. Not Enter — the Save
 * button is `type="submit"`, so Enter inside any form field risks
 * submitting the form before the rest of it is filled. An earlier implementation
 * drove the popup's calendar grid (prev/next clicks, then later
 * month/year dropdowns) and hit multiple confirmed-live Radzen/Blazor
 * quirks — clicks that resolved and ran with no error but were silently
 * ignored, a range-picker mode that activated unexpectedly on a second
 * click — none of which apply to typing into the field directly.
 */
export async function setDatePickerDate(page, dateISO) {
  const [year, month, day] = dateISO.split('-').map(Number);
  const expected = `${String(day).padStart(2, '0')}.${String(month).padStart(2, '0')}.${String(year)}`;

  const dateInput = page.locator('input.rz-daterangepicker-single-input');
  await dateInput.click();
  await dateInput.fill(expected);
  await page.keyboard.press('Tab');

  // Confirmed live the input's value updates asynchronously right after
  // Tab — reading it immediately can catch it mid-update. Poll briefly
  // instead of trusting a single synchronous read.
  const deadline = Date.now() + 3000;
  let finalValue = '';
  while (Date.now() < deadline) {
    finalValue = (await dateInput.inputValue()).trim();
    if (finalValue === expected) break;
    await page.waitForTimeout(100);
  }

  if (finalValue !== expected) {
    throw new Error(`Date field shows "${finalValue}" after typing "${expected}", expected them to match.`);
  }
}

/**
 * Reads the already-logged timesheet entries for every day in the currently-
 * visible week in one pass, returning
 * `{ [dateISO]: { projectLabel, note }[] }`. Meant to be called ONCE per
 * upload batch (by checkExistingEntries.mjs), not once per entry — an
 * earlier version checked before every single fill, reloading the page
 * each time, which was both unnecessary (the caller already knows the
 * whole batch up front) and the wrong layer to guarantee fresh data at:
 * reloading between fills didn't reliably prevent duplicates in practice
 * and added a full-page reload's latency to every entry.
 *
 * A date outside the currently-visible week simply doesn't appear as a
 * key in the returned object — callers checking such a date get no dedup
 * guarantee for it, same as before this function existed.
 *
 * Confirmed live (2026-09-04):
 * - "Timesheet" is the page's default view — the 7-day-column entries
 *   list (`.rz-events` / `.calendar-daysInTheWeek-field`) reads directly
 *   with no toggle click needed.
 * - The 7 day columns are `.rz-events` containers, Monday-to-Sunday
 *   order, matching `.calendar-daysInTheWeek-field`'s own date labels
 *   (also 7, same order, "dd.mm.yyyy" format in each field's text).
 * - An already-logged entry's `.rz-event-content` text is
 *   "Project label | Note text" (a literal " | " separator) — this is
 *   the entry's free-text note/description, NOT its timesheet task category.
 *   An earlier version of this function assumed the text after " | " was
 *   the task, which is wrong: the task category isn't shown in this
 *   compact view at all, so comparing it against Vaire's task label
 *   produced systematic false negatives (every real duplicate compared
 *   the task category against a description and never matched). An
 *   unlogged Microsoft Calendar-only item has no separator and a
 *   distinct grey inline style — this function only returns the logged
 *   ones.
 */
// The timesheet's date field renders dd.MM.yyyy; dateISO comes in as yyyy-MM-dd.
function formatTimesheetDate(dateISO) {
  const [year, month, day] = dateISO.split('-');
  if (!year || !month || !day) {
    throw new Error(`dateISO must be yyyy-MM-dd, got "${dateISO}"`);
  }
  return `${day}.${month}.${year}`;
}

/**
 * Fills one timesheet "Log time" entry on an already-attached `page` and clicks
 * Save — fully automatic. Extracted from fillEntry.mjs's `main()` so both
 * the one-shot CLI script and the long-lived session server share the exact
 * same fill/Save/confirm sequence; this function's body must stay a literal
 * lift of that logic, not a reimplementation, given its hard-won history
 * (see fillEntry.mjs's header comment for the duplicate-entry incident this
 * sequence's Save-confirm wait guards against).
 */
export async function runFillEntry(page, entry) {
  if (!page.url().endsWith(timesheetURL()) && !page.url().includes('/timesheet')) {
    await page.goto(timesheetURL());
    await page.waitForLoadState('networkidle');
  }

  const projectDropdown = dropdownByInputName(page, 'DropDownProject');
  const taskDropdown = dropdownByInputName(page, 'DropDownTimeEntryTask');

  await projectDropdown.waitFor({ state: 'visible', timeout: 15000 });

  try {
    await selectDropdownOption(page, projectDropdown, entry.projectLabel);
  } catch (error) {
    throw new Error(`Could not select project "${entry.projectLabel}" — it may no longer exist in the timesheet. Re-run the catalog refresh. (${error.message})`);
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
  const wantedDate = formatTimesheetDate(entry.dateISO);
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
    // Some timesheet flows keep the form open and just clear its fields
    // instead of hiding it — fall back to checking the Description field
    // emptied out as evidence the save happened.
    const remaining = await page.locator('#Description').inputValue().catch(() => '');
    if (remaining === entry.description) {
      throw new Error('Save click did not appear to complete — form still shows the filled description.');
    }
  });
}

export async function findExistingLoggedEntries(page) {
  await page.locator('.calendar-daysInTheWeek-field').first().waitFor({ state: 'visible', timeout: 15000 });

  const dayFields = page.locator('.calendar-daysInTheWeek-field');
  const dayCount = await dayFields.count();
  const eventsContainers = page.locator('.rz-events');
  const eventsCount = await eventsContainers.count();

  const byDate = {};
  for (let i = 0; i < dayCount && i < eventsCount; i++) {
    const fieldText = await dayFields.nth(i).innerText();
    const dateMatch = fieldText.match(/(\d{2})\.(\d{2})\.(\d{4})/);
    if (!dateMatch) continue;
    const [, day, month, year] = dateMatch;
    const dateISO = `${year}-${month}-${day}`;

    const contents = await eventsContainers.nth(i).locator('.rz-event-content').allInnerTexts();
    const logged = [];
    for (const text of contents) {
      const separatorIndex = text.indexOf(' | ');
      if (separatorIndex === -1) continue; // unlogged calendar-only item
      logged.push({
        projectLabel: text.slice(0, separatorIndex).trim(),
        note: text.slice(separatorIndex + 3).trim(),
      });
    }
    byDate[dateISO] = logged;
  }
  return byDate;
}
