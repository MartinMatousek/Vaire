// Shared CDP-attach helper for the Trask automation scripts. Connects to a
// dedicated debug Chrome profile — never the user's regular Chrome — that
// Vaire launches itself on demand (ensureDebugChrome), so uploading never
// requires the user to run a shell command by hand. Credentials still never
// touch this codebase: login is either done by the user in that window, or
// (if enabled in Settings) via loginIfNeeded.mjs pulling from 1Password
// through the `op` CLI's biometric-gated per-call mode — no stored secret,
// no service-account token.
//
// A stale/expired CDP connection or a missing/wrong tab are both routine,
// expected failure modes here (the profile isn't running yet, Trask logged
// the session out, etc.) — every export throws a plain Error with an
// actionable message rather than letting a raw Playwright timeout surface,
// since VaireApp will show these messages to the user directly.
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
const PROFILE_DIR = path.join(os.homedir(), 'chrome-trask-debug');
const TRASK_URL = 'https://my.trask.cz/';

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
 * an open tab on my.trask.cz — navigating a fresh tab there if none exists
 * yet. This is the auto-launch entry point `ensureReady.mjs` uses; plain
 * `attachToTraskTab()` below stays as the "tab must already exist" variant
 * used by scripts that assume a prior successful ensureReady/login.
 */
export async function ensureTraskTab() {
  await ensureDebugChrome();
  const browser = await connectToDebugChrome();

  // Repeated runs (retried logins, repeated uploads) can leave more than
  // one my.trask.cz tab open — e.g. an old logged-out tab alongside a
  // freshly-logged-in one. Prefer the most recently opened match rather
  // than the first one found, and close the rest so they don't keep
  // accumulating or get picked up by mistake on a later run.
  const matches = [];
  for (const context of browser.contexts()) {
    for (const page of context.pages()) {
      if (page.url().includes('my.trask.cz')) {
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
    return { browser, page };
  }

  const context = browser.contexts()[0] ?? (await browser.newContext());
  const page = await context.newPage();
  await page.goto(TRASK_URL);
  return { browser, page };
}

/**
 * Finds the open my.trask.cz tab among the debug Chrome's windows. Throws a
 * clear, distinct message for "no such tab" vs. "tab is stuck on the
 * Keycloak login page" so the caller can show the right instruction.
 */
export async function findTraskPage(browser) {
  for (const context of browser.contexts()) {
    for (const page of context.pages()) {
      if (page.url().includes('my.trask.cz')) {
        if (page.url().includes('id.trask.cz') || page.url().includes('/auth/')) {
          throw new Error(
            'The my.trask.cz tab is showing the Keycloak login page. ' +
            'Log in (including 2FA) in that Chrome window, then try again.'
          );
        }
        return page;
      }
    }
  }
  throw new Error(
    'No open tab found on my.trask.cz in the debug Chrome window. ' +
    'Open https://my.trask.cz/ there and log in, then try again.'
  );
}

/**
 * Convenience wrapper: connect + find the tab + bring it to front, the
 * common case for every script here.
 */
export async function attachToTraskTab() {
  const browser = await connectToDebugChrome();
  const page = await findTraskPage(browser);
  await page.bringToFront();
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
 * Selecting by index is unsafe here: confirmed live against Trask's actual
 * Project dropdown that Radzen re-marks/reorders options after a selection,
 * which caused a stale-element timeout on the 2nd project when indexed by
 * position. Exact-label selection is the only implementation used anywhere
 * in this codebase — do not reintroduce index-based selection.
 */
export async function selectDropdownOption(page, dropdown, label) {
  await dropdown.click();
  const popup = page.locator('.rz-dropdown-panel:visible').first();
  await popup.waitFor({ state: 'visible', timeout: 5000 });
  await popup.getByRole('option', { name: label, exact: true }).click();
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
