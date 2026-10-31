#!/usr/bin/env python3
"""R49 + R50 — callsbox.go (chunk 3, iteration 32).

R49: the load tail appended into a.callsBoxRows (frame-shared backing
array) and sorted in place — after the delete shift left spare capacity,
a background page could write into and permute what an in-flight frame was
still reading. Fix: the merge builds a FRESH slice (the R38 rule).

R50: the load tail had no session guard — a fetch racing an account
switch, a reopen, or a clear-all landed anyway (cross-account rows,
resurrected clears, reopen stomps) and reset busy under the newer session.
Also: clearCallsBoxAll fired its first-page reload IN PARALLEL with the
engine clear (could land pre-clear rows as the "cleared" page), and its
failure tail left busy=true forever. Fix: callsBoxGen session key
(open/clear bump; tails apply only on a match, never touching the newer
session's flags), the reload chains after the clear, and the failure tail
recovers the flags under the same guard.

Tab-exact replacements (the Edit tool normalizes tabs -> spaces).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUI = ROOT / "go" / "gui"


def patch(path, old, new, expect=1):
    data = path.read_text()
    n = data.count(old)
    if n != expect:
        sys.exit(f"{path.name}: anchor found {n}x (want {expect}):\n{old[:200]}")
    path.write_text(data.replace(old, new))
    print(f"patched {path.name}: {expect} site(s)")


# ── state.go: the session-key field ────────────────────────────────────────
patch(
    GUI / "state.go",
    "\tcallsBoxLoad   bool\n\tcallsBoxMenu   *callsBoxMenuTarget\n",
    "\tcallsBoxLoad   bool\n"
    "\tcallsBoxGen    int // R50: load-session key; open/clear bump it, tails apply only on a match\n"
    "\tcallsBoxMenu   *callsBoxMenuTarget\n",
)

# ── callsbox.go: openCallsBox bumps the session key ────────────────────────
patch(
    GUI / "callsbox.go",
    "\ta.callsBoxDone = false\n\ta.callsBoxLoad = true\n\ta.callsBoxMenu = nil\n",
    "\ta.callsBoxDone = false\n\ta.callsBoxLoad = true\n\ta.callsBoxGen++\n\ta.callsBoxMenu = nil\n",
)

# ── callsbox.go: loadCallsBoxPage -> capture + applyCallsBoxPage ───────────
OLD_LOAD = (
    "// loadCallsBoxPage fetches one page of call history at offsetID, groups it\n"
    "// into rows, and appends (first page replaces). Entries are filtered to\n"
    "// strictly-older-than-offset as a dedupe guard; a short or empty page marks\n"
    "// the history exhausted.\n"
    "func (a *App) loadCallsBoxPage(accountID string, offsetID, limit int) {\n"
    "\tgo func() {\n"
    "\t\tentries, err := a.eng.GetCallHistory(accountID, offsetID, limit)\n"
    "\t\ta.mu.Lock()\n"
    "\t\tfirst := offsetID == 0\n"
    "\t\tif err != nil {\n"
    "\t\t\ta.callsBoxBusy = false\n"
    "\t\t\ta.callsBoxLoad = false\n"
    "\t\t\ta.mu.Unlock()\n"
    "\t\t\ta.setToast(\"Calls: \" + err.Error())\n"
    "\t\t\treturn\n"
    "\t\t}\n"
    "\t\tif offsetID > 0 {\n"
    "\t\t\tkept := entries[:0]\n"
    "\t\t\tfor _, e := range entries {\n"
    "\t\t\t\tif id, convErr := strconv.Atoi(e.MsgID); convErr == nil && id < offsetID {\n"
    "\t\t\t\t\tkept = append(kept, e)\n"
    "\t\t\t\t}\n"
    "\t\t\t}\n"
    "\t\t\tentries = kept\n"
    "\t\t}\n"
    "\t\tif len(entries) < limit {\n"
    "\t\t\ta.callsBoxDone = true\n"
    "\t\t}\n"
    "\t\tif len(entries) > 0 {\n"
    "\t\t\tmerged := append(a.callsBoxRows, groupCallEntries(entries)...)\n"
    "\t\t\tsortCallBoxRows(merged)\n"
    "\t\t\ta.callsBoxRows = merged\n"
    "\t\t} else if first {\n"
    "\t\t\ta.callsBoxRows = nil\n"
    "\t\t}\n"
    "\t\ta.callsBoxBusy = false\n"
    "\t\ta.callsBoxLoad = false\n"
    "\t\ta.mu.Unlock()\n"
    "\t\ta.invalidate()\n"
    "\t}()\n"
    "}\n"
)
NEW_LOAD = (
    "// loadCallsBoxPage fetches one page of call history at offsetID off the GUI\n"
    "// loop and hands the result to applyCallsBoxPage. The session key\n"
    "// (callsBoxGen) is captured at fire time so a switch, reopen, or clear\n"
    "// racing the round-trip drops the result instead of applying it (R50).\n"
    "func (a *App) loadCallsBoxPage(accountID string, offsetID, limit int) {\n"
    "\ta.mu.Lock()\n"
    "\tgen := a.callsBoxGen\n"
    "\ta.mu.Unlock()\n"
    "\tgo func() {\n"
    "\t\tentries, err := a.eng.GetCallHistory(accountID, offsetID, limit)\n"
    "\t\ta.applyCallsBoxPage(accountID, gen, offsetID, limit, entries, err)\n"
    "\t}()\n"
    "}\n"
    "\n"
    "// callsBoxSessionLive reports whether the given load session still owns\n"
    "// the box. Caller must hold a.mu.\n"
    "func (a *App) callsBoxSessionLive(accountID string, gen int) bool {\n"
    "\treturn a.callsBoxOpen && a.callsBoxFor == accountID && a.callsBoxGen == gen\n"
    "}\n"
    "\n"
    "// applyCallsBoxPage installs one fetched page into the head. R50: applies\n"
    "// only while the box is still open for the same account and load session —\n"
    "// a stale tail returns without touching busy (the newer session owns it)\n"
    "// or toasting its error. R49: pages merge through a FRESH slice, never\n"
    "// append into a.callsBoxRows — the head's backing array is shared with\n"
    "// in-flight frames, and the delete shift leaves spare capacity, so an\n"
    "// in-place append+sort would write into and permute what a frame is still\n"
    "// reading. Entries are filtered to strictly-older-than-offset as a dedupe\n"
    "// guard; a short or empty page marks the history exhausted.\n"
    "func (a *App) applyCallsBoxPage(accountID string, gen, offsetID, limit int, entries []engine.CallHistoryEntry, err error) {\n"
    "\ta.mu.Lock()\n"
    "\tif !a.callsBoxSessionLive(accountID, gen) {\n"
    "\t\ta.mu.Unlock()\n"
    "\t\treturn\n"
    "\t}\n"
    "\tfirst := offsetID == 0\n"
    "\tif err != nil {\n"
    "\t\ta.callsBoxBusy = false\n"
    "\t\ta.callsBoxLoad = false\n"
    "\t\ta.mu.Unlock()\n"
    "\t\ta.setToast(\"Calls: \" + err.Error())\n"
    "\t\treturn\n"
    "\t}\n"
    "\tif offsetID > 0 {\n"
    "\t\tkept := entries[:0]\n"
    "\t\tfor _, e := range entries {\n"
    "\t\t\tif id, convErr := strconv.Atoi(e.MsgID); convErr == nil && id < offsetID {\n"
    "\t\t\t\tkept = append(kept, e)\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t\tentries = kept\n"
    "\t}\n"
    "\tif len(entries) < limit {\n"
    "\t\ta.callsBoxDone = true\n"
    "\t}\n"
    "\tif len(entries) > 0 {\n"
    "\t\tgrouped := groupCallEntries(entries)\n"
    "\t\tmerged := make([]callBoxRow, len(a.callsBoxRows), len(a.callsBoxRows)+len(grouped))\n"
    "\t\tcopy(merged, a.callsBoxRows)\n"
    "\t\tmerged = append(merged, grouped...)\n"
    "\t\tsortCallBoxRows(merged)\n"
    "\t\ta.callsBoxRows = merged\n"
    "\t} else if first {\n"
    "\t\ta.callsBoxRows = nil\n"
    "\t}\n"
    "\ta.callsBoxBusy = false\n"
    "\ta.callsBoxLoad = false\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "}\n"
)
patch(GUI / "callsbox.go", OLD_LOAD, NEW_LOAD)

# ── callsbox.go: clearCallsBoxAll — gen, guarded recovery, chained reload ──
OLD_CLEAR = (
    "// clearCallsBoxAll runs the Clear-all flow: deletePhoneCallHistory (revoke\n"
    "// honored), then reload the first page (tdesktop ClearCallsBox).\n"
    "func (a *App) clearCallsBoxAll(revoke bool) {\n"
    "\ta.mu.Lock()\n"
    "\tacc := a.callsBoxFor\n"
    "\ta.callsClearDlg = false\n"
    "\ta.callsRowMenu = nil\n"
    "\ta.callsBoxRows = nil\n"
    "\ta.callsBoxBusy = true\n"
    "\ta.callsBoxDone = false\n"
    "\ta.callsBoxLoad = true\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\tif err := a.eng.ClearCallHistory(acc, revoke); err != nil {\n"
    "\t\t\ta.setToast(\"Clear call history: \" + err.Error())\n"
    "\t\t\treturn\n"
    "\t\t}\n"
    "\t\ta.setToast(\"Call history cleared\")\n"
    "\t}()\n"
    "\ta.loadCallsBoxPage(acc, 0, 20)\n"
    "}\n"
)
NEW_CLEAR = (
    "// clearCallsBoxAll runs the Clear-all flow: deletePhoneCallHistory (revoke\n"
    "// honored), then reload the first page (tdesktop ClearCallsBox). R50: the\n"
    "// reload chains AFTER the engine clear — fired in parallel it raced the\n"
    "// deletion server-side and could land the pre-clear rows as the \"cleared\"\n"
    "// first page; a failed clear recovers the busy/loading flags under the\n"
    "// session guard instead of spinning \"Loading…\" forever.\n"
    "func (a *App) clearCallsBoxAll(revoke bool) {\n"
    "\ta.mu.Lock()\n"
    "\tacc := a.callsBoxFor\n"
    "\ta.callsClearDlg = false\n"
    "\ta.callsRowMenu = nil\n"
    "\ta.callsBoxRows = nil\n"
    "\ta.callsBoxBusy = true\n"
    "\ta.callsBoxDone = false\n"
    "\ta.callsBoxLoad = true\n"
    "\ta.callsBoxGen++\n"
    "\tgen := a.callsBoxGen\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\tif err := a.eng.ClearCallHistory(acc, revoke); err != nil {\n"
    "\t\t\ta.setToast(\"Clear call history: \" + err.Error())\n"
    "\t\t\ta.callsBoxClearFailed(acc, gen)\n"
    "\t\t\treturn\n"
    "\t\t}\n"
    "\t\ta.setToast(\"Call history cleared\")\n"
    "\t\ta.loadCallsBoxPage(acc, 0, 20)\n"
    "\t}()\n"
    "}\n"
    "\n"
    "// callsBoxClearFailed recovers the busy/loading flags after a failed\n"
    "// clear. R50: session-guarded — if the box moved on (switch, reopen, or a\n"
    "// newer clear), the newer session owns the flags and they stay untouched.\n"
    "func (a *App) callsBoxClearFailed(accountID string, gen int) {\n"
    "\ta.mu.Lock()\n"
    "\tif a.callsBoxSessionLive(accountID, gen) {\n"
    "\t\ta.callsBoxBusy = false\n"
    "\t\ta.callsBoxLoad = false\n"
    "\t}\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "}\n"
)
patch(GUI / "callsbox.go", OLD_CLEAR, NEW_CLEAR)

print("R49+R50 source patches applied")
