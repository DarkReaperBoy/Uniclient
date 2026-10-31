#!/usr/bin/env python3
"""Session 340 — rewrite the WORKLOG STATE block + insert the session entry."""
import pathlib
import sys

WL = pathlib.Path(__file__).resolve().parent.parent / "WORKLOG.md"
lines = WL.read_text().splitlines(keepends=True)

# --- sanity: locate the STATE block pieces ---
idx_item = next(i for i, l in enumerate(lines) if l.startswith("- item: iteration 31 DONE"))
idx_also = next(i for i, l in enumerate(lines) if l.startswith("- ALSO this session: iterations 27-28"))
idx_next = next(i for i, l in enumerate(lines) if l.startswith("- next: the unscanned gui files by size"))
idx_owner = next(i for i, l in enumerate(lines) if l.startswith("- owner-waiting:"))
idx_gate = next(i for i, l in enumerate(lines) if l.startswith("- last-gate:"))
assert idx_item < idx_also < idx_next < idx_owner < idx_gate, "STATE block shape changed"

new_state = [
    "- item: iteration 32 DONE — callsbox.go (1,089→1,139 lines, read in full — the unscanned queue by size #3); **R49** (the load tail appended fetched pages into a.callsBoxRows and sorted IN PLACE — the frame-shared backing array, armed by the delete shift's spare capacity, the R38 class → applyCallsBoxPage fresh-slice merge; the pre-fix array reuse is scratch-proven by scripts/r49_red_proof.go) + **R50** (the tail had NO session guard — cross-account/reopen/clear stomps, stale-busy double loads, the clear flow's reload racing the engine clear, and the failed-clear busy deadlock → callsBoxGen session key + callsBoxSessionLive guard + chained reload + callsBoxClearFailed). callsbox_r49_test.go ×5, local -race clean, CI race-leg extended. Rows in BUGS, section in MAP\n",
    "- ALSO this session (339, carried in STATE): iterations 29-31 — instantview.go (**R46** — closed the R34 systemic watch), media.go (CLEAN), giveaways.go (**R47** + **R48**); iterations 27-28 — exportdlg.go (**R42** + **R43**), twofa.go (**R44** + **R45**)\n",
    "- next: the unscanned gui files by size (poll.go 972 next, then stories.go 960, …) — full read+audit per file; CI CLOSED at job+step level: R32/R33 **41222152669**, R34-R36 **41236970838 (f14028a6)**, R37 **41237343094 (e6de37fc)**, R38 **41237698797 (6fdb1835)**, R39 **41238091947 (f38e19f7)**, R40 **41238742290 (1d143036)**, R41 **41239171673 (733d220b)**, R42/R43 **41244407673 (9b2cf32d)**, R44/R45 **41245057374 (1476115a)**, R46 **41245678978 (d8b4ce01)**, R47/R48 **41246248716 (12165b24)** — all 5 jobs each; pending: the R49/R50 dispatch (this commit)\n",
    lines[idx_owner],
    "- last-gate: local full GREEN — gofmt clean, full gui suite **914 PASS / 0 FAIL / 3 SKIP** (environmental; +5 R49/R50 pins on top of 909), LOCAL -race clean on the new pins; R46 CI **41245678978** + R47/R48 CI **41246248716** = SUCCESS (all 5 jobs at step level, Race green); R49/R50 CI dispatch pending\n",
]
lines[idx_item:idx_gate + 1] = new_state

# --- insert the Session 340 entry before the newest existing session header ---
idx_s339 = next(i for i, l in enumerate(lines) if l.startswith("## Session 339 — iterations 30-31"))
session340 = [
    "## Session 340 — iteration 32: callsbox.go = R49 + R50; R46/R47/R48 CI closed (2026-11-01)\n",
    "\n",
    "- Verified the pending CI at job AND step level: R46 **41245678978\n",
    "  (d8b4ce01)** and R47/R48 **41246248716 (12165b24)** — all 5 jobs\n",
    "  each SUCCESS, Race steps green.\n",
    "- Iteration 32 — callsbox.go (the Calls box, tdesktop parity slice\n",
    "  154): **R49** (load-tail append + in-place sort into the\n",
    "  frame-shared backing array — armed by the delete shift's spare\n",
    "  capacity → fresh-slice merge in applyCallsBoxPage;\n",
    "  scripts/r49_red_proof.go prints the pre-fix array reuse) + **R50**\n",
    "  (no session guard on the tail — cross-account/reopen/clear stomps,\n",
    "  stale busy resets, the clear flow's parallel reload, and the\n",
    "  failed-clear busy deadlock → callsBoxGen + applyCallsBoxPage guard\n",
    "  + chained reload + callsBoxClearFailed). ×5 pins in\n",
    "  callsbox_r49_test.go, local -race clean, suite 914 PASS / 0 FAIL /\n",
    "  3 SKIP (environmental). CI race-leg extended (r49_ci_filter.py).\n",
    "- Env note (also in HOT): Bash shells reset between tool calls —\n",
    "  re-source `. ./devroot.env && unset GOROOT && export\n",
    "  GOMODCACHE=/home/z/my-project/toolchain/mod\n",
    "  GOCACHE=/home/z/my-project/toolchain/gocache GOFLAGS=-p=1\n",
    "  GOMEMLIMIT=3GiB GOGC=20` in EVERY call; scripts/env.sh alone lacks\n",
    "  PKG_CONFIG_PATH (gui CGO builds fail on xkbcommon/wayland).\n",
    "\n",
]
lines[idx_s339:idx_s339] = session340

WL.write_text("".join(lines))
print("WORKLOG STATE rewritten + Session 340 entry inserted")
