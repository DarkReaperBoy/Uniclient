#!/usr/bin/env python3
"""R56 + R57 stage 2 — the fix.

R56: the package-level live-location dialog state (attachDlgLiveOn,
liveDurationSelected) moves to per-App fields (attachLiveOn, attachLiveSel)
— each separate window is its own App on its own GUI loop; package vars
were a cross-window race AND cross-talk (window A's toggle flipping
window B's attach dialog).

R57: attachContactsDone goes through the updateAttachDlg copy-on-write
installer with an account+kind guard (the R44 rule: field guards, not
pointer identity, under copy-on-write).
"""
import pathlib

GUI = pathlib.Path("go/gui")
LOC = GUI / "location.go"
ST = GUI / "state.go"


def sub_once(text, old, new, what):
    n = text.count(old)
    assert n == 1, f"{what}: expected 1 occurrence, found {n}"
    return text.replace(old, new)


# --- state.go: per-App fields -------------------------------------------
t = ST.read_text()
old = (
    "\tattachMenuOpen bool\n"
)
new = (
    "\tattachMenuOpen bool\n"
    "\t// live-location attach-dialog state (slice 131) — GUI-loop-only,\n"
    "\t// per-App: each window's dialog owns its own (R56).\n"
    "\tattachLiveOn  bool\n"
    "\tattachLiveSel int\n"
)
# attachMenuOpen appears in App (330), snapshot (~2409), frame (~2732) —
# only the App declaration has this exact plain shape followed by the
# emoji comment; anchor wider to be unique.
old_wide = (
    "\tattachMenuOpen bool\n"
    "\n"
    "\t// emoji picker (AyuGram parity slice 10): panel open + active category\n"
)
new_wide = (
    "\tattachMenuOpen bool\n"
    "\t// live-location attach-dialog state (slice 131) — GUI-loop-only,\n"
    "\t// per-App: each window's dialog owns its own (R56).\n"
    "\tattachLiveOn  bool\n"
    "\tattachLiveSel int\n"
    "\n"
    "\t// emoji picker (AyuGram parity slice 10): panel open + active category\n"
)
t = sub_once(t, old_wide, new_wide, "state.go attachLive fields")
ST.write_text(t)

# --- location.go ---------------------------------------------------------
s = LOC.read_text()

# 1. Delete the package vars.
old = (
    "// liveDurationClickables pools the preset chips.\n"
    "\n"
    "// liveDurationSelected is the picked preset index (session state).\n"
    "var liveDurationSelected = 0\n"
    "\n"
    "// a.wid.attachDlgLiveBtn toggles the \"share live location\" mode; attachDlgLiveOn\n"
    "// is the toggle's state (reset when the dialog opens).\n"
    "var attachDlgLiveOn bool\n"
    "\n"
    "// attachDlgStopBtn stops an outgoing share from the bubble chip.\n"
    "\n"
)
new = (
    "// The live toggle + preset pick live on the App (R56): per-window\n"
    "// GUI-loop state, reset when the dialog opens.\n"
    "\n"
)
s = sub_once(s, old, new, "package vars deleted")

# 2. openAttachDialog: reset the per-App fields.
old = (
    "\tattachDlgLiveOn = false // live mode never leaks across dialog opens\n"
    "\tliveDurationSelected = 0\n"
)
new = (
    "\ta.attachLiveOn = false // live mode never leaks across dialog opens\n"
    "\ta.attachLiveSel = 0\n"
)
s = sub_once(s, old, new, "open reset")

