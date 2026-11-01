#!/usr/bin/env python3
"""R53/R54/R55 stage 2 — copy-on-write conversion, the fix.

Every writer of the frame-carried *storyViewerState goes through the
updateStoryView installer (fresh struct install under a.mu); reaction
flips deep-copy the items slice (R38 rule); the fetch tail and react
revert tail are gen-guarded (R54); closeStoryViewer clears the reply
draft (R55). The strip's pointless `go openStoryViewer` is dropped.
"""
import pathlib

GUI = pathlib.Path("go/gui")
STORIES = GUI / "stories.go"


def sub_once(text, old, new, what):
    n = text.count(old)
    assert n == 1, f"{what}: expected 1 occurrence, found {n}"
    return text.replace(old, new)


s = STORIES.read_text()

# --- storyFetchDone: in-place body -> installer --------------------------
old = (
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
new = (
    "func (a *App) storyFetchDone(gen int, accountID, chatID, raw string, err error) {\n"
    "\tif !a.updateStoryView(func(sv *storyViewerState) bool {\n"
    "\t\tif a.storyViewGen != gen || sv.accountID != accountID || sv.chatID != chatID {\n"
    "\t\t\treturn false\n"
    "\t\t}\n"
    "\t\tsv.loading = false\n"
    "\t\tif err != nil {\n"
    "\t\t\tsv.err = err.Error()\n"
    "\t\t\treturn true\n"
    "\t\t}\n"
    "\t\titems, perr := parseStories(raw)\n"
    "\t\tif perr != nil {\n"
    "\t\t\tsv.err = perr.Error()\n"
    "\t\t\treturn true\n"
    "\t\t}\n"
    "\t\tsv.items = items\n"
    "\t\treturn true\n"
    "\t}) {\n"
    "\t\treturn\n"
    "\t}\n"
    "\ta.invalidate()\n"
    "}\n"
)
s = sub_once(s, old, new, "storyFetchDone CoW body")

# --- closeStoryViewer: gen bump + draft clear (R55) ----------------------
old = (
    "// closeStoryViewer dismisses the overlay.\n"
    "func (a *App) closeStoryViewer() {\n"
    "\ta.mu.Lock()\n"
    "\ta.storyView = nil\n"
    "\ta.mu.Unlock()\n"
    "\ta.invalidate()\n"
    "}\n"
)
new = (
    "// closeStoryViewer dismisses the overlay. R55: the reply draft is\n"
    "// viewer-session state — cleared on close so the next open (any chat)\n"
    "// starts empty, never showing another story's half-written reply.\n"
    "// GUI-loop-only (storyReplyEd); every caller is a viewer key, click or\n"
    "// tap.\n"
    "func (a *App) closeStoryViewer() {\n"
    "\ta.mu.Lock()\n"
    "\ta.storyView = nil\n"
    "\ta.storyViewGen++\n"
    "\ta.mu.Unlock()\n"
    "\ta.wid.storyReplyEd.SetText(\"\")\n"
    "\ta.invalidate()\n"
    "}\n"
)
s = sub_once(s, old, new, "closeStoryViewer")

# --- storyAdvance: installer + the two new helpers -----------------------
old = (
    "func (a *App) storyAdvance(delta int) {\n"
    "\ta.mu.Lock()\n"
    "\tsv := a.storyView\n"
    "\tif sv == nil {\n"
    "\t\ta.mu.Unlock()\n"
    "\t\treturn\n"
    "\t}\n"
    "\tsv.cur = storyStep(sv.cur, delta, len(sv.items))\n"
    "\tlast := sv.cur >= len(sv.items)-1\n"
    "\ta.mu.Unlock()\n"
    "\tif delta > 0 && last {\n"
    "\t\ta.closeStoryViewer()\n"
    "\t\treturn\n"
    "\t}\n"
    "\ta.invalidate()\n"
    "}\n"
)
new = (
    "func (a *App) storyAdvance(delta int) {\n"
    "\tlast := false\n"
    "\tif !a.updateStoryView(func(sv *storyViewerState) bool {\n"
    "\t\tsv.cur = storyStep(sv.cur, delta, len(sv.items))\n"
    "\t\tlast = sv.cur >= len(sv.items)-1\n"
    "\t\treturn true\n"
    "\t}) {\n"
    "\t\treturn\n"
    "\t}\n"
    "\tif delta > 0 && last {\n"
    "\t\ta.closeStoryViewer()\n"
    "\t\treturn\n"
    "\t}\n"
    "\ta.invalidate()\n"
    "}\n"
    "\n"
    "// updateStoryView copy-on-write installs a mutated story-viewer head.\n"
    "// R53: storyViewerState is frame-carried as a POINTER, so the frame and\n"
    "// the head share the struct — every writer goes through here so a\n"
    "// frame's snapshot stays immutable while background tails run.\n"
    "func (a *App) updateStoryView(fn func(sv *storyViewerState) bool) bool {\n"
    "\ta.mu.Lock()\n"
    "\tdefer a.mu.Unlock()\n"
    "\tif a.storyView == nil {\n"
    "\t\treturn false\n"
    "\t}\n"
    "\tsv := *a.storyView\n"
    "\tif !fn(&sv) {\n"
    "\t\treturn false\n"
    "\t}\n"
    "\ta.storyView = &sv\n"
    "\treturn true\n"
    "}\n"
    "\n"
    "// flipStoryReaction installs SentReaction=to on the story currently\n"
    "// showing `from` (deep item copy — the frame's items slice stays\n"
    "// untouched, the R38 rule). False when the viewer moved on, the story\n"
    "// is gone, or a newer reaction already replaced ours.\n"
    "func (a *App) flipStoryReaction(accountID, chatID string, storyID int, from, to string) bool {\n"
    "\treturn a.updateStoryView(func(sv *storyViewerState) bool {\n"
    "\t\tif sv.accountID != accountID || sv.chatID != chatID {\n"
    "\t\t\treturn false\n"
    "\t\t}\n"
    "\t\tfor i := range sv.items {\n"
    "\t\t\tif sv.items[i].ID != storyID {\n"
    "\t\t\t\tcontinue\n"
    "\t\t\t}\n"
    "\t\t\tif sv.items[i].SentReaction != from {\n"
    "\t\t\t\treturn false\n"
    "\t\t\t}\n"
    "\t\t\titems := make([]storyItem, len(sv.items))\n"
    "\t\t\tcopy(items, sv.items)\n"
    "\t\t\titems[i].SentReaction = to\n"
    "\t\t\tsv.items = items\n"
    "\t\t\treturn true\n"
    "\t\t}\n"
    "\t\treturn false\n"
    "\t})\n"
    "}\n"
)
s = sub_once(s, old, new, "storyAdvance + helpers")

# --- strip click: drop the pointless goroutine ---------------------------
old = "\t\t\t\t\tgo a.openStoryViewer(c) // GUI-safe: state set under lock\n"
new = "\t\t\t\t\ta.openStoryViewer(c)\n"
s = sub_once(s, old, new, "strip click go-drop")

# --- storyActionRow: own dedupe + click sites through the installer ------
old = "\town := sv.chatID != \"\" && sv.chatID == accountByID(f, sv.accountID).SelfUserID\n"
new = "\town := storyViewerOwn(f, sv)\n"
s = sub_once(s, old, new, "own dedupe")

old = (
    "\tif a.wid.storyReactBtn.Clicked(gtx) {\n"
    "\t\temoji, open := storyHeartAction(it.SentReaction)\n"
    "\t\tif open {\n"
    "\t\t\tsv.reactOpen = !sv.reactOpen\n"
    "\t\t\ta.loadAvailEmojis(sv.accountID)\n"
    "\t\t} else {\n"
    "\t\t\ta.storyReact(sv, it, emoji)\n"
    "\t\t\tsv.reactOpen = false\n"
    "\t\t}\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
    "\tif a.wid.storyReplyBtn.Clicked(gtx) {\n"
    "\t\tsv.replyOn = !sv.replyOn\n"
    "\t\tsv.reactOpen = false\n"
    "\t\tif sv.replyOn {\n"
    "\t\t\tgtx.Execute(key.FocusCmd{Tag: &a.wid.storyReplyEd})\n"
    "\t\t}\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
)
new = (
    "\tif a.wid.storyReactBtn.Clicked(gtx) {\n"
    "\t\temoji, open := storyHeartAction(it.SentReaction)\n"
    "\t\tif open {\n"
    "\t\t\ta.updateStoryView(func(s *storyViewerState) bool { s.reactOpen = !s.reactOpen; return true })\n"
    "\t\t\ta.loadAvailEmojis(sv.accountID)\n"
    "\t\t} else {\n"
    "\t\t\ta.storyReact(sv, it, emoji)\n"
    "\t\t\ta.updateStoryView(func(s *storyViewerState) bool { s.reactOpen = false; return true })\n"
    "\t\t}\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
    "\tif a.wid.storyReplyBtn.Clicked(gtx) {\n"
    "\t\treplyOn := false\n"
    "\t\ta.updateStoryView(func(s *storyViewerState) bool {\n"
    "\t\t\ts.replyOn = !s.replyOn\n"
    "\t\t\ts.reactOpen = false\n"
    "\t\t\treplyOn = s.replyOn\n"
    "\t\t\treturn true\n"
    "\t\t})\n"
    "\t\tif replyOn {\n"
    "\t\t\tgtx.Execute(key.FocusCmd{Tag: &a.wid.storyReplyEd})\n"
    "\t\t}\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
)
s = sub_once(s, old, new, "react/reply click sites")

old = (
    "\tif a.wid.storyReplyXBtn.Clicked(gtx) {\n"
    "\t\tsv.replyOn = false\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
)
new = (
    "\tif a.wid.storyReplyXBtn.Clicked(gtx) {\n"
    "\t\ta.updateStoryView(func(s *storyViewerState) bool { s.replyOn = false; return true })\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
)
s = sub_once(s, old, new, "reply-cancel click")

# --- emoji strip click ----------------------------------------------------
old = (
    "\t\tif a.wid.storyReactEmojiBtn[i].Clicked(gtx) {\n"
    "\t\t\ta.storyReact(sv, it, e)\n"
    "\t\t\ta.mu.Lock()\n"
    "\t\t\tsv.reactOpen = false\n"
    "\t\t\ta.mu.Unlock()\n"
    "\t\t\ta.invalidate()\n"
    "\t\t\tbreak\n"
    "\t\t}\n"
)
new = (
    "\t\tif a.wid.storyReactEmojiBtn[i].Clicked(gtx) {\n"
    "\t\t\ta.storyReact(sv, it, e)\n"
    "\t\t\ta.updateStoryView(func(s *storyViewerState) bool { s.reactOpen = false; return true })\n"
    "\t\t\ta.invalidate()\n"
    "\t\t\tbreak\n"
    "\t\t}\n"
)
s = sub_once(s, old, new, "emoji strip click")

# --- storyReact: optimistic flip via installer + guarded revert tail -----
old = (
    "func (a *App) storyReact(sv *storyViewerState, it *storyItem, emoji string) {\n"
    "\tprev := it.SentReaction\n"
    "\tit.SentReaction = emoji\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\tif err := a.eng.ReactToStory(sv.accountID, sv.chatID, it.ID, emoji); err != nil {\n"
    "\t\t\ta.mu.Lock()\n"
    "\t\t\tit.SentReaction = prev\n"
    "\t\t\ta.mu.Unlock()\n"
    "\t\t\ta.setToast(\"React: \" + err.Error())\n"
    "\t\t\ta.invalidate()\n"
    "\t\t}\n"
    "\t}()\n"
    "}\n"
)
new = (
    "func (a *App) storyReact(sv *storyViewerState, it *storyItem, emoji string) {\n"
    "\taccountID, chatID, storyID, prev := sv.accountID, sv.chatID, it.ID, it.SentReaction\n"
    "\tif !a.flipStoryReaction(accountID, chatID, storyID, prev, emoji) {\n"
    "\t\treturn\n"
    "\t}\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\ta.storyReactDone(accountID, chatID, storyID, emoji,\n"
    "\t\t\ta.eng.ReactToStory(accountID, chatID, storyID, emoji))\n"
    "\t}()\n"
    "}\n"
    "\n"
    "// storyReactDone reverts the optimistic flip when the engine call\n"
    "// failed. R53: only while the same viewer still shows OUR emoji — a\n"
    "// newer reaction must not be stomped, and a closed/reopened viewer is\n"
    "// not touched (the error still toasts — the react really was sent).\n"
    "func (a *App) storyReactDone(accountID, chatID string, storyID int, emoji string, err error) {\n"
    "\tif err != nil {\n"
    "\t\ta.flipStoryReaction(accountID, chatID, storyID, emoji, \"\")\n"
    "\t\ta.setToast(\"React: \" + err.Error())\n"
    "\t\ta.invalidate()\n"
    "\t}\n"
    "}\n"
)
s = sub_once(s, old, new, "storyReact + storyReactDone")

# --- storySendReply: replyOn through the installer ------------------------
old = (
    "\ta.wid.storyReplyEd.SetText(\"\")\n"
    "\tsv.replyOn = false\n"
    "\ta.invalidate()\n"
    "\tgo func() {\n"
    "\t\t_, err := a.eng.SendMessage(sv.accountID, sv.chatID, text, storyReplyID(it.ID), nil, false, 0, \"\", \"\", false, false, false, false, false)\n"
)
new = (
    "\ta.wid.storyReplyEd.SetText(\"\")\n"
    "\ta.updateStoryView(func(s *storyViewerState) bool { s.replyOn = false; return true })\n"
    "\ta.invalidate()\n"
    "\taccountID, chatID, storyID := sv.accountID, sv.chatID, it.ID\n"
    "\tgo func() {\n"
    "\t\t_, err := a.eng.SendMessage(accountID, chatID, text, storyReplyID(storyID), nil, false, 0, \"\", \"\", false, false, false, false, false)\n"
)
s = sub_once(s, old, new, "storySendReply")

STORIES.write_text(s)
print("stage 2 applied: copy-on-write conversion complete")
