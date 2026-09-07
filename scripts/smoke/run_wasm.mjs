// Wrapper: sets up the Node globals the Go wasm runtime expects (mirrors
// Go's own lib/wasm/wasm_exec_node.js) — plain wasm_exec.js is browser-only
// and has no fs bridge — then runs the real smoke test.
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

globalThis.require = createRequire(import.meta.url);
globalThis.fs = require("fs");
globalThis.path = require("path");
globalThis.TextEncoder = require("util").TextEncoder;
globalThis.TextDecoder = require("util").TextDecoder;
globalThis.performance ??= require("performance");
globalThis.crypto ??= require("crypto");

const here = dirname(fileURLToPath(import.meta.url));
const goRoot = process.env.GOROOT || "/home/z/sdk/go";
await import(pathToFileURL(join(goRoot, "lib", "wasm", "wasm_exec.js")));
await import(pathToFileURL(join(here, "smoke_wasm.mjs")));
