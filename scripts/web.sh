#!/usr/bin/env bash
# web.sh — serve the wasm build locally: generates a minimal web shell and
# serves it on :8080. Run `make wasm` first (dist/uniclient.wasm).
set -euo pipefail

cd "$(dirname "$0")/.."
DIST=dist
PORT="${1:-8080}"
GOROOT="$(go env GOROOT)"

[ -f "$DIST/uniclient.wasm" ] || { echo "dist/uniclient.wasm missing — run: make wasm"; exit 1; }
[ -f "$DIST/wasm_exec.js" ] || cp "$GOROOT/lib/wasm_exec.js" "$DIST/wasm_exec.js"

if [ ! -f "$DIST/index.html" ]; then
	cat > "$DIST/index.html" <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Uniclient</title>
<style>
  html, body { margin:0; height:100%; background:#17212B; }
  canvas { display:block; width:100vw; height:100vh; touch-action:none; }
</style>
</head>
<body>
<script src="wasm_exec.js"></script>
<script>
(async () => {
  const go = new Go();
  const resp = await fetch("uniclient.wasm");
  if (!resp.ok) { document.body.textContent = "failed to load uniclient.wasm"; return; }
  const bytes = await resp.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, go.importObject);
  go.run(instance);
})();
</script>
</body>
</html>
HTML
fi

echo "serving http://127.0.0.1:$PORT/"
exec python3 -m http.server "$PORT" --directory "$DIST" --bind 127.0.0.1
