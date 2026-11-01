#!/usr/bin/env python3
"""R53/R54/R55 stage 1 — extraction only, behavior-identical.

state.go: add storyViewGen (the session key).
stories.go: openStoryViewer bumps the gen and hands the fetch tail to an
extracted storyFetchDone whose body is EXACTLY the old inline tail logic
(in-place writes under a.mu + identity guard, plus the gen retirement).

This is the RED stage: the race pin (stories_race_pin_test.go) fails
against this shape under -race, proving the production race is real.
Stage 2 (r53_stage2.py) converts every writer to copy-on-write.
"""
import pathlib

GUI = pathlib.Path("go/gui")
STORIES = GUI / "stories.go"
STATE = GUI / "state.go"


def sub_once(text, old, new, what):
    n = text.count(old)
    assert n == 1, f"{what}: expected 1 occurrence, found {n}"
    return text.replace(old, new)


s = STORIES.read_text()

# --- openStoryViewer: gen bump + extracted tail --------------------------
old_open = (
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\traw, err := a.eng.FetchPeerStories(c.AccountID, c.ChatID)\n"
    "\t\ta.mu.Lock()\n"
    "\t\tsv := a.storyView\n"
    "\t\tif sv == nil || sv.chatID != c.ChatID || sv.accountID != c.AccountID {\n"
    "\t\t\ta.mu.Unlock()\n"
    "\t\t\treturn // a different viewer opened meanwhile\n"
    "\t\t}\n"
    "\t\tsv.loading = false\n"
    "\t\tif err != nil {\n"
    "\t\t\tsv.err = err.Error()\n"
    "\t\t} else {\n"
    "\t\t\tsv.items, err = parseStories(raw)\n"
    "\t\t\tif err != nil {\n"
    "\t\t\t\tsv.err = err.Error()\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t\ta.mu.Unlock()\n"
    "\t\ta.invalidate()\n"
    "\t}()\n"
    "}\n"
)
new_open = (
    "\ta.storyViewGen++ // R54: new viewer session — in-flight fetch tails retire\n"
    "\tgen := a.storyViewGen\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\traw, err := a.eng.FetchPeerStories(c.AccountID, c.ChatID)\n"
    "\t\ta.storyFetchDone(gen, c.AccountID, c.ChatID, raw, err)\n"
    "\t}()\n"
    "}\n"
    "\n"
    "// storyFetchDone installs the fetch result (extracted from the open\n"
    "// goroutine; stage-1 body is the original in-place tail — the shape\n"
    "// the R53 pin proves racy).\n"
    "func (a *App) storyFetchDone(gen int, accountID, chatID, raw string, err error) {\n"
    "\ta.mu.Lock()\n"
    "\tsv := a.storyView\n"
    "\tif sv == nil || a.storyViewGen != gen || sv.chatID != chatID || sv.accountID != accountID {\n"
    "\t\ta.mu.Unlock()\n"
    "\t\treturn // the viewer closed or reopened meanwhile\n"
    "\t}\n"
    "\tsv.loading = false\n"
    "\tif err != nil {\n"
    "\t\tsv.err = err.Error()\n"
    "\t} else {\n"
    "\t\titems, perr := parseStories(raw)\n"
    "\t\tif perr != nil {\n"
    "\t\t\tsv.err = perr.Error()\n"
    "\t\t} else {\n"
    "\t\t\tsv.items = items\n"
    "\t\t}\n"
    "\t}\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "}\n"
)
s = sub_once(s, old_open, new_open, "openStoryViewer tail extraction")
STORIES.write_text(s)

# --- state.go: the gen field --------------------------------------------
t = STATE.read_text()
old_field = (
    "\t// story viewer (slice 104)\n"
    "\tstoryView *storyViewerState\n"
)
new_field = (
    "\t// story viewer (slice 104); storyViewGen is its session key (R54)\n"
    "\tstoryView    *storyViewerState\n"
    "\tstoryViewGen int\n"
)
t = sub_once(t, old_field, new_field, "state.go storyViewGen field")
STATE.write_text(t)

print("stage 1 applied: extraction + gen field")
