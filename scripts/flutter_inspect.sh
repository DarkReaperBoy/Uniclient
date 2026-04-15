#!/usr/bin/env bash
# Flutter VM Service inspector — takes screenshots and dumps widget tree
# from a running debug Flutter app without OS-level GUI automation.
#
# Usage:
#   ./scripts/flutter_inspect.sh screenshot [output.png]
#   ./scripts/flutter_inspect.sh tree
#   ./scripts/flutter_inspect.sh find <widget_name>
#   ./scripts/flutter_inspect.sh details <inspector-ID>
#   ./scripts/flutter_inspect.sh text <inspector-ID>   # get text content
#
# Requires: websocat (auto-fetched via nix-shell), running debug app
# The app must be launched with flutter debug mode (VM service enabled).

set -euo pipefail

ACTION="${1:-screenshot}"
WEBSOCAT="${WEBSOCAT:-}"

# Auto-fetch websocat if needed
if [[ -z "$WEBSOCAT" ]] || ! command -v "$WEBSOCAT" &>/dev/null; then
  if command -v websocat &>/dev/null; then
    WEBSOCAT=websocat
  else
    WEBSOCAT="$(nix-build '<nixpkgs>' -A websocat --no-out-link 2>/dev/null)/bin/websocat"
  fi
fi

# Find the VM service URL from app logs
LOG_FILE="${UNICLIENT_LOG:-/tmp/uniclient_stdout.log}"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "ERROR: App log not found at $LOG_FILE. Launch the app first." >&2
  exit 1
fi

VM_HTTP=$(grep -a "Dart VM service is listening on" "$LOG_FILE" | tail -1 | grep -oP 'http://[^ /]+/[^ /]+/')
if [[ -z "$VM_HTTP" ]]; then
  echo "ERROR: Could not find VM service URL in $LOG_FILE" >&2
  exit 1
fi

VM_WS="${VM_HTTP/http:/ws:}ws"

# Find the main isolate
ISOLATE=$(curl -s "${VM_HTTP}getVM" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
isolates = data.get('result', {}).get('isolates', [])
for i in isolates:
    if not i.get('isSystemIsolate', False):
        print(i['id'])
        break
" 2>/dev/null)

if [[ -z "$ISOLATE" ]]; then
  echo "ERROR: Could not find main isolate. Is the app running?" >&2
  exit 1
fi

call_ext() {
  local method="$1"
  local extra_params="${2:-}"
  local params="{\"isolateId\":\"$ISOLATE\",\"objectGroup\":\"inspect\"$extra_params}"
  echo "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"$method\",\"params\":$params}" \
    | timeout 10 "$WEBSOCAT" -n1 -B 10000000 "$VM_WS" 2>/dev/null
}

case "$ACTION" in
  screenshot)
    OUTFILE="${2:-/tmp/flutter_screenshot.png}"
    # Screenshot the root UniClientApp widget (inspector-8 in typical tree)
    # First find the app root by getting the summary tree
    # Try to find the app root widget. The tree can be large (>64KB), so if
    # parsing fails, fall back to well-known inspector IDs.
    ROOT_ID=$(call_ext "ext.flutter.inspector.getRootWidgetSummaryTree" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    root = data.get('result', {}).get('result', {})
    def find_app(node):
        desc = node.get('description', '')
        if 'App' in desc and node.get('createdByLocalProject'):
            return node.get('valueId', '')
        for c in node.get('children', []):
            r = find_app(c)
            if r: return r
        return ''
    vid = find_app(root)
    if not vid:
        for c in root.get('children', []):
            for c2 in c.get('children', []):
                vid = c2.get('valueId', '')
                if vid: break
            if vid: break
    print(vid)
except:
    pass
" 2>/dev/null)

    # Fallback: try common inspector IDs (inspector-8 is typically UniClientApp)
    if [[ -z "$ROOT_ID" ]]; then
      ROOT_ID="inspector-8"
    fi

    call_ext "ext.flutter.inspector.screenshot" \
      ",\"id\":\"$ROOT_ID\",\"width\":1280,\"height\":800,\"margin\":0,\"maxPixelRatio\":2.0,\"debugPaint\":false" \
    | python3 -c "
import json, sys, base64
data = json.load(sys.stdin)
result = data.get('result', {}).get('result', data.get('result', {}))
if isinstance(result, str):
    img = base64.b64decode(result)
    with open('$OUTFILE', 'wb') as f: f.write(img)
    print(f'Screenshot saved: $OUTFILE ({len(img)} bytes)')
else:
    print(f'ERROR: unexpected response: {str(result)[:200]}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
    ;;

  tree)
    call_ext "ext.flutter.inspector.getRootWidgetSummaryTree" | python3 -c "
import json, sys
data = json.load(sys.stdin)
root = data.get('result', {}).get('result', {})
def show(node, indent=0):
    desc = node.get('description', '?')
    vid = node.get('valueId', '')
    proj = ' *' if node.get('createdByLocalProject') else ''
    if len(desc) > 90: desc = desc[:90] + '...'
    print('  ' * indent + f'{desc}{proj} [{vid}]')
    for c in node.get('children', []):
        if indent < 10: show(c, indent + 1)
show(root)
" 2>/dev/null
    ;;

  find)
    QUERY="${2:?Usage: $0 find <widget_name>}"
    call_ext "ext.flutter.inspector.getRootWidgetSummaryTree" | python3 -c "
import json, sys
data = json.load(sys.stdin)
root = data.get('result', {}).get('result', {})
query = '$QUERY'.lower()
def find(node, path=''):
    desc = node.get('description', '')
    vid = node.get('valueId', '')
    cur = f'{path}/{desc}'
    if query in desc.lower():
        print(f'{vid}: {desc}')
    for c in node.get('children', []):
        find(c, cur)
find(root)
" 2>/dev/null
    ;;

  details|text)
    WIDGET_ID="${2:?Usage: $0 details <inspector-ID>}"
    call_ext "ext.flutter.inspector.getDetailsSubtree" \
      ",\"arg\":\"$WIDGET_ID\",\"subtreeDepth\":10" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
result = data.get('result', {}).get('result', {})
action = '$ACTION'
def show(node, indent=0):
    desc = node.get('description', '?')
    props = node.get('properties', [])
    if len(desc) > 100: desc = desc[:100]
    if action == 'text':
        for p in props:
            name = p.get('name', '')
            val = str(p.get('value', p.get('description', '')))
            if name in ('data', 'text') and val:
                print(f'[{desc}] {name}: {val}')
    else:
        print('  ' * indent + desc)
        for p in props:
            val = str(p.get('value', p.get('description', '')))
            if val and val != 'null' and val != 'None' and len(val) < 200:
                print('  ' * indent + f'  {p.get(\"name\",\"\")}: {val}')
    for c in node.get('children', []):
        if indent < 12: show(c, indent + 1)
show(result)
" 2>/dev/null
    ;;

  *)
    echo "Usage: $0 {screenshot|tree|find|details|text} [args...]"
    exit 1
    ;;
esac
