// Web E2E runner: prepares fixtures, starts the controllable server, runs
// the spec tiers against headless Chrome via puppeteer.
//
// Tiers:
//   shell — the gh-pages shell logic (extracted from release.yml) against
//           fixture wasm bytes: progress bar, ETag revalidation, offline
//           fallback, retry/relaunch, failure states.
//   app   — the real dist/uniclient.wasm: boot, canvas attach, welcome
//           screen, picker, mobile viewport, two-tab vault persistence.
//   live  — (--live) the deployed https://darkreaperboy.github.io/Uniclient/.
//
// Env:
//   UC_WASM               path to the real wasm (default dist/uniclient.wasm)
//   PUPPETEER_EXECUTABLE_PATH  use a specific Chrome (CI's system Chrome)
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const fixtures = join(here, "fixtures");
const artifacts = join(here, "artifacts");
const LIVE = process.argv.includes("--live");
const ONLY = (process.argv.find((a) => a.startsWith("--only=")) || "= ").slice(7).trim() || null;

mkdirSync(artifacts, { recursive: true });
rmSync(fixtures, { recursive: true, force: true });
mkdirSync(fixtures, { recursive: true });

// --- fixtures -------------------------------------------------------------
execFileSync("node", [join(here, "extract-shell.mjs"), fixtures], { stdio: "inherit" });

const goTool = (() => {
  try {
    return execFileSync("go", ["env", "GOROOT"], { encoding: "utf8" }).trim();
  } catch {
    for (const p of [process.env.GOROOT, "/usr/local/go", join(process.env.HOME || "", "go")]) {
      if (p && existsSync(join(p, "lib", "wasm", "wasm_exec.js"))) return p;
    }
    return null;
  }
})();

if (!goTool) {
  console.error("run: no Go toolchain found (go not on PATH, GOROOT unset) — cannot source wasm_exec.js");
  process.exit(1);
}
copyFileSync(join(goTool, "lib", "wasm", "wasm_exec.js"), join(fixtures, "wasm_exec.js"));

// dummy.wasm: valid module header + padding, ~1.5 MB so the MB counter and
// the determinate bar are exercised. Instantiates fine; go.run then finds no
// Go exports — the shell's stop/retry path covers that end.
{
  const head = Buffer.from([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
  const pad = Buffer.alloc(1_500_000 - head.length, 0x42);
  const body = Buffer.concat([head, pad]);
  writeFileSync(join(fixtures, "dummy.wasm"), body);
  copyFileSync(join(fixtures, "dummy.wasm"), join(fixtures, "uniclient.wasm"));
}

// exit-helper.wasm: real Go binary whose main returns at once — go.run()
// resolves, the shell reports "Uniclient exited" and offers Retry.
let haveExitHelper = false;
try {
  const src = join(here, "exit-helper", "main.go");
  const out = join(fixtures, "exit-helper.wasm");
  execFileSync("go", ["build", "-o", out, src], {
    env: { ...process.env, GOOS: "js", GOARCH: "wasm", CGO_ENABLED: "0" },
    stdio: "inherit",
  });
  haveExitHelper = true;
} catch (e) {
  console.warn("run: exit-helper build failed — exit-journey tests will skip:", String(e).split("\n")[0]);
}

const realWasm = process.env.UC_WASM || join(repo, "dist", "uniclient.wasm");
const haveRealWasm = existsSync(realWasm);
if (!haveRealWasm) {
  console.warn(`run: ${realWasm} missing — app tier skipped (run \`make wasm\` first)`);
}

// --- runner ---------------------------------------------------------------
const { startServer } = await import("./server.mjs");
const puppeteer = (await import("puppeteer")).default;
const pngjs = await import("pngjs");

const server = await startServer(fixtures, Number(process.env.PORT || 8099));
console.log(`run: server on ${server.url} (fixtures ${fixtures})`);

const launchBrowser = () =>
  puppeteer.launch({
    headless: true,
    protocolTimeout: 300000,
    ...(process.env.PUPPETEER_EXECUTABLE_PATH
      ? { executablePath: process.env.PUPPETEER_EXECUTABLE_PATH }
      : {}),
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--enable-unsafe-swiftshader",
      "--disable-gpu-sandbox",
      "--js-flags=--max-old-space-size=2048",
    ],
  });

const ctx = {
  browser: null,
  launchBrowser,
  server,
  fixtures,
  artifacts,
  pngjs,
  goRoot: goTool,
  haveExitHelper,
  realWasm: haveRealWasm ? realWasm : null,
  liveUrl: "https://darkreaperboy.github.io/Uniclient/",
};

const results = [];
let current = null;
const t = (name, fn) => {
  current = { name, status: "pending" };
  return (async () => {
    const entry = { name, status: "PASS", ms: 0 };
    const start = Date.now();
    try {
      await fn({
        ok(cond, msg) {
          if (!cond) throw new Error(msg || "assertion failed");
        },
        eq(a, b, msg) {
          if (a !== b) throw new Error(`${msg || "eq"}: ${JSON.stringify(a)} !== ${JSON.stringify(b)}`);
        },
        skip(reason) {
          entry.status = "SKIP";
          entry.reason = reason;
          throw new Error("__skip__");
        },
      });
    } catch (e) {
      if (entry.status === "SKIP") {
        // keep
      } else {
        entry.status = "FAIL";
        entry.error = String(e && e.message ? e.message : e).split("\n")[0];
        console.error(`  FAIL ${name}: ${entry.error}`);
      }
    }
    entry.ms = Date.now() - start;
    results.push(entry);
  })();
};

const specs = [];
if (!LIVE && (!ONLY || ONLY === "shell")) {
  specs.push(["shell", await import("./shell.spec.mjs")]);
}
if (!LIVE && (!ONLY || ONLY === "app")) {
  if (haveRealWasm) specs.push(["app", await import("./app.spec.mjs")]);
  else console.warn("run: app tier skipped (no real wasm)");
}
if (LIVE) {
  specs.push(["live", await import("./live.spec.mjs")]);
}

for (const [name, mod] of specs) {
  console.log(`== tier: ${name}`);
  if (name === "app") {
    copyFileSync(realWasm, join(fixtures, "uniclient.wasm"));
  }
  // A fresh browser per tier: the 88 MB app module is memory-heavy and
  // renderer reclaim lags — don't inherit the previous tier's heap.
  if (ctx.browser) await ctx.browser.close();
  ctx.browser = await launchBrowser();
  await mod.suite(t, ctx);
}

if (ctx.browser) await ctx.browser.close();
await server.close();

const pass = results.filter((r) => r.status === "PASS").length;
const fail = results.filter((r) => r.status === "FAIL").length;
const skip = results.filter((r) => r.status === "SKIP").length;
console.log(`\n${pass} passed, ${fail} failed, ${skip} skipped`);
for (const r of results) {
  console.log(`  ${r.status.padEnd(4)} ${r.name}${r.status === "SKIP" ? `  (${r.reason})` : ""}`);
}
process.exit(fail ? 1 : 0);
