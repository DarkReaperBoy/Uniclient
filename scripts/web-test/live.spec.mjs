// Tier C (--live) — the deployed https://darkreaperboy.github.io/Uniclient/.
// Verifies the production bytes + delivery path end-to-end: revalidation
// fast path, canvas attach, GUI render, console cleanliness, mobile boot.
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function suite(t, ctx) {
  const { liveUrl, artifacts } = ctx;
  mkdirSync(artifacts, { recursive: true });
  const timings = [];

  // Production availability check: the tier must SKIP with a precise
  // reason when the site is down (e.g. GitHub Pages disabled by the
  // owner) instead of failing three boots against a 404 page.
  {
    const probe = await fetch(liveUrl, { redirect: "follow" }).catch((e) => null);
    if (!probe || !probe.ok) {
      const status = probe ? `HTTP ${probe.status}` : "unreachable";
      await t(`live tier: production site unavailable (${status})`, async (a) => {
        a.skip(`https://darkreaperboy.github.io/Uniclient/ answers ${status} — Pages serving is off (owner-controlled). Run again once the site is enabled.`);
      });
      return;
    }
  }

  const newPage = async (viewport) => {
    const page = await ctx.browser.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
    page.on("console", (m) => {
      if (m.type() === "error") errors.push(`console: ${m.text()}`);
    });
    page._ucErrors = errors;
    if (viewport) await page.setViewport(viewport);
    return page;
  };

  await t("l1 live desktop boot: canvas + GUI + clean console", async (a) => {
    const page = await newPage({ width: 1280, height: 800 });
    const start = Date.now();
    await page.goto(liveUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForFunction(
      () => document.querySelector("canvas") && document.querySelector("#boot").style.display === "none",
      { timeout: 300000, polling: 500 },
    );
    timings.push({ what: "live desktop boot (canvas attach)", ms: Date.now() - start });
    await sleep(3000);
    const shot = await page.screenshot({ path: join(artifacts, "l1-live-desktop.png") });
    a.ok(shot.length > 20000, `rendered (screenshot ${shot.length} bytes)`);
    a.eq(page._ucErrors.length, 0, `console errors: ${page._ucErrors.join(" | ")}`);
    await page.close();
  });

  await t("l2 live reload: up-to-date fast path", async (a) => {
    const page = await newPage({ width: 1280, height: 800 });
    await page.goto(liveUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    const start = Date.now();
    await page.waitForFunction(
      () => document.querySelector("#detail").textContent.includes("up to date"),
      { timeout: 300000, polling: 500 },
    );
    timings.push({ what: "live reload revalidation (up to date)", ms: Date.now() - start });
    a.ok(Date.now() - start < 60000, "revalidation was fast, no full redownload");
    await page.close();
  });

  await t("l3 live mobile boot", async (a) => {
    const page = await newPage({ width: 375, height: 812, isMobile: true, hasTouch: true });
    const start = Date.now();
    await page.goto(liveUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForFunction(
      () => document.querySelector("canvas") && document.querySelector("#boot").style.display === "none",
      { timeout: 300000, polling: 500 },
    );
    timings.push({ what: "live mobile boot (canvas attach)", ms: Date.now() - start });
    await page.screenshot({ path: join(artifacts, "l3-live-mobile.png") });
    await page.close();
  });

  writeFileSync(join(artifacts, "timings-live.json"), JSON.stringify(timings, null, 2));
  console.log("live timings (ms):", JSON.stringify(timings));
}
