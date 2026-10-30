// Controllable static file server for the web E2E suite.
//
// Mirrors the gh-pages delivery semantics the shell depends on:
//   - strong ETags, If-None-Match -> 304 (the shell's "up to date" fast path)
//   - chunked streaming bodies (exercises the determinate progress bar)
//   - Cache-Control: max-age=600 (gh-pages default)
// Control routes (GET /ctl/...) let tests inject failures:
//   /ctl/404?file=uniclient.wasm    -> serve 404 for that file
//   /ctl/netfail?file=uniclient.wasm -> destroy the socket for that file
//   /ctl/reset                      -> clear all injected failures
//   /ctl/note                       -> dump + clear the request log
import { createHash } from "node:crypto";
import { readFileSync, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";

export function startServer(root, port = 8099) {
  const state = {
    notFound: new Set(),
    netFail: new Set(),
    log: [],
  };
  const types = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".png": "image/png",
  };

  const server = createServer((req, res) => {
    const u = new URL(req.url, "http://localhost");
    if (u.pathname.startsWith("/ctl/")) {
      if (u.pathname === "/ctl/404") {
        state.notFound.add(u.searchParams.get("file"));
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("404 armed");
      } else if (u.pathname === "/ctl/netfail") {
        state.netFail.add(u.searchParams.get("file"));
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("netfail armed");
      } else if (u.pathname === "/ctl/reset") {
        state.notFound.clear();
        state.netFail.clear();
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("reset");
      } else if (u.pathname === "/ctl/note") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify(state.log));
        state.log = [];
      } else {
        res.writeHead(404);
        res.end("unknown ctl");
      }
      return;
    }

    let rel = normalize(u.pathname).replace(/^([/\\])+/, "");
    if (rel === "" || rel.endsWith("/")) rel += "index.html";
    const file = join(root, rel);
    if (state.netFail.has(rel)) {
      state.log.push({ path: u.pathname, status: "netfail" });
      res.destroy();
      return;
    }
    let status = 200;
    if (!existsSync(file) || !statSync(file).isFile()) {
      status = 404;
    } else if (state.notFound.has(rel)) {
      status = 404;
    }
    if (status === 404) {
      state.log.push({ path: u.pathname, status: 404 });
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
      return;
    }

    const body = readFileSync(file);
    const etag = '"' + createHash("sha1").update(body).digest("hex").slice(0, 16) + '"';
    const headers = {
      "content-type": types[extname(file)] || "application/octet-stream",
      "cache-control": "max-age=600",
      etag,
    };
    if (req.headers["if-none-match"] === etag) {
      state.log.push({ path: u.pathname, status: 304 });
      res.writeHead(304, headers);
      res.end();
      return;
    }
    state.log.push({ path: u.pathname, status: 200, bytes: body.length });
    headers["content-length"] = String(body.length);
    res.writeHead(200, headers);

    const CHUNK = 256 * 1024;
    // Small inter-chunk delay keeps the determinate progress bar observable
    // by the tests (instant local reads would flash by in one frame).
    // Performance measurements set SERVER_DELAY_MS=0 for real timings.
    const DELAY_MS = Number(process.env.SERVER_DELAY_MS ?? 15);
    let off = 0;
    const pump = () => {
      if (off >= body.length) {
        res.end();
        return;
      }
      const end = Math.min(off + CHUNK, body.length);
      if (res.write(body.subarray(off, end))) {
        off = end;
        setTimeout(pump, DELAY_MS);
      } else {
        off = end;
        res.once("drain", () => setTimeout(pump, DELAY_MS));
      }
    };
    pump();
  });

  return new Promise((resolve) => {
    server.listen(port, "127.0.0.1", () => {
      resolve({
        port,
        url: `http://127.0.0.1:${port}`,
        note: async () => {
          const r = await fetch(`http://127.0.0.1:${port}/ctl/note`);
          return r.json();
        },
        arm404: (file) => fetch(`http://127.0.0.1:${port}/ctl/404?file=${encodeURIComponent(file)}`),
        armNetfail: (file) => fetch(`http://127.0.0.1:${port}/ctl/netfail?file=${encodeURIComponent(file)}`),
        reset: () => fetch(`http://127.0.0.1:${port}/ctl/reset`),
        close: () => new Promise((done) => server.close(done)),
        root,
      });
    });
  });
}
