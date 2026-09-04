// Long-lived timesheet automation server for one upload session. VaireApp
// spawns exactly one of these per upload (UploadFlowView), keeps it alive
// across ensureReady + checkExistingEntries + every fillEntry call in the
// batch, and kills it when the upload ends — replacing the old pattern of
// spawning a fresh node+Playwright process (with a fresh CDP connect) for
// every single call, which was the source of a long pause after every
// logged entry.
//
// Protocol: newline-delimited JSON on stdin/stdout, one request per line in,
// one response per line out, correlated by an opaque `id` the caller
// assigns and this script echoes back unchanged.
//
//   Request:  {"id": "1", "op": "ensureReady", "args": {"onePasswordItemId": "..."}}
//             {"id": "2", "op": "checkExistingEntries", "args": {}}
//             {"id": "3", "op": "fillEntry", "args": {...same shape as fillEntry.mjs's entry JSON...}}
//             {"id": "4", "op": "shutdown", "args": {}}
//   Response: {"id": "1", "ok": true, "result": {"status": "ready"}}
//             {"id": "2", "ok": true, "result": {"2026-09-01": [{"projectLabel":"...","note":"..."}]}}
//             {"id": "3", "ok": false, "error": "human-readable message"}
//
// `error` is always the plain message string — the same text the
// corresponding one-shot script would have written to stderr — so
// VaireApp's existing user-facing error surfacing needs no changes.
//
// stdout is reserved EXCLUSIVELY for one-JSON-object-per-line protocol
// responses. Any diagnostic/log output this script wants to emit must go to
// stderr — never add a console.log here. The reader on the Swift side also
// defensively ignores any stdout line that isn't valid JSON with a
// recognized `id`, as a safety net against stray output from a dependency.
//
// A single request's failure must never crash the process or block
// subsequent requests — every op is wrapped in its own try/catch. Only a
// genuine startup failure (Chrome won't launch, no timesheet tab found) or
// an unhandled exception outside the per-request handling exits the
// process.
import readline from 'node:readline';
import { ensureTimesheetTab, recoverFromStaleConnection, findExistingLoggedEntries, runFillEntry } from './attach.mjs';
import { loginIfNeeded } from './loginIfNeeded.mjs';

function writeResponse(response) {
  process.stdout.write(JSON.stringify(response) + '\n');
}

function mapLoginStatus(result) {
  switch (result.status) {
    case 'not-on-login-page':
    case 'filled':
      return { status: 'ready' };
    case 'awaiting-2fa':
      return { status: 'awaiting-2fa' };
    case 'skipped-autofill-disabled':
      return { status: 'login-required' };
    default:
      throw new Error(`Unexpected loginIfNeeded status: ${result.status}`);
  }
}

async function main() {
  let page;
  let browser;
  try {
    ({ browser, page } = await ensureTimesheetTab());
  } catch (error) {
    writeResponse({ id: null, ok: false, error: error.message });
    process.exit(1);
  }

  process.on('unhandledRejection', (error) => {
    process.stderr.write(`Unhandled rejection: ${error?.message ?? error}\n`);
    process.exit(1);
  });
  process.on('uncaughtException', (error) => {
    process.stderr.write(`Uncaught exception: ${error?.message ?? error}\n`);
    process.exit(1);
  });

  const rl = readline.createInterface({ input: process.stdin, terminal: false });

  rl.on('line', async (line) => {
    let request;
    try {
      request = JSON.parse(line);
    } catch (error) {
      process.stderr.write(`Ignoring malformed request line: ${error.message}\n`);
      return;
    }

    const { id, op, args } = request;
    try {
      let result;
      switch (op) {
        case 'ensureReady': {
          await recoverFromStaleConnection(page);
          result = mapLoginStatus(await loginIfNeeded(page, args?.onePasswordItemId ?? null));
          break;
        }
        case 'checkExistingEntries': {
          await recoverFromStaleConnection(page);
          result = await findExistingLoggedEntries(page);
          break;
        }
        case 'fillEntry': {
          await recoverFromStaleConnection(page);
          await runFillEntry(page, args);
          result = { status: 'ready' };
          break;
        }
        case 'shutdown': {
          writeResponse({ id, ok: true, result: { status: 'shutting-down' } });
          await browser.close(); // detaches only, browser window stays open
          process.exit(0);
        }
        default:
          throw new Error(`Unknown op "${op}"`);
      }
      writeResponse({ id, ok: true, result });
    } catch (error) {
      writeResponse({ id, ok: false, error: error.message });
    }
  });
}

main();
