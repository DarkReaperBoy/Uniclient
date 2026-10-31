#!/usr/bin/env python3
"""Insert the R30 row into BUGS.md (Fixed table, above R29)."""
import sys

p = 'BUGS.md'
s = open(p).read()

row = (
    "| R30 | **The R29 dead-button class was systemic: 19 openers reachable "
    "from every-window surfaces set state only the MAIN window paints (dead "
    "buttons in separate chat windows, §1.10).** The sweep enumerated all 24 "
    "contentDialogSurface states + settingsOpen + the main-branch window "
    "modals (rate/clear/restrict/saved-delete) + mode 1, mapped every setter "
    "to its opener function, and intersected the callers with the "
    "separate-window render tree (Root's separate branch = chat view + "
    "media/IV/story/call/pip/toast/shortcuts overlays; the header menu, "
    "attach menu, message menu, info panel with member menu and mute clock, "
    "boost panel, call overlay, saved-lists pane, shortcuts and the call bar "
    "all render there). Dead in separate windows: header menu's Notification "
    "sound / Add members / Auto-delete / Send a gift / Change colors / Set "
    "wallpaper; attach menu's Music / Location / Contact; the info panel's "
    "mute-duration clock and member-menu Restrict / Ban; the message menu's "
    "\"Filter Like This…\"; the boost panel's prepaid-giveaway Launch cells; "
    "the call overlay's rating offer; the saved-lists row menu's Delete; "
    "Ctrl+J contacts; and worst, the call bar's JOIN — it set mode 1 (a "
    "layoutMain-only surface) after a real engine join, so the group-call UI "
    "appeared in NO window while the audio session ran with no leave "
    "affordance. | Direct §1.10 violation class (\"what cannot work is "
    "HIDDEN, never faked\") on the multi-window surface; the JOIN case "
    "orphaned a live call with no UI anywhere. Found at chunk-3 iteration 18 "
    "by the reachability analysis R29's watch item called for (calibration: "
    "the scanner's shape alone would not have found it — the openers are "
    "method calls, not package vars). | Per-surface fixes, all RED-first "
    "(deadopeners_r30_test.go, 7 tests): the pure derivation functions take "
    "a `separate` flag and drop the dead rows (headerMenuItems ×6, "
    "memberMenuItems ×2, savedSublistMenuActions ×1, attachMenuItems ×3); "
    "the inline gates share mainOnlySurfaceShown(a) (R29's "
    "profileMusicSectionShown generalized, separate.go) — mute clock hidden, "
    "\"Filter Like This…\" gated, prepaid Launch section dropped, rating "
    "offer skipped, Ctrl+J consumes the key without the dead opener; the "
    "call bar's JOIN became honest in every window: callBarJoin/"
    "applyCallJoinResult skip the mode flip in separate windows (where the "
    "bar itself is the in-call surface) and callBarInCall flips the button "
    "to LEAVE (leaveJoinedCall) once THIS window has joined THIS chat's call "
    "— main-window behavior unchanged. Direct engine actions (mute switch, "
    "promote/demote/remove/unban, pin/move) stay everywhere — they work from "
    "any window. Full gui suite green (attach-menu order test updated for "
    "the grouped items). |"
)

anchor = '| R29 | **The profile panel'
assert s.count(anchor) == 1, "R29 anchor not found"
s = s.replace(anchor, row + '\n' + anchor)

old_line = '*Open: R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R29 verified/fixed (Fixed table).*'
new_line = '*Open: R11 R12 R13 (MAP chunks 1-2) and R9 (owner decision). R10, R14-R30 verified/fixed (Fixed table).*'
assert s.count(old_line) == 1, "open-line not found"
s = s.replace(old_line, new_line)

open(p, 'w').write(s)
print("BUGS.md: R30 row added, open-line updated")