# 3. The tail: account+kind signature through the installer.
old = (
    "\tif st != nil && kind == \"contact\" {\n"
    "\t\tgo func() {\n"
    "\t\t\tcontacts, err := a.eng.GetContacts(account)\n"
    "\t\t\ta.attachContactsDone(st, contacts, err)\n"
    "\t\t}()\n"
    "\t}\n"
    "}\n"
    "\n"
    "// attachContactsDone installs the contact-list load (extracted from\n"
    "// the open goroutine; stage-1 body is the original in-place tail —\n"
    "// the shape the R57 pin proves racy).\n"
    "func (a *App) attachContactsDone(st2 *attachDlgState, contacts []engine.ContactInfo, err error) {\n"
    "\ta.mu.Lock()\n"
    "\tif a.attachDlg != st2 {\n"
    "\t\ta.mu.Unlock()\n"
    "\t\treturn\n"
    "\t}\n"
    "\tif err != nil {\n"
    "\t\tst2.err = err.Error()\n"
    "\t} else {\n"
    "\t\tst2.contacts, st2.loaded = contacts, true\n"
    "\t}\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "}\n"
)
new = (
    "\tif st != nil && kind == \"contact\" {\n"
    "\t\tgo func() {\n"
    "\t\t\tcontacts, err := a.eng.GetContacts(account)\n"
    "\t\t\ta.attachContactsDone(account, kind, contacts, err)\n"
    "\t\t}()\n"
    "\t}\n"
    "}\n"
    "\n"
    "// attachContactsDone installs the contact-list load. R57: through the\n"
    "// copy-on-write installer with an account+kind guard (the R44 rule —\n"
    "// field guards, not pointer identity, under copy-on-write); a dialog\n"
    "// closed or reopened for another account/chat is not touched.\n"
    "func (a *App) attachContactsDone(account, kind string, contacts []engine.ContactInfo, err error) {\n"
    "\tif !a.updateAttachDlg(func(st *attachDlgState) bool {\n"
    "\t\tif st.account != account || st.kind != kind {\n"
    "\t\t\treturn false\n"
    "\t\t}\n"
    "\t\tif err != nil {\n"
    "\t\t\tst.err = err.Error()\n"
    "\t\t\treturn true\n"
    "\t\t}\n"
    "\t\tst.contacts, st.loaded = contacts, true\n"
    "\t\treturn true\n"
    "\t}) {\n"
    "\t\treturn\n"
    "\t}\n"
    "\ta.invalidate()\n"
    "}\n"
    "\n"
    "// updateAttachDlg copy-on-write installs a mutated attach-dialog\n"
    "// head. R57: attachDlgState is frame-carried as a POINTER, so the\n"
    "// frame and the head share the struct — every writer goes through\n"
    "// here so a frame's snapshot stays immutable while tails run.\n"
    "func (a *App) updateAttachDlg(fn func(st *attachDlgState) bool) bool {\n"
    "\ta.mu.Lock()\n"
    "\tdefer a.mu.Unlock()\n"
    "\tif a.attachDlg == nil {\n"
    "\t\treturn false\n"
    "\t}\n"
    "\tst := *a.attachDlg\n"
    "\tif !fn(&st) {\n"
    "\t\treturn false\n"
    "\t}\n"
    "\ta.attachDlg = &st\n"
    "\treturn true\n"
    "}\n"
)
s = sub_once(s, old, new, "attachContactsDone CoW + installer")

# 4. sendLocationFromDialog reads.
old = (
    "\tif attachDlgLiveOn && liveDurationSelected < len(liveDurationChoices) {\n"
    "\t\tperiod = liveDurationChoices[liveDurationSelected].minutes * 60\n"
    "\t}\n"
)
new = (
    "\tif a.attachLiveOn && a.attachLiveSel < len(liveDurationChoices) {\n"
    "\t\tperiod = liveDurationChoices[a.attachLiveSel].minutes * 60\n"
    "\t}\n"
)
s = sub_once(s, old, new, "send reads")

# 5. layoutAttachDialog click sites.
old = (
    "\tif a.wid.attachDlgLiveBtn.Clicked(gtx) {\n"
    "\t\tattachDlgLiveOn = !attachDlgLiveOn\n"
    "\t}\n"
    "\tif attachDlgLiveOn {\n"
    "\t\tgrowClickables(&a.wid.liveDurationBtns, len(liveDurationChoices))\n"
    "\t\tfor i := range liveDurationChoices {\n"
    "\t\t\tif a.wid.liveDurationBtns[i].Clicked(gtx) {\n"
    "\t\t\t\tliveDurationSelected = i\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
)
new = (
    "\tif a.wid.attachDlgLiveBtn.Clicked(gtx) {\n"
    "\t\ta.attachLiveOn = !a.attachLiveOn\n"
    "\t}\n"
    "\tif a.attachLiveOn {\n"
    "\t\tgrowClickables(&a.wid.liveDurationBtns, len(liveDurationChoices))\n"
    "\t\tfor i := range liveDurationChoices {\n"
    "\t\t\tif a.wid.liveDurationBtns[i].Clicked(gtx) {\n"
    "\t\t\t\ta.attachLiveSel = i\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
)
s = sub_once(s, old, new, "layout clicks")

# 6. The Send button label read.
old = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t if attachDlgLiveOn {\n"
# fall through to the generic replace below instead of an exact-depth guess
s = s.replace("\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tif attachDlgLiveOn {", "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tif a.attachLiveOn {")
s = s.replace("\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tif attachDlgLiveOn {", "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tif a.attachLiveOn {")
s = s.replace("if attachDlgLiveOn {\n", "if a.attachLiveOn {\n")
s = s.replace("if !attachDlgLiveOn {\n", "if !a.attachLiveOn {\n")
s = s.replace("if i == liveDurationSelected {", "if i == a.attachLiveSel {")
s = s.replace("if attachDlgLiveOn && a.attachLiveSel", "if a.attachLiveOn && a.attachLiveSel")
assert "attachDlgLiveOn" not in s, "leftover attachDlgLiveOn"
assert "liveDurationSelected" not in s, "leftover liveDurationSelected"

LOC.write_text(s)
print("stage 2 applied: CoW + per-App live state")
