#!/usr/bin/env python3
"""Insert the R31 row into BUGS.md Open table (topmost)."""

p = 'BUGS.md'
s = open(p).read()

row = (
    "| R31 | go/gui/state.go + topics.go | **Four async installers of "
    "a.messages have no install-time staleness guard — a chat switch "
    "mid-fetch installs the OLD chat's window (and msgFor) into the NEW "
    "chat.** Unguarded: state.go openChat's load goroutine (~1568: "
    "`a.messages = msgs; a.msgFor = &k` unconditionally — lands after a "
    "later openChat(B) reset), mergeMessages (959: refreshMessages' "
    "install), topics.go openForumTopic's goroutine (~183; its sibling "
    "loaders ARE guarded), and loadOlder (1718: prepends the old chat's "
    "older page onto the new chat's window; also reads a.messages[0] at "
    "1741 OUTSIDE the lock for the tag-scope offset — a data race by the "
    "letter). | Evidence: messageList (chat.go:613) renders f.messages "
    "with no msgFor==selected check, and send paths resolve the target "
    "via f.msgFor (chat.go:1490, voicerecord.go) — a stale install shows "
    "chat A's messages under chat B's header AND directs the next send "
    "to A. Reproduction window = the engine-call duration (fast local "
    "click-through can hit it; slow networks widen it). The codebase "
    "already has the right pattern (savedsublists.go 209/243, "
    "comments.go 152/226, topics.go 237/263, chrome.go 223: "
    "selected==k — plus scope match — under the install lock); these "
    "four predate or missed it. Found at chunk-3 iteration 19 reading "
    "state.go's remaining body (refreshMessages/mergeMessages/openChat/"
    "loadOlder). | Fix per the in-repo pattern: install-time guard "
    "(selected==k, +forumTopic==topicID for the topic loader, "
    "+msgFor==k for loadOlder) with the install extracted into "
    "bare-App-testable methods; fold the 1741 outside-lock read into "
    "the initial locked snapshot. RED tests: direct-call installs with "
    "a mismatched selection must drop. |"
)

anchor = '| R11 | cmd/uniclient/main.go'
assert s.count(anchor) == 1, "R11 anchor not found"
s = s.replace(anchor, row + '\n' + anchor)

old_line = '*Open: R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R30 verified/fixed (Fixed table).*'
new_line = '*Open: R31 (fix next — iteration 19), R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R30 verified/fixed (Fixed table).*'
assert s.count(old_line) == 1
s = s.replace(old_line, new_line)

open(p, 'w').write(s)
print("BUGS.md: R31 Open row added")
