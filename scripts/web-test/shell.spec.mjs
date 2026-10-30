// Tier A — the gh-pages shell, characterized against the EXACT bytes CI
// ships (index.html extracted from release.yml by the runner). Fixture wasm
// is a dummy module; a real Go exit-helper drives the exit/relaunch path.
// Journey map: research/web_hardening_2026-10.md §2 J1–J7.
//
// Shell state transitions are faster than any poll, so every page gets a
// DOM-history recorder (window.__ucLog) and assertions run against the
// recorded sequence, not the live DOM. wait conditions are DATA (plain
// objects), never functions — puppeteer does not reliably call functions
// passed as waitForFunction args.
//
// NOTE: s1→s4 chain in one shared browser context on purpose — they pin the
// first-visit → revalidation → deploy → failure sequence against shared rev
// state. Do not reorder. Fixture-mutating tests restore state in finally.
import { join } from "node:path";
import { readFileSync, writeFileSync, copyFileSync, appendFileSync } from "node:fs";

const RECORDER = () => {
  window.__ucLog = [];
  const rec = () => {
    window.__ucLog.push({
      t: Date.now(),
      status: (document.querySelector("#status") || {}).textContent || "",
      detail: (document.querySelector("#detail") || {}).textContent || "",
      fill: (document.querySelector("#fill") || {}).style
        ? document.querySelector("#fill").style.width + " " + document.querySelector("#fill").className
        : "",
    });
  };
  const obs = new MutationObserver(rec);
  const start = () => {
    obs.observe(document.body, { subtree: true, childList: true, characterData: true });
    rec();
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
};

export async function suite(t, ctx) {
  const { server, fixtures, goRoot } = ctx;

  // OBS_COUNTER patches MutationObserver with a subclass that counts
  // live (observed-but-not-disconnected) instances in window.__obsActive —
  // s14's proof that the shell disconnects stale boot observers (R6).
  const OBS_COUNTER = () => {
    const Orig = MutationObserver;
    let active = 0;
    class CountingMO extends Orig {
      observe(target, options) {
        super.observe(target, options);
        active++;
      }
      disconnect() {
        super.disconnect();
        if (!this._ucDisc) {
          active--;
          this._ucDisc = true;
        }
      }
    }
    window.MutationObserver = CountingMO;
    window.__obsActive = () => active;
  };

  const freshPage = async (opts = {}) => {
    const context = opts.isolated ? await ctx.browser.createBrowserContext() : null;
    const page = context ? await context.newPage() : await ctx.browser.newPage();
    page._ucContext = context;
    if (opts.countObservers) await page.evaluateOnNewDocument(OBS_COUNTER);
    await page.evaluateOnNewDocument(RECORDER);
    const errors = [];
    page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
    page.on("console", (m) => {
      if (m.type() === "error") errors.push(`console: ${m.text()}`);
    });
    const requests = [];
    page._ucIntercept = { abort: [] };
    if (!opts.noIntercept) {
      await page.setRequestInterception(true);
      page.on("request", (r) => {
        const u = r.url();
        requests.push(u);
        if (page._ucIntercept.abort.some((pat) => u.includes(pat))) {
          r.abort("failed").catch(() => {});
        } else {
          r.continue().catch(() => {});
        }
      });
    }
    page._ucErrors = errors;
    page._ucRequests = requests;
    if (opts.viewport) await page.setViewport(opts.viewport);
    return page;
  };

  const closePage = async (page) => {
    if (page._ucContext) await page._ucContext.close();
    else await page.close();
  };

  const boot = (page) => page.goto(server.url + "/", { waitUntil: "domcontentloaded" });

  const detailText = (page) => page.$eval("#detail", (el) => el.textContent);
  const retryVisible = (page) => page.$eval("#retry", (el) => getComputedStyle(el).display !== "none");

  const attachCanvas = (page) =>
    page.evaluate(() => {
      const c = document.createElement("canvas");
      c.width = 100;
      c.height = 100;
      document.body.appendChild(c);
    });

  // cond (plain object, all fields optional): {status, detail, detailRe, det,
  // after, count} — count requires that many MATCHING records in history
  // (boots repeat states; a unique detail is not always available).
  const waitRec = async (page, cond, what, timeout = 10000) => {
    await page
      .waitForFunction(
        (c) => {
          const matches = (window.__ucLog || []).filter((r) => {
            if (c.status && r.status !== c.status) return false;
            if (c.detail && !r.detail.includes(c.detail)) return false;
            if (c.detailRe && !new RegExp(c.detailRe).test(r.detail)) return false;
            if (c.det !== undefined) {
              if (!r.fill || r.fill.includes("indet")) return false;
              if (!(parseFloat(r.fill) > c.det)) return false;
            }
            if (c.after && !(r.t > c.after)) return false;
            return true;
          });
          return matches.length >= (c.count || 1);
        },
        { timeout, polling: 50 },
        cond,
      )
      .catch(async (e) => {
        if (process.env.UC_DEBUG) {
          const log = await page.evaluate(() => window.__ucLog || []).catch(() => "evaluate failed");
          console.error(`[debug] cond for "${what}":`, JSON.stringify(cond));
          console.error(`[debug] __ucLog for "${what}":`, JSON.stringify(log).slice(-1200));
        }
        throw new Error(`${what}: ${e.message}`);
      });
  };

  const waitOverlayHidden = (page, what, timeout = 5000) =>
    page
      .waitForFunction(() => document.querySelector("#boot").style.display === "none", { timeout, polling: 50 })
      .catch((e) => {
        throw new Error(`${what}: ${e.message}`);
      });

  const setFixtureWasm = (name) =>
    copyFileSync(join(fixtures, name), join(fixtures, "uniclient.wasm"));

  // ── s1: first visit — determinate progress, MB counter, "downloaded",
  //        rev keys stored, overlay hides on canvas attach (J1).
  await t("s1 first visit: progress + downloaded + overlay hide", async (a) => {
    await server.note();
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { det: 0 }, "determinate progress bar");
      await waitRec(page, { detailRe: "MB / .*MB" }, "MB counter during download");
      await waitRec(page, { detail: "downloaded" }, "downloaded readout");
      await waitRec(page, { status: "Starting Uniclient…" }, "status before instantiation");
      const keys = await page.evaluate(() => [
        localStorage.getItem("uniclient.wasm.rev"),
        localStorage.getItem("uniclient.js.rev"),
      ]);
      a.ok(keys[0] && keys[1], "rev etags stored");
      await attachCanvas(page);
      await waitOverlayHidden(page, "overlay hides");
    } finally {
      await closePage(page);
    }
  });

  // ── s2: repeat visit — ETag revalidation, 304, "up to date" (J2).
  await t("s2 reload: up to date + HTTP 304", async (a) => {
    const page = await freshPage();
    try {
      await server.note();
      await boot(page);
      await waitRec(page, { detail: "up to date" }, "up to date readout");
      const log = await server.note();
      const wasmReqs = log.filter((r) => r.path.endsWith("uniclient.wasm"));
      a.ok(wasmReqs.some((r) => r.status === 304), `wasm revalidated with 304 (${JSON.stringify(wasmReqs)})`);
      a.ok(!wasmReqs.some((r) => r.status === 200), "no full redownload");
    } finally {
      await closePage(page);
    }
  });

  // ── s3: deploy changed both assets — "updated" readouts, wasm_exec.js
  //        refresh injected over the static copy (J3).
  await t("s3 changed deploy: updated readout + wasm_exec.js reinjection", async (a) => {
    writeFileSync(
      join(fixtures, "uniclient.wasm"),
      Buffer.concat([readFileSync(join(fixtures, "dummy.wasm")).subarray(0, 8), Buffer.alloc(2_000_000, 0x43)]),
    );
    appendFileSync(join(fixtures, "wasm_exec.js"), "\nwindow.__wasmExecRefreshed = true;\n");
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { detail: "updated" }, "updated readout");
      await waitRec(page, { detail: "js: updated" }, "js updated readout", 5000);
      await page.waitForFunction(() => window.__wasmExecRefreshed === true, { timeout: 5000, polling: 50 });
    } finally {
      await closePage(page);
      writeFileSync(join(fixtures, "wasm_exec.js"), readFileSync(join(goRoot, "lib", "wasm", "wasm_exec.js")));
      setFixtureWasm("dummy.wasm");
    }
  });

  // ── s4: wasm 404 — stopped + Retry; retry with rapid double-click boots
  //        exactly once (J6 + double-submit).
  await t("s4 wasm 404: stopped + retry, single concurrent boot", async (a) => {
    const page = await freshPage();
    await server.arm404("uniclient.wasm");
    try {
      await boot(page);
      await waitRec(page, { status: "Uniclient stopped" }, "stopped status");
      a.ok(/HTTP 404/.test(await detailText(page)), "error names the failing asset");
      a.ok(await retryVisible(page), "retry visible");
      await server.reset();
      await server.note();
      await page.$eval("#retry", (el) => el.click());
      await page.$eval("#retry", (el) => el.click());
      await page.$eval("#retry", (el) => el.click());
      await waitRec(page, { status: "Starting Uniclient…" }, "retry boots", 15000);
      const log = await server.note();
      const boots = log.filter((r) => r.path.endsWith("wasm_exec.js") || r.path.endsWith("uniclient.wasm"));
      a.eq(boots.length, 2, `exactly one boot after rapid retry clicks (got ${JSON.stringify(boots)})`);
    } finally {
      await server.reset();
      await closePage(page);
    }
  });

  // ── s5: wasm network fetch fails with a fresh cache copy — offline
  //        force-cache fallback boots anyway (J6 offline leg). The failure
  //        is injected SERVER-side (socket destroy) because puppeteer's
  //        request interception bypasses Chrome's HTTP cache, which would
  //        make the force-cache leg hit the network too.
  await t("s5 offline fetch failure: force-cache fallback", async (a) => {
    const page = await freshPage({ noIntercept: true });
    try {
      await boot(page);
      await waitRec(page, { detail: "up to date" }, "primed cache");
      await server.armNetfail("uniclient.wasm");
      await page.reload({ waitUntil: "domcontentloaded" });
      await waitRec(page, { detail: "offline" }, "offline fallback message");
      await waitRec(page, { status: "Starting Uniclient…" }, "boots from cached copy", 15000);
    } finally {
      await server.reset();
      await closePage(page);
    }
  });

  // ── s6: real Go module that exits — "Uniclient exited" + Retry relaunch
  //        proven by server request count (J7).
  await t("s6 exit + relaunch journey", async (a) => {
    if (!ctx.haveExitHelper) a.skip("exit-helper wasm not built");
    setFixtureWasm("exit-helper.wasm");
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { status: "Uniclient stopped", detail: "Uniclient exited" }, "stopped after exit", 20000);
      a.ok(await retryVisible(page), "retry offered");
      await server.note();
      const tClick = Date.now();
      await page.$eval("#retry", (el) => el.click());
      await waitRec(
        page,
        { status: "Uniclient stopped", detail: "Uniclient exited", after: tClick },
        "relaunch exits again after the click",
        20000,
      );
      await new Promise((r) => setTimeout(r, 300));
      const log = await server.note();
      const reqs = log.filter((r) => r.path.endsWith(".wasm") || r.path.endsWith("wasm_exec.js"));
      a.eq(reqs.length, 2, `relaunch fetched js+wasm exactly once (got ${JSON.stringify(reqs)})`);
    } finally {
      await closePage(page);
      setFixtureWasm("dummy.wasm");
    }
  });

  // ── s7: localStorage unavailable — rev storage degrades silently (J1 var).
  await t("s7 no localStorage: shell still boots", async (a) => {
    const page = await freshPage();
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(window, "localStorage", {
        get() {
          throw new DOMException("denied", "SecurityError");
        },
      });
    });
    try {
      await boot(page);
      await waitRec(page, { status: "Starting Uniclient…" }, "boots without rev storage");
      a.ok(
        page._ucErrors.filter((e) => /SecurityError|denied/.test(e)).length === 0,
        "storage errors swallowed, not surfaced",
      );
    } finally {
      await closePage(page);
    }
  });

  // ── s8: refresh mid-download — no wedged state, second load completes.
  await t("s8 refresh mid-download", async (a) => {
    writeFileSync(
      join(fixtures, "uniclient.wasm"),
      Buffer.concat([readFileSync(join(fixtures, "dummy.wasm")).subarray(0, 8), Buffer.alloc(8_000_000, 0x44)]),
    );
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { det: 2 }, "download in progress");
      await page.reload({ waitUntil: "domcontentloaded" });
      await waitRec(page, { detail: "updated" }, "second load completes", 20000);
    } finally {
      await closePage(page);
      setFixtureWasm("dummy.wasm");
    }
  });

  // ── s9: mobile viewport — overlay sane, bar within bounds (J1 mobile).
  await t("s9 mobile viewport boot overlay", async (a) => {
    const page = await freshPage({ viewport: { width: 375, height: 812, isMobile: true } });
    try {
      await boot(page);
      await waitRec(page, { fill: "" }, "overlay present");
      const bar = await page.$eval("#bar", (el) => el.getBoundingClientRect().width);
      a.ok(bar <= 375, `bar fits viewport (${bar}px)`);
      await waitRec(page, { status: "Starting Uniclient…" }, "completes on mobile layout");
      await attachCanvas(page);
      await waitOverlayHidden(page, "overlay hides");
    } finally {
      await closePage(page);
    }
  });

  // ── s10: both wasm_exec.js sources fail — honest load error + retry.
  //         Isolated context: the shared browser context would serve the
  //         static <script src> from its HTTP cache and mask the failure.
  await t("s10 wasm_exec.js missing: honest failure", async (a) => {
    const page = await freshPage({ isolated: true });
    await server.arm404("wasm_exec.js");
    try {
      await boot(page);
      await waitRec(page, { status: "Uniclient stopped" }, "stopped", 15000);
      await waitRec(page, { detail: "wasm_exec.js failed to load" }, "names wasm_exec.js", 5000);
    } finally {
      await server.reset();
      await closePage(page);
    }
  });

  // ── s11: back/forward navigation re-runs the shell cleanly.
  await t("s11 back-button re-navigation", async (a) => {
    setFixtureWasm("exit-helper.wasm");
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { status: "Uniclient stopped" }, "stopped", 20000);
      await page.goto("about:blank");
      await page.goBack({ waitUntil: "domcontentloaded" });
      await waitRec(page, { status: "Uniclient stopped" }, "returns and boots again", 20000);
    } finally {
      await closePage(page);
      setFixtureWasm("dummy.wasm");
    }
  });

  // ── s13: after the canvas attached and the overlay hid, a late wasm
  //        panic / uncaught script error must surface — overlay back with
  //        the error and a Retry, never a dead silent page (risk R5).
  await t("s13 late crash re-shows the overlay with a retry (R5)", async (a) => {
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { status: "Starting Uniclient…" }, "booted");
      await attachCanvas(page);
      await waitOverlayHidden(page, "overlay hidden on canvas attach");
      // synth windows-error AFTER boot. Throwing through an inline
      // <script> keeps the message same-origin — puppeteer's evaluate
      // context is treated as cross-origin and masks it as
      // "Script error.".
      await page.evaluate(() => {
        const s = document.createElement("script");
        s.textContent = "setTimeout(function () { throw new Error('synthetic late crash'); }, 0);";
        document.head.appendChild(s);
      });
      await waitRec(page, { status: "Uniclient stopped", detail: "synthetic late crash" },
        "uncaught error surfaces as stopped + retry", 8000);
      a.ok(await retryVisible(page), "retry visible after late crash");
      // unhandled rejection leg — same surface, same inline-script vector
      // (puppeteer's evaluate absorbs the rejection there).
      await page.evaluate(() => {
        const s = document.createElement("script");
        s.textContent = "Promise.reject(new Error('synthetic rejection'));";
        document.head.appendChild(s);
      });
      await waitRec(page, { status: "Uniclient stopped", detail: "synthetic rejection" },
        "unhandled rejection surfaces", 8000);
    } finally {
      await closePage(page);
    }
  });

  // ── s14: failed boots must not stack connected MutationObservers (R6).
  //        The shell's boot observer hides the overlay on canvas attach —
  //        every failed boot used to leave one connected forever (self-
  //        healing at first success, but a leak while failing). Counted
  //        via a patched MutationObserver: a retry boot must not grow the
  //        live count.
  await t("s14 failed boots do not stack boot observers (R6)", async (a) => {
    // A boot that reaches the wasm stage (dummy module: instantiate fails
    // AFTER the boot observer exists) and stops — then a retry boot. The
    // failed boot's observer must not survive into the next boot.
    const page = await freshPage({ countObservers: true });
    try {
      await boot(page);
      await waitRec(page, { status: "Uniclient stopped", detail: "WebAssembly.instantiate" },
        "first boot reaches the observer stage and stops", 20000);
      const active1 = await page.evaluate(() => window.__obsActive());
      await page.$eval("#retry", (el) => el.click());
      // Measure at the retry's SECOND stop — boots repeat states, so the
      // wait requires TWO stop records (retry's observer exists by then).
      await waitRec(page, { status: "Uniclient stopped", detail: "WebAssembly.instantiate()", count: 2 },
        "retry reaches its own observer and stops", 20000);
      const active2 = await page.evaluate(() => window.__obsActive());
      a.ok(active2 <= active1, `retry boot grew live observers: ${active1} -> ${active2} (R6: failed boot's observer never disconnected)`);
    } finally {
      await closePage(page);
    }
  });

  // ── s15: boot overlay accessibility — screen readers get the boot state
  //        (live region) and a JavaScript-disabled page explains itself.
  await t("s15 overlay a11y: live region + noscript fallback", async (a) => {
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { detailRe: "MB" }, "booted");
      const aria = await page.evaluate(() => {
        const st = document.querySelector("#status");
        return {
          role: st.getAttribute("role"),
          live: st.getAttribute("aria-live"),
          noscript: !!document.querySelector("noscript"),
          noscriptText: (document.querySelector("noscript") || {}).textContent || "",
        };
      });
      a.eq(aria.role, "status", "#status must be a live region (role=status)");
      a.eq(aria.live, "polite", "#status must announce politely (aria-live=polite)");
      a.ok(aria.noscript, "a <noscript> fallback must exist");
      a.ok(aria.noscriptText.trim().length > 10, "noscript must explain that JavaScript is required");
    } finally {
      await closePage(page);
    }
  });

  // ── s12: same-origin only — no external/API calls anywhere.
  await t("s12 network surface is same-origin only", async (a) => {
    const page = await freshPage();
    try {
      await boot(page);
      await waitRec(page, { status: "Starting Uniclient…" }, "settled");
      const foreign = page._ucRequests.filter(
        (u) => !u.startsWith(server.url + "/") && !u.startsWith("data:"),
      );
      a.eq(foreign.length, 0, `foreign requests: ${foreign.join(", ")}`);
    } finally {
      await closePage(page);
    }
  });
}
