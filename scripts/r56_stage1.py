#!/usr/bin/env python3
"""R56 + R57 stage 1 — extraction only, behavior-identical (the RED shape).

location.go: openAttachDialog's contact-load tail becomes the extracted
attachContactsDone with EXACTLY the original in-place body (identity
guard, in-place writes under a.mu). The R57 pin fails against this
under -race, proving the production race. Stage 2 converts to CoW +
per-App live state.
"""
import pathlib

p = pathlib.Path("go/gui/location.go")
s = p.read_text()


def sub_once(text, old, new, what):
    n = text.count(old)
    assert n == 1, f"{what}: expected 1 occurrence, found {n}"
    return text.replace(old, new)


old = (
    "\tif st != nil && kind == \"contact\" {\n"
    "\t\taccount, st2 := account, st\n"
    "\t\tgo func() {\n"
    "\t\t\tcontacts, err := a.eng.GetContacts(account)\n"
    "\t\t\ta.mu.Lock()\n"
    "\t\t\tif a.attachDlg != st2 {\n"
    "\t\t\t\ta.mu.Unlock()\n"
    "\t\t\t\treturn\n"
    "\t\t\t}\n"
    "\t\t\tif err != nil {\n"
    "\t\t\t\tst2.err = err.Error()\n"
    "\t\t\t} else {\n"
    "\t\t\t\tst2.contacts, st2.loaded = contacts, true\n"
    "\t\t\t}\n"
    "\t\t\ta.mu.Unlock()\n"
    "\t\t\ta.invalidate()\n"
    "\t\t}()\n"
    "\t}\n"
)
new = (
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
s = sub_once(s, old, new, "contacts tail extraction")
p.write_text(s)
print("stage 1 applied: attachContactsDone extracted (in-place body)")
