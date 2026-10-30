import { copyFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, "fixtures");
copyFileSync(join(here, "..", "..", "dist", "uniclient.wasm"), join(fixtures, "uniclient.wasm"));

process.env.SERVER_DELAY_MS = "0";
const { startServer } = await import("./server.mjs");
const srv = await startServer(fixtures, 8099);
const p = (await import("puppeteer")).default;
const b = await p.launch({
  headless: true,
  protocolTimeout: 300000,
  args: ["--no-sandbox", "--disable-dev-shm-usage", "--enable-unsafe-swiftshader", "--js-flags=--max-old-space-size=2048"],
});
const pg = await b.newPage();
await pg.setViewport({ width: 1280, height: 800 });
await pg.evaluateOnNewDocument(() => {
  window.__peak = 0;
  setInterval(() => {
    if (performance.memory) window.__peak = Math.max(window.__peak, performance.memory.usedJSHeapSize);
  }, 50);
  window.__phases = { t0: performance.now(), fetchDone: 0, instStart: 0, instDur: 0, canvas: 0 };
  const origInstantiate = WebAssembly.instantiate;
  WebAssembly.instantiate = async function (bytes, imports) {
    window.__phases.fetchDone = performance.now() - window.__phases.t0;
    window.__phases.instStart = window.__phases.fetchDone;
    const s = performance.now();
    try {
      return await origInstantiate.call(WebAssembly, bytes, imports);
    } finally {
      window.__phases.instDur = performance.now() - s;
    }
  };
  const obs = new MutationObserver(() => {
    if (document.querySelector("canvas") && !window.__phases.canvas) {
      window.__phases.canvas = performance.now() - window.__phases.t0;
    }
  });
  document.addEventListener("DOMContentLoaded", () => obs.observe(document.body, { subtree: true, childList: true }));
});
await pg.goto("http://127.0.0.1:8099/", { waitUntil: "domcontentloaded", timeout: 60000 });
await pg.waitForFunction(
  () => document.querySelector("canvas") && document.querySelector("#boot").style.display === "none",
  { timeout: 180000, polling: 250 },
);
await new Promise((r) => setTimeout(r, 500));
const phases = await pg.evaluate(() => {
  const p = window.__phases;
  const goBoot = p.canvas - p.instStart - p.instDur; // engine init + first frame
  return {
    download_js_wasm: Math.round(p.fetchDone),
    wasm_compile: Math.round(p.instDur),
    engine_boot_to_canvas: Math.round(goBoot),
    total_to_canvas: Math.round(p.canvas),
  };
});
console.log("BOOT PHASES (ms, unthrottled local):", JSON.stringify(phases));
const mem = await pg.evaluate(() =>
  performance.memory
    ? { used: Math.round(performance.memory.usedJSHeapSize / 1048576), total: Math.round(performance.memory.totalJSHeapSize / 1048576) }
    : "n/a",
);
console.log("JS heap after boot (MB):", JSON.stringify(mem));
const peak = await pg.evaluate(() => Math.round(window.__peak / 1048576));
console.log("JS heap PEAK during boot (MB):", peak);
await b.close();
await srv.close();
