#!/usr/bin/env python3
"""Move R31 from BUGS Open to Fixed (with fix evidence)."""

p = 'BUGS.md'
s = open(p).read()

# 1. Cut the R31 Open row.
start = s.index('| R31 | go/gui/state.go + topics.go')
end = s.index('\n', start)
open_row = s[start:end]
s = s[:start] + s[end+1:]

# 2. Open-line back to the R30 state (R31 now fixed).
old_line = '*Open: R31 (fix next — iteration 19), R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R30 verified/fixed (Fixed table).*'
new_line = '*Open: R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R31 verified/fixed (Fixed table).*'
assert s.count(old_line) == 1
s = s.replace(old_line, new_line)

# 3. Fixed row (adapted from the Open row + the fix).
fixed_row = (
    "| R31 | **Four async installers of a.messages had no install-time "
    "staleness guard — a chat (or scope) switch mid-fetch installed the "
    "OLD view's window (and msgFor) into the NEW view.** Unguarded: "
    "openChat's load goroutine (`a.messages = msgs; a.msgFor = &k` "
    "unconditionally), mergeMessages (refreshMessages' install), "
    "openForumTopic's goroutine, and loadOlder (prepended the old chat's "
    "older page onto the new chat's window; also re-read a.messages[0] on "
    "the goroutine, outside the lock, for the tag-scope offset). "
    "messageList renders f.messages with no msgFor==selected check and "
    "send paths resolve the target via f.msgFor — a stale install showed "
    "chat A's messages under chat B's header AND directed the next send "
    "to A. Found at chunk-3 iteration 19 reading state.go's remaining "
    "body; the codebase already had the right per-site pattern "
    "(savedsublists/comments/topics-jump/chrome: selected==k + scope "
    "match under the install lock) — these four predated or missed it. | "
    "Wrong-content + message-misdirection class; window = the engine-call "
    "duration (fast click-through hits it, slow networks widen it). | "
    "Generation counter, one mechanism for the whole class: a.uiGen "
    "(App, under a.mu) increments at every message-scope reset — openChat, "
    "both deselect paths, openForumTopic, jumpToTopicMessageAt, "
    "backToForumTopics, openCommentThread, openCommentThreadDeep, "
    "closeCommentThread, openSavedTag, openSavedSublist, closeSavedSublist "
    "(12 sites). The four installers capture the gen before their engine "
    "call and install only if it still matches, via extracted bare-App-"
    "testable methods: applyOpenChatMessages (also consumes the deep-link "
    "pendings only on a live install), mergeMessages (gen param from "
    "refreshMessages), applyForumTopicWindow (selected+forumTopic+gen), "
    "applyOlderPage (selected+msgFor+gen; oldestID now snapshotted under "
    "the initial lock — the outside-lock read is gone); jumpToMessageAt "
    "gained the same gen check at its install. RED-first: "
    "deadinstalls_r31_test.go ×4 (compile seam; stale-gen, moved-selection "
    "and live-gen paths each). Full gui suite green; gofmt clean. |"
)

anchor = '| R30 | **The R29 dead-button class was systemic'
assert s.count(anchor) == 1
s = s.replace(anchor, fixed_row + '\n' + anchor)

open(p, 'w').write(s)
print("BUGS.md: R31 moved Open -> Fixed")
