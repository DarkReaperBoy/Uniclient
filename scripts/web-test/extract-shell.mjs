// Extracts the deployed web shell (index.html) out of the release workflow.
// The shell exists ONLY as an inline heredoc in .github/workflows/release.yml
// (main never carries JS/HTML — AGENTS.md §1.4), so the suite tests the exact
// bytes CI ships by parsing that heredoc instead of keeping a drifting copy.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const ymlPath = join(repo, ".github", "workflows", "release.yml");
const outDir = process.argv[2] || join(here, "fixtures");
const outFile = join(outDir, "index.html");

const yml = readFileSync(ymlPath, "utf8");
const lines = yml.split("\n");

// The heredoc lives inside the web job's `run: |` block. YAML strips the
// block's base indentation, so the heredoc body in the shell is the raw text
// minus exactly the leading spaces of the `cat > web-build/index.html` line.
const catRe = /^(\s*)cat > web-build\/index\.html <<'HTML'\s*$/;
let start = -1;
let indent = "";
for (let i = 0; i < lines.length; i++) {
  const m = lines[i].match(catRe);
  if (m) {
    start = i + 1;
    indent = m[1];
    break;
  }
}
if (start < 0) {
  console.error("extract-shell: heredoc `cat > web-build/index.html <<'HTML'` not found in release.yml");
  process.exit(1);
}
const body = [];
let terminated = false;
for (let i = start; i < lines.length; i++) {
  if (lines[i] === indent + "HTML") {
    terminated = true;
    break;
  }
  body.push(lines[i].startsWith(indent) ? lines[i].slice(indent.length) : lines[i]);
}
if (!terminated) {
  console.error("extract-shell: heredoc terminator not found");
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });
writeFileSync(outFile, body.join("\n") + "\n");
console.log(`extract-shell: wrote ${outFile} (${body.length} lines)`);
