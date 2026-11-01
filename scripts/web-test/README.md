# Web E2E suite (puppeteer)

Puppeteer-driven end-to-end tests for the Uniclient web target — the
gh-pages shell and the real WASM app in headless Chrome. This is TEST-ONLY
infrastructure: nothing here ships, links, or runs in the product
(AGENTS.md §1.1 carve-out; the owner's "use puppeteer" mandate).

## What it covers

- **shell tier** (`shell.spec.mjs`) — the exact index.html bytes CI ships,
  extracted from the release.yml heredoc (never a drifting copy): progress
  bar + MB readout, ETag revalidation ("up to date"), deploy updates
  (wasm_exec.js reinjection), 404 → stopped/Retry with double-submit
  proof, offline force-cache fallback, exit/relaunch via a real Go helper
  module, no-localStorage, refresh mid-download, mobile overlay, missing
  wasm_exec.js, back-button, same-origin-only network surface.
- **app tier** (`app.spec.mjs`) — the real `dist/uniclient.wasm`: boot to
  canvas, welcome screen, CTA → picker → auth form, mobile viewport,
  single-tab vault persistence, and the two-tab vault merge (flush-time
  cross-instance merge keeps both accounts).
- **live tier** (`--live`) — the deployed https://darkreaperboy.github.io/
  Uniclient/ site.

## Run

```sh
make wasm                      # dist/uniclient.wasm (app tier needs it)
cd scripts/web-test
npm install                    # once; reuses ~/.cache/puppeteer browsers
node run.mjs                   # shell + app tiers
node run.mjs --only=shell      # one tier
node run.mjs --live            # deployed-site tier
```

Env: `UC_WASM` (real wasm path, default `dist/uniclient.wasm`),
`PORT` (test server port, default 8099), `SERVER_DELAY_MS` (inter-chunk
throttle; 15 keeps the progress bar testable, 0 = real timings),
`PUPPETEER_EXECUTABLE_PATH` (system Chrome in CI instead of a download),
`UC_DEBUG=1` (dumps the DOM-history log on wait failures).

`measure-boot.mjs` is the performance harness (boot phase segments +
JS-heap peak sampling) — run with `SERVER_DELAY_MS=0` for real numbers.
The live tier probes production first and SKIPS with a reason if the
site is down (e.g. Pages disabled by the owner).

Artifacts land in `artifacts/` (screenshots, boot timings, decrypted
vault dumps) — gitignored, kept for review.

## Notes for maintainers

- Shell state transitions are faster than any poll: pages install a
  DOM-history recorder (`window.__ucLog`) and waits assert on the recorded
  sequence. Wait conditions are plain objects — puppeteer does not
  reliably call functions passed as waitForFunction args.
- Click targets are calibrated in 1280x800 canvas space (CTA at 639,482;
  Telegram card at 396,215). The CI gui-smoke's 559,445 is Xvfb-window
  space — a different coordinate system, ~80px left / ~37px up.
- Multi-tab tests call `bringToFront()` before driving each page:
  headless Chrome freezes hidden renderers (no rAF, queued input).
- The offline leg injects failure SERVER-side (`/ctl/netfail` destroys
  the socket): puppeteer request interception bypasses Chrome's HTTP
  cache and would break the force-cache path.
- One browser per test: the 88 MB module's heap outlives page close and
  wedges small machines when tests share a browser.
