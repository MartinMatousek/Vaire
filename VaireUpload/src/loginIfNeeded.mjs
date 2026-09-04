// If the given page is sitting on the login flow, optionally fills it from
// a 1Password item via the `op` CLI's biometric-gated per-call mode — never
// `op signin`, never a service-account token, so no plaintext credential is
// ever stored by Vaire. Clearing MFA (if presented) is always left to the
// user; this never attempts to handle it.
//
// The real flow (confirmed live 2026-09-03, NOT plain Keycloak as first
// assumed): the timesheet's Keycloak realm brokers to Microsoft Entra ID
// (Azure AD) for "Pracovníci Trask (trask email)" accounts:
//   1. id.trask.cz — an IdP picker: "Pracovníci Trask (trask email)" vs
//      "Externí uživatelé (personal email)". No inputs on this step.
//   2. login.microsoftonline.com — EITHER a remembered-account picker
//      (click the account tile, e.g. "mmatousek@trask.cz") OR a fresh
//      "loginfmt" email field (if no account is remembered / "Use another
//      account" was chosen) — both converge on...
//   3. login.microsoftonline.com — a password step: input#i0118
//      name="passwd", submit button#idSIButton9.
// Beyond the password step, Microsoft presents an Authenticator app PUSH
// approval (confirmed live 2026-09-03) — no code to type, no field to
// fill. This is always left to the user to approve on their phone; there
// is deliberately no TOTP-fill logic here (tried once, reverted — this
// account's MFA has no code-entry step for it to ever match).
//
// 1Password autofill is opt-in: the caller passes `onePasswordItemId` only
// when the user has enabled it in Settings and chosen an item. When it's
// null/undefined, a login page is reported as-is for the user to handle by
// hand in the Chrome window.
//
// Detection below matches the IdP picker's own rendered text rather than
// hardcoding its domain (id.trask.cz) — Vaire only knows the timesheet's
// configured root URL (Settings), not the identity-provider subdomain it
// redirects to, and a text/element check works the same regardless.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

// A prefix match, not the full "Pracovníci Trask" text, so this keeps
// matching if the account-tile suffix ever changes (e.g. a different
// domain in parentheses) — the picker's own wording ("Pracovníci ...") is
// the stable part.
const TIMESHEET_IDP_PICKER_TEXT = 'Pracovníci';
const MS_EMAIL_INPUT_SELECTOR = 'input[name="loginfmt"]';
const MS_PASSWORD_INPUT_SELECTOR = 'input[name="passwd"]';
const MS_SUBMIT_SELECTOR = '#idSIButton9';

/**
 * Detects "on the IdP picker" or "on Microsoft's login page" without
 * relying on the picker's own domain (id.trask.cz) — a URL Vaire has no
 * reason to know or hardcode, since only the timesheet's own root URL
 * (my.trask.cz) is configured in Settings. `login.microsoftonline.com` is
 * kept as a literal check since that's Microsoft's own domain, not the
 * timesheet's — any Keycloak realm brokering to Entra ID redirects there.
 */
async function isOnAnyLoginPage(page) {
  if (page.url().includes('login.microsoftonline.com')) return true;
  const picker = page.getByText(TIMESHEET_IDP_PICKER_TEXT, { exact: false });
  return (await picker.count().catch(() => 0)) > 0;
}

/**
 * Fetches a Login item's username/password from 1Password via `op`.
 * Deliberately uses `--format json` and reads the `fields` array rather
 * than the plain `--fields username,password` form, which comma-joins its
 * output and would misparse a value that itself contains a comma.
 */
async function fetchOnePasswordCredential(itemId) {
  let stdout;
  try {
    ({ stdout } = await execFileAsync('op', ['item', 'get', itemId, '--format', 'json']));
  } catch (error) {
    throw new Error(
      `Could not fetch 1Password item ${itemId}. Confirm the op CLI is installed ` +
      '(brew install --cask 1password-cli) and "Integrate with 1Password CLI" is enabled ' +
      `in 1Password.app > Settings > Developer. Original error: ${error.message}`
    );
  }

  let item;
  try {
    item = JSON.parse(stdout);
  } catch {
    throw new Error('op item get returned output that was not valid JSON.');
  }

  const fields = item.fields ?? [];
  const username = fields.find((f) => f.id === 'username')?.value;
  const password = fields.find((f) => f.id === 'password')?.value;
  if (!username || !password) {
    throw new Error(`1Password item ${itemId} is missing a username or password field.`);
  }
  return { username, password };
}

