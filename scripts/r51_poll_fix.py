#!/usr/bin/env python3
"""R51 + R52 — poll.go (chunk 3, iteration 33).

R51: pollDlgState is frame-carried as a POINTER (state.go snapshot), and
five sites mutated it IN PLACE — submit's busy=true head, both busy=false
tails (the send tail on a BACKGROUND goroutine), and both correct writes —
while layoutPollDialog read d.busy/d.correct through the frozen frame
pointer with no a.mu: R34's exact pre-fix shape. The send tail also had no
session guard: a cancel+reopen mid-send let the old tail un-busy (double
send window) or close the freshly reopened draft. Fix: updatePollDlg
copy-on-write installer + pollDlgGen session key (openPollDialog bumps;
pollSendDone clears/closes only on a match; failures toast regardless —
the send really happened).

R52: the send goroutine read a.wid.pollAnonSw/pollMultiSw/pollQuizSw
.Value — GUI-loop-only widget state — racing the layout-side switch
writes. Fix: capture the switch state on the GUI loop before spawning.

Line-index based edits (deep layout nesting makes tab-exact string
anchors fragile; content-matched line ranges with preserved indentation).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
POLL = ROOT / "go" / "poll.go" if False else ROOT / "go" / "gui" / "poll.go"
STATE = ROOT / "go" / "gui" / "state.go"


def lead(line):
    return line[: len(line) - len(line.lstrip("\t"))]


lines = POLL.read_text().splitlines(keepends=True)


def find(strip_eq, near=None):
    for i, l in enumerate(lines):
        if l.strip() == strip_eq:
            if near is None or any(lines[j].strip() == near for j in range(max(0, i - 1), min(len(lines), i + 3))):
                return i
    sys.exit(f"anchor not found: {strip_eq!r}")


# ── A. updatePollDlg installer before pollMaxOptions ──────────────────────
i_const = find("const pollMaxOptions = 10")
INSTALLER = [
    "// updatePollDlg copy-on-write installs a mutated poll-dialog head. R51:\n",
    "// the frame carries the *pollDlgState POINTER (the state.go snapshot),\n",
    "// so in-place busy/correct writes raced the frameMu-side reads in\n",
    "// layoutPollDialog (d.busy drives the Create/Sending label, d.correct\n",
    "// the quiz answer highlight) — a frozen head must never change. fn\n",
    "// edits a copy; returning false aborts with the head untouched.\n",
    "// Reports whether it installed.\n",
    "func (a *App) updatePollDlg(fn func(d *pollDlgState) bool) bool {\n",
    "\ta.mu.Lock()\n",
    "\tdefer a.mu.Unlock()\n",
    "\tif a.pollDlg == nil {\n",
    "\t\treturn false\n",
    "\t}\n",
    "\td := *a.pollDlg\n",
    "\tif !fn(&d) {\n",
    "\t\treturn false\n",
    "\t}\n",
    "\ta.pollDlg = &d\n",
    "\treturn true\n",
    "}\n",
    "\n",
]
lines[i_const:i_const] = INSTALLER

# ── B. openPollDialog bumps the session key ────────────────────────────────
i_open = find("a.pollDlg = &pollDlgState{correct: 0}")
lines.insert(i_open + 1, lead(lines[i_open]) + "a.pollDlgGen++ // R51: new dialog session — in-flight send tails retire\n")

# ── C. submitPollDialog replaced + pollSendDone extracted ─────────────────
i_sub = find("func (a *App) submitPollDialog() {")
i_comment = i_sub - 1
if not lines[i_comment].strip().startswith("// submitPollDialog validates"):
    sys.exit("submit comment anchor mismatch")
i_layout = find("// layoutPollDialog renders the poll creation card over the chat pane.")
NEW_SUBMIT = [
    "// submitPollDialog validates and sends the poll (engine CreatePollEx).\n",
    "func (a *App) submitPollDialog() {\n",
    "\ta.mu.Lock()\n",
    "\tk := a.selected\n",
    "\tgen := a.pollDlgGen // R51: the send tail's session key\n",
    "\tdlg := a.pollDlg\n",
    "\ta.mu.Unlock()\n",
    "\tif dlg == nil || k == nil {\n",
    "\t\treturn\n",
    "\t}\n",
    "\tif !a.updatePollDlg(func(d *pollDlgState) bool {\n",
    "\t\tif d.busy {\n",
    "\t\t\treturn false // already sending\n",
    "\t\t}\n",
    "\t\td.busy = true\n",
    "\t\treturn true\n",
    "\t}) {\n",
    "\t\treturn\n",
    "\t}\n",
    "\ta.invalidate()\n",
    "\n",
    "\tq := strings.TrimSpace(a.wid.pollQEd.Text())\n",
    "\topts := make([]string, 0, len(pollOptEds))\n",
    "\tfor i := range pollOptEds {\n",
    "\t\tif t := strings.TrimSpace(pollOptEds[i].Text()); t != \"\" {\n",
    "\t\t\topts = append(opts, t)\n",
    "\t\t}\n",
    "\t}\n",
    "\tif err := validatePollDraft(q, opts); err != \"\" {\n",
    "\t\ta.setToast(err)\n",
    "\t\ta.updatePollDlg(func(d *pollDlgState) bool { d.busy = false; return true })\n",
    "\t\treturn\n",
    "\t}\n",
    "\n",
    "\t// R52: capture the switch state HERE, on the GUI loop — a.wid is\n",
    "\t// GUI-loop-only state; reading it from the send goroutine raced the\n",
    "\t// layout-side switch writes (material.Switch updates .Value during\n",
    "\t// Layout).\n",
    "\tanon := a.wid.pollAnonSw.Value\n",
    "\tmulti := a.wid.pollMultiSw.Value\n",
    "\tquiz := a.wid.pollQuizSw.Value\n",
    "\tcorrect := dlg.correct // install-preserved by the busy install above\n",
    "\tacc, chat := k.AccountID, k.ChatID\n",
    "\tgo func() {\n",
    "\t\t_, err := a.eng.CreatePollEx(acc, chat, q, opts, engine.PollOptions{\n",
    "\t\t\tAnonymous:      anon,\n",
    "\t\t\tMultipleChoice: multi,\n",
    "\t\t\tQuiz:           quiz,\n",
    "\t\t\tCorrectOption:  correct,\n",
    "\t\t})\n",
    "\t\ta.pollSendDone(gen, err)\n",
    "\t}()\n",
    "}\n",
    "\n",
    "// pollSendDone lands the send tail. R51: the busy flag clears and the\n",
    "// dialog closes only while the SAME dialog session still owns the head —\n",
    "// a tail racing a cancel+reopen (pollDlgGen bumped) must not un-busy or\n",
    "// close the new draft. A failure toasts regardless of session: the poll\n",
    "// really was sent and really failed — honest-UI beats session purity\n",
    "// for errors the user's own action produced.\n",
    "func (a *App) pollSendDone(gen int, err error) {\n",
    "\ta.mu.Lock()\n",
    "\tlive := a.pollDlg != nil && a.pollDlgGen == gen\n",
    "\ta.mu.Unlock()\n",
    "\tif live {\n",
    "\t\tif err == nil {\n",
    "\t\t\ta.closePollDialog()\n",
    "\t\t} else {\n",
    "\t\t\ta.updatePollDlg(func(d *pollDlgState) bool { d.busy = false; return true })\n",
    "\t\t}\n",
    "\t}\n",
    "\tif err != nil {\n",
    "\t\ta.setToast(\"Poll failed: \" + err.Error())\n",
    "\t}\n",
    "}\n",
    "\n",
]
lines[i_comment:i_layout] = NEW_SUBMIT

# ── D. delete-option correct reset → installer ────────────────────────────
i_d = None
for i, l in enumerate(lines):
    if l.strip() == "a.mu.Lock()" and i + 1 < len(lines) and lines[i + 1].strip() == "if a.pollDlg != nil && a.pollDlg.correct == i {":
        i_d = i
        break
if i_d is None:
    sys.exit("delete-reset anchor not found")
assert lines[i_d + 2].strip() == "a.pollDlg.correct = 0" and lines[i_d + 4].strip() == "a.mu.Unlock()"
ind = lead(lines[i_d])
lines[i_d:i_d + 5] = [
    ind + "a.updatePollDlg(func(d *pollDlgState) bool { // R51: copy-on-write\n",
    ind + "\tif d.correct != i {\n",
    ind + "\t\treturn false\n",
    ind + "\t}\n",
    ind + "\td.correct = 0\n",
    ind + "\treturn true\n",
    ind + "})\n",
]

# ── E. correct picker → installer ──────────────────────────────────────────
i_c = None
for i, l in enumerate(lines):
    if l.strip() == "if a.wid.pollCorrectBtns[i].Clicked(gtx) {":
        i_c = i
        break
if i_c is None:
    sys.exit("correct-picker anchor not found")
for off, want in [(1, "a.mu.Lock()"), (2, "if a.pollDlg != nil {"), (3, "a.pollDlg.correct = i"), (4, "}"), (5, "a.mu.Unlock()"), (6, "a.invalidate()")]:
    if lines[i_c + off].strip() != want:
        sys.exit(f"correct-picker shape mismatch at +{off}: {lines[i_c + off].strip()!r}")
ind = lead(lines[i_c + 1])
lines[i_c + 1:i_c + 7] = [
    ind + "a.updatePollDlg(func(d *pollDlgState) bool { d.correct = i; return true }) // R51: copy-on-write\n",
    ind + "a.invalidate()\n",
]

POLL.write_text("".join(lines))
print("poll.go: R51 installer + gen + submit/tail conversion + picker/delete conversion, R52 capture")

# ── state.go: the session-key field ────────────────────────────────────────
d = STATE.read_text()
old = "\tpollDlg     *pollDlgState\n"
new = ("\tpollDlg     *pollDlgState\n"
       "\tpollDlgGen  int // R51: dialog session key; openPollDialog bumps it, send tails land only on a match\n")
if d.count(old) != 1:
    sys.exit(f"state.go pollDlg anchor count = {d.count(old)}")
STATE.write_text(d.replace(old, new))
print("state.go: pollDlgGen field added")
