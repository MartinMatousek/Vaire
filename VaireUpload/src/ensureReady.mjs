// Entry point VaireApp calls before an upload begins: launches the debug
// Chrome profile if needed, gets a my.trask.cz tab, and (if 1Password
// autofill is enabled) attempts to log in. Prints one JSON line describing
// the outcome so VaireApp can show a specific, correct message rather than
// a generic failure — never clicks past 2FA, never guesses.
//
// Usage: node src/ensureReady.mjs ['<onePasswordItemId>']
// Output (stdout, one JSON line):
//   { "status": "ready" }
//   { "status": "awaiting-2fa" }
//   { "status": "login-required" }   -- on login page, autofill disabled/unset
// Non-zero exit + stderr message on any failure (Chrome wouldn't launch,
// op CLI failure, etc).
import { ensureTimesheetTab } from './attach.mjs';
import { loginIfNeeded } from './loginIfNeeded.mjs';

async function main() {
  const onePasswordItemId = process.argv[2] || null;

  const { browser, page } = await ensureTimesheetTab();
  const result = await loginIfNeeded(page, onePasswordItemId);
  await browser.close(); // detaches only; the Chrome window stays open

  switch (result.status) {
    case 'not-on-login-page':
    case 'filled':
      process.stdout.write(JSON.stringify({ status: 'ready' }) + '\n');
      break;
    case 'awaiting-2fa':
      process.stdout.write(JSON.stringify({ status: 'awaiting-2fa' }) + '\n');
      break;
    case 'skipped-autofill-disabled':
      process.stdout.write(JSON.stringify({ status: 'login-required' }) + '\n');
      break;
    default:
      throw new Error(`Unexpected loginIfNeeded status: ${result.status}`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