/**
 * Clicks through the Keycloak identity-provider picker if present. A no-op
 * if the page has already moved past it (e.g. resumed mid-flow).
 */
async function passIdpPickerIfPresent(page) {
  const link = page.getByText(TIMESHEET_IDP_PICKER_TEXT, { exact: false });
  if (await link.count() > 0) {
    await link.first().click();
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
  }
}

/**
 * Handles the Microsoft step(s): a remembered-account tile, or a fresh
 * email field, then the password field — submitting after each. Returns
 * once no more of these fields are visible (either fully through, or MFA
 * is now showing and this function has done all it can).
 *
 * Every step explicitly waits for its target to actually be present before
 * acting, and verifies a fill actually held before submitting, rather than
 * a bare `count() > 0` check right after a click — belt-and-suspenders
 * against a page that hasn't finished navigating yet. (What first looked
 * live like this racing — a loop back to the password screen — turned out
 * to actually be the push-MFA approval screen being misread; login itself
 * was working correctly. Kept these waits anyway since they're strictly
 * safer than the bare count check they replaced.)
 */
async function fillMicrosoftLogin(page, username, password) {
  // A single point-in-time URL check here is unsafe: clicking the IdP
  // picker link starts a multi-hop redirect (timesheet -> Keycloak ->
  // Microsoft) that isn't guaranteed to have landed on
  // login.microsoftonline.com by the time `networkidle` resolves in the
  // caller. A bug found live (2026-09-03): on a fresh profile with no
  // remembered Microsoft session, this check ran while the page was still
  // mid-redirect, saw a non-Microsoft URL, and returned immediately doing
  // nothing — the flow then stalled and Keycloak reset back to the IdP
  // picker on the next interaction. Wait for the URL to actually arrive.
  try {
    await page.waitForURL((url) => url.href.includes('login.microsoftonline.com'), { timeout: 10000 });
  } catch {
    return; // never reached Microsoft — nothing this function can do
  }

  // Remembered-account tile takes priority — its text is the account email
  // itself, so match on the known username rather than a generic selector.
  const accountTile = page.getByText(username, { exact: false });
  const hasAccountTile = await accountTile.first().waitFor({ state: 'visible', timeout: 5000 }).then(() => true).catch(() => false);

  if (hasAccountTile) {
    await accountTile.first().click();
  } else {
    const emailInput = page.locator(MS_EMAIL_INPUT_SELECTOR);
    const hasEmailInput = await emailInput.waitFor({ state: 'visible', timeout: 5000 }).then(() => true).catch(() => false);
    if (hasEmailInput) {
      await emailInput.fill(username);
      const filledValue = await emailInput.inputValue();
      if (filledValue !== username) {
        throw new Error('Email field did not hold the filled value — aborting rather than submitting a blank/wrong field.');
      }
      await page.locator(MS_SUBMIT_SELECTOR).click();
    } else {
      return; // neither a tile nor an email field showed up — nothing this function can do
    }
  }

  const passwordInput = page.locator(MS_PASSWORD_INPUT_SELECTOR);
  const hasPasswordInput = await passwordInput.waitFor({ state: 'visible', timeout: 10000 }).then(() => true).catch(() => false);
  if (!hasPasswordInput) return; // e.g. straight through via SSO with no password step at all

  await passwordInput.fill(password);
  const filledPassword = await passwordInput.inputValue();
  if (filledPassword !== password) {
    throw new Error('Password field did not hold the filled value — aborting rather than submitting a blank/wrong field.');
  }
  await page.locator(MS_SUBMIT_SELECTOR).click();
  await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
}

/**
 * Returns one of:
 *   { status: 'not-on-login-page' }         — nothing to do, caller proceeds
 *   { status: 'filled' }                    — credentials submitted, caller should re-check the URL
 *   { status: 'skipped-autofill-disabled' } — on a login page, but autofill wasn't requested
 *   { status: 'awaiting-2fa' }              — filled, but still on a login/MFA page
 */
export async function loginIfNeeded(page, onePasswordItemId) {
  if (!(await isOnAnyLoginPage(page))) {
    return { status: 'not-on-login-page' };
  }

  if (!onePasswordItemId) {
    return { status: 'skipped-autofill-disabled' };
  }

  const { username, password } = await fetchOnePasswordCredential(onePasswordItemId);

  await passIdpPickerIfPresent(page);
  await fillMicrosoftLogin(page, username, password);

  if (await isOnAnyLoginPage(page)) {
    return { status: 'awaiting-2fa' };
  }
  return { status: 'filled' };
}
