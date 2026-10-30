// Tier B — the real app (dist/uniclient.wasm) in headless Chrome.
// Boots the actual Gio GUI, pins the welcome → picker → auth-form journey,
// mobile viewport, single- and two-tab vault persistence, and console
// cleanliness. Two-tab clobbering is pinned as KNOWN BEHAVIOR (risk R1,
// research/web_hardening_2026-10.md §3) — Phase 2 flips the expectation.
//
// One browser PER TEST: the 88 MB module plus its heap survive page close
// for a while, and a shared browser wedges under 4 GB sandboxes.
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { decryptVault, accountCount } from "./vault-crypto.mjs";

// Click targets are CALIBRATED against the current app at 1280x800 canvas
// space (the CI gui-smoke's 559,445 is Xvfb-window-relative, ~80px left
// and ~37px up of canvas space). The welcome CTA blue button center is
// (639, 482); the Telegram card center in the picker grid is (396, 215).
const CLICK_CTA = { x: 639, y: 482 };
const CLICK_CARD = { x: 396, y: 215 };
const VIEW = { width: 1280, height: 800 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pngDiff(ctx, a, b) {
  const { PNG } = ctx.pngjs;
  const pa = PNG.sync.read(a);
  const pb = PNG.sync.read(b);
  if (pa.width !== pb.width || pa.height !== pb.height) return Number.POSITIVE_INFINITY;
  let diff = 0;
  for (let i = 0; i < pa.data.length; i += 4) {
    const d =
      Math.abs(pa.data[i] - pb.data[i]) +
      Math.abs(pa.data[i + 1] - pb.data[i + 1]) +
      Math.abs(pa.data[i + 2] - pb.data[i + 2]);
    if (d > 24) diff++;
  }
  return diff;
}

function pngVariance(ctx, buf) {
  const { PNG } = ctx.pngjs;
  const p = PNG.sync.read(buf);
  let mean = 0;
  const n = p.data.length / 4;
  const lum = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const j = i * 4;
    lum[i] = 0.2126 * p.data[j] + 0.7152 * p.data[j + 1] + 0.0722 * p.data[j + 2];
    mean += lum[i];
  }
  mean /= n;
  let v = 0;
  for (let i = 0; i < n; i++) v += (lum[i] - mean) ** 2;
  return v / n;
}

async function bootApp(page, url, timeout = 180000) {
  await page.goto(url + "/", { waitUntil: "domcontentloaded", timeout: 120000 });
  const start = Date.now();
  try {
    await page.waitForFunction(
      () => document.querySelector("canvas") && document.querySelector("#boot").style.display === "none",
      { timeout, polling: 250 },
    );
  } catch (e) {
    const st = await page.evaluate(() => ({
      status: document.querySelector("#status")?.textContent,
      detail: document.querySelector("#detail")?.textContent,
      canvas: !!document.querySelector("canvas"),
      overlay: document.querySelector("#boot")?.style.display,
    })).catch(() => "page gone");
    throw new Error(`boot did not finish: ${JSON.stringify(st)}`);
  }
  return Date.now() - start;
}

export async function suite(t, ctx) {
  const { server, fixtures, artifacts } = ctx;
  mkdirSync(artifacts, { recursive: true });
  const timings = [];

  const withBrowser = async (fn) => {
    const b = await ctx.launchBrowser();
    try {
      return await fn(b);
    } finally {
      await b.close();
    }
  };

  const newPage = (b, viewport = VIEW) =>
    (async () => {
      const page = await b.newPage();
      const errors = [];
      page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
      page.on("console", (m) => {
        if (m.type() === "error") errors.push(`console: ${m.text()}`);
      });
      page._ucErrors = errors;
      await page.setViewport(viewport);
      return page;
    })();

  let welcomeShot = null;

  // b1 — desktop boot: real app attaches canvas, overlay hides, GUI renders,
  // console stays clean (J1 with the real payload).
  await t("b1 real app boots: canvas + welcome + clean console", async (a) => {
    await withBrowser(async (b) => {
      const page = await newPage(b);
      const ms = await bootApp(page, server.url);
      timings.push({ what: "desktop boot (canvas attach)", ms });
      const canvas = await page.evaluate(() => {
        const c = document.querySelector("canvas");
        return c ? { w: c.clientWidth, h: c.clientHeight } : null;
      });
      a.ok(canvas && canvas.w > 0 && canvas.h > 0, "canvas attached with size");
      await sleep(2500);
      welcomeShot = await page.screenshot({ path: join(artifacts, "b1-welcome.png") });
      const v = pngVariance(ctx, welcomeShot);
      a.ok(v > 10, `welcome screen rendered (pixel variance ${v.toFixed(1)})`);
      a.eq(page._ucErrors.length, 0, `console errors: ${page._ucErrors.join(" | ")}`);
    });
  });

  // b2 — welcome CTA opens the backend picker (J4 step 1).
  await t("b2 CTA opens picker", async (a) => {
    await withBrowser(async (b) => {
      const page = await newPage(b);
      await bootApp(page, server.url);
      await sleep(2500);
      const before = await page.screenshot();
      await page.mouse.click(CLICK_CTA.x, CLICK_CTA.y);
      await sleep(1500);
      const after = await page.screenshot({ path: join(artifacts, "b2-picker.png") });
      const diff = pngDiff(ctx, before, after);
      a.ok(diff > 500, `picker appeared (pixel diff ${diff})`);
      a.eq(page._ucErrors.length, 0, `console errors: ${page._ucErrors.join(" | ")}`);
    });
  });

  // b3 — first card opens the auth flow (J4 step 2; Telegram phone form).
  await t("b3 picker card opens auth form", async (a) => {
    await withBrowser(async (b) => {
      const page = await newPage(b);
      await bootApp(page, server.url);
      await sleep(2500);
      await page.mouse.click(CLICK_CTA.x, CLICK_CTA.y);
      await sleep(1500);
      const before = await page.screenshot();
      await page.mouse.click(CLICK_CARD.x, CLICK_CARD.y);
      await sleep(2000);
      const after = await page.screenshot({ path: join(artifacts, "b3-authform.png") });
      const diff = pngDiff(ctx, before, after);
      a.ok(diff > 500, `auth form appeared (pixel diff ${diff})`);
    });
  });

  // b4 — mobile viewport boot (J1 mobile, real payload).
  await t("b4 mobile viewport boots the real app", async (a) => {
    await withBrowser(async (b) => {
      const page = await newPage(b, { width: 375, height: 812, isMobile: true, hasTouch: true });
      const ms = await bootApp(page, server.url);
      timings.push({ what: "mobile boot (canvas attach)", ms });
      await sleep(2000);
      const shot = await page.screenshot({ path: join(artifacts, "b4-mobile.png") });
      const v = pngVariance(ctx, shot);
      a.ok(v > 10, `mobile welcome rendered (variance ${v.toFixed(1)})`);
      a.eq(page._ucErrors.length, 0, `console errors: ${page._ucErrors.join(" | ")}`);
    });
  });

  // b5 — vault persistence single-tab: account survives a reload (J8).
  await t("b5 vault persists across reload (single tab)", async (a) => {
    await withBrowser(async (b) => {
      const vaultLen = (page) =>
        page.evaluate(() => (localStorage.getItem("uniclient.vault") || "").length);

      const page = await newPage(b);
      await bootApp(page, server.url);
      await sleep(2000);
      await page.mouse.click(CLICK_CTA.x, CLICK_CTA.y);
      await sleep(1500);
      await page.mouse.click(CLICK_CARD.x, CLICK_CARD.y);
      await sleep(2000); // AddAccount runs async: full-vault flush lands here
      await page.screenshot({ path: join(artifacts, "b5-tab1-added.png") });
      const L1 = await vaultLen(page);
      a.ok(L1 > 0, `vault persisted after add (${L1} bytes)`);

      await page.reload({ waitUntil: "domcontentloaded" });
      await bootApp(page, server.url);
      await sleep(2000);
      a.ok((await vaultLen(page)) > 0, "vault survives reload");
      const afterReload = await page.screenshot({ path: join(artifacts, "b5-tab1-reloaded.png") });
      a.ok(pngDiff(ctx, welcomeShot, afterReload) > 500, "reloaded tab shows the account, not the welcome CTA");
    });
  });

  // b6 — two tabs clobber the vault (KNOWN BEHAVIOR, risk R1 — pinned
  //      as-is; Phase 2 flips the expectation). Both tabs must boot BEFORE
  //      any account exists: a tab that starts with an account in the
  //      vault never shows the welcome CTA. The vault is DECRYPTED in the
  //      test (Argon2id+AES-GCM, same params as the app) so the assertion
  //      counts accounts exactly — no ciphertext-size guessing.
  await t("b6 two-tab vault clobber (KNOWN R1)", async (a) => {
    await withBrowser(async (b) => {
      const vaultRaw = (page) => page.evaluate(() => localStorage.getItem("uniclient.vault") || "");

      // The full-vault flush always rewrites the ciphertext (fresh nonce), so
      // "the vault string changed" is the deterministic flush signal — fixed
      // sleeps race under two-instance memory pressure.
      const waitForFlush = async (page, before, what) => {
        for (let i = 0; i < 20; i++) {
          const raw = await vaultRaw(page);
          if (raw && raw !== before) return raw;
          await sleep(1000);
        }
        throw new Error(`timed out waiting for vault flush: ${what}`);
      };

      const p1 = await newPage(b);
      const p2 = await newPage(b);
      await bootApp(p1, server.url);
      await bootApp(p2, server.url);
      await sleep(2000);

      const rawEmpty = await vaultRaw(p1);

      // Headless Chrome freezes hidden renderers (no rAF, queued input) under
      // memory pressure — each page must be fronted before it is driven.
      await p1.bringToFront();
      await p1.mouse.click(CLICK_CTA.x, CLICK_CTA.y);
      await sleep(1500);
      await p1.mouse.click(CLICK_CARD.x, CLICK_CARD.y);
      const raw1 = await waitForFlush(p1, rawEmpty, "tab1 add");
      const v1 = await decryptVault(raw1);
      const n1 = accountCount(v1);
      a.ok(n1 === 1, `tab1 vault holds its account (${n1})`);

      await p2.bringToFront();
      await p2.mouse.click(CLICK_CTA.x, CLICK_CTA.y);
      await sleep(1500);
      await p2.mouse.click(CLICK_CARD.x, CLICK_CARD.y);
      const raw2 = await waitForFlush(p2, raw1, "tab2 add");
      const v2 = await decryptVault(raw2);
      const n2 = accountCount(v2);

      // KNOWN BEHAVIOR (R1): tab2's flush rewrote the vault from its own
      // stale in-memory image, so the persisted vault holds ONE account —
      // tab1's is gone. Correct behavior: 2. Flip when R1 is fixed.
      a.ok(n2 === 1, `KNOWN R1 clobber: vault holds ${n2} account(s) after the second tab added (correct behavior: 2)`);
      writeFileSync(join(artifacts, "b6-vault-after-tab2.json"), JSON.stringify(v2, null, 2));
    });
  });

  writeFileSync(join(artifacts, "timings.json"), JSON.stringify(timings, null, 2));
  console.log("boot timings (ms):", JSON.stringify(timings));
}
