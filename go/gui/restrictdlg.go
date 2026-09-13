package gui

import (
	"fmt"
	"image"
	"image/color"
	"time"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Restrict/ban boxes (slice 191, tdesktop's RestrictParticipantBox and the
// ban box — parity row "Moderation (admin log, restrictions)"): opened from
// the member menu. Restrict = duration ladder + one switch per
// DefaultBannedRights permission (allowed ↔ banned inversion at the wire);
// Ban = duration ladder + confirm. The box initializes from the member's
// CURRENT server rights when the member list carried them (restricted
// rows), else all-allowed (tdesktop fresh-restriction semantics).

// restrictDuration is one row of the duration ladder.
type restrictDuration struct {
	label string
	secs  int // 0 = forever
}

// restrictDurations: tdesktop's restrict/ban duration ladder.
var restrictDurations = []restrictDuration{
	{"Forever", 0},
	{"1 hour", 3600},
	{"8 hours", 8 * 3600},
	{"2 days", 2 * 86400},
	{"1 week", 604800},
	{"1 month", 30 * 86400},
	{"3 months", 3 * 30 * 86400},
	{"6 months", 6 * 30 * 86400},
	{"1 year", 365 * 86400},
}

// restrictPermissionRow is one permission switch (field names match
// engine.DefaultBannedRights 1:1).
type restrictPermissionRow struct {
	label string
	field string
}

// restrictPermissionRows: tdesktop's restrict-box permission set, mapped to
// the engine's DefaultBannedRights fields.
func restrictPermissionRows() []restrictPermissionRow {
	return []restrictPermissionRow{
		{"Send messages", "SendPlain"},
		{"Send photos", "SendPhotos"},
		{"Send videos", "SendVideos"},
		{"Send video notes", "SendRoundvideos"},
		{"Send music", "SendAudios"},
		{"Send voice messages", "SendVoices"},
		{"Send files", "SendDocs"},
		{"Send stickers & GIFs", "SendStickers"},
		{"Embed links", "EmbedLinks"},
		{"Send polls", "SendPolls"},
		{"Add members", "InviteUsers"},
		{"Pin messages", "PinMessages"},
		{"Manage topics", "ManageTopics"},
		{"Change chat info", "ChangeInfo"},
		{"Edit admin rank", "EditRank"},
	}
}

// banUntilDate (pure): the wire until-timestamp for a duration row. 0 secs
// = forever = 0 on the wire (Telegram semantics).
func banUntilDate(now time.Time, secs int) int {
	if secs <= 0 {
		return 0
	}
	return int(now.Unix()) + secs
}

// bannedRightsFromAllowed inverts the GUI's allowed-switch map into the
// wire's banned-rights struct (fields absent from the map = allowed —
// partial maps never ban by omission). Pure.
func bannedRightsFromAllowed(allowed map[string]bool) *engine.DefaultBannedRights {
	br := &engine.DefaultBannedRights{}
	for _, r := range restrictPermissionRows() {
		if v, ok := allowed[r.field]; ok && !v {
			switch r.field {
			case "SendPlain":
				br.SendPlain = true
			case "SendPhotos":
				br.SendPhotos = true
			case "SendVideos":
				br.SendVideos = true
			case "SendRoundvideos":
				br.SendRoundvideos = true
			case "SendAudios":
				br.SendAudios = true
			case "SendVoices":
				br.SendVoices = true
			case "SendDocs":
				br.SendDocs = true
			case "SendStickers":
				br.SendStickers = true
			case "EmbedLinks":
				br.EmbedLinks = true
			case "SendPolls":
				br.SendPolls = true
			case "InviteUsers":
				br.InviteUsers = true
			case "PinMessages":
				br.PinMessages = true
			case "ManageTopics":
				br.ManageTopics = true
			case "ChangeInfo":
				br.ChangeInfo = true
			case "EditRank":
				br.EditRank = true
			}
		}
	}
	return br
}

// initialRestrictRights resolves the box's starting state: the member's
// current rights when the list carried them, else all allowed. Pure.
func initialRestrictRights(m engine.MemberInfo) *engine.DefaultBannedRights {
	if m.BannedRights != nil {
		br := *m.BannedRights
		return &br
	}
	return &engine.DefaultBannedRights{}
}

// fieldOfRights reads one DefaultBannedRights field by name (the banned
// polarity: true = banned). Pure.
func fieldOfRights(br *engine.DefaultBannedRights, field string) bool {
	switch field {
	case "SendPlain":
		return br.SendPlain
	case "SendPhotos":
		return br.SendPhotos
	case "SendVideos":
		return br.SendVideos
	case "SendRoundvideos":
		return br.SendRoundvideos
	case "SendAudios":
		return br.SendAudios
	case "SendVoices":
		return br.SendVoices
	case "SendDocs":
		return br.SendDocs
	case "SendStickers":
		return br.SendStickers
	case "EmbedLinks":
		return br.EmbedLinks
	case "SendPolls":
		return br.SendPolls
	case "InviteUsers":
		return br.InviteUsers
	case "PinMessages":
		return br.PinMessages
	case "ManageTopics":
		return br.ManageTopics
	case "ChangeInfo":
		return br.ChangeInfo
	case "EditRank":
		return br.EditRank
	}
	return false
}

// restrictDlgState: open box (nil when closed). mode: "restrict" | "ban".
type restrictDlgState struct {
	chat   engine.ChatInfo
	member engine.MemberInfo
	mode   string
	durIdx int
	busy   bool
}

// openRestrictDialog opens the restrict box for a member. The permission
// switches start from the member's current rights (or all-allowed).
func (a *App) openRestrictDialog(chat engine.ChatInfo, m engine.MemberInfo) {
	br := initialRestrictRights(m)
	rows := restrictPermissionRows()
	growBools(&a.wid.restrictDlgSw, len(rows))
	for i, r := range rows {
		a.wid.restrictDlgSw[i].Value = !fieldOfRights(br, r.field)
	}
	a.mu.Lock()
	a.restrictDlg = &restrictDlgState{chat: chat, member: m, mode: "restrict"}
	a.memberMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// openBanDialog opens the ban box for a member.
func (a *App) openBanDialog(chat engine.ChatInfo, m engine.MemberInfo) {
	a.mu.Lock()
	a.restrictDlg = &restrictDlgState{chat: chat, member: m, mode: "ban"}
	a.memberMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

// closeRestrictDialog dismisses (blocked while applying).
func (a *App) closeRestrictDialog() {
	a.mu.Lock()
	if a.restrictDlg == nil || a.restrictDlg.busy {
		a.mu.Unlock()
		return
	}
	a.restrictDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// submitRestrictDialog applies the box (async): restrict →
// RestrictMemberWithRights (rights + untilDate, the switch values read on
// the GUI goroutine); ban → BanMemberUntil.
func (a *App) submitRestrictDialog() {
	a.mu.Lock()
	if a.restrictDlg == nil || a.restrictDlg.busy {
		a.mu.Unlock()
		return
	}
	d := *a.restrictDlg
	dur := 0
	if d.durIdx >= 0 && d.durIdx < len(restrictDurations) {
		dur = restrictDurations[d.durIdx].secs
	}
	// Snapshot the switch values under the lock (GUI goroutine only).
	var allowed map[string]bool
	if d.mode == "restrict" {
		rows := restrictPermissionRows()
		allowed = make(map[string]bool, len(rows))
		for i, r := range rows {
			allowed[r.field] = i < len(a.wid.restrictDlgSw) && a.wid.restrictDlgSw[i].Value
		}
	}
	a.restrictDlg.busy = true
	a.mu.Unlock()

	go func() {
		var err error
		verb := "Restricted"
		if d.mode == "restrict" {
			until := banUntilDate(time.Now(), dur)
			err = a.eng.RestrictMemberWithRights(d.chat.AccountID, d.chat.ChatID, d.member.UserID, bannedRightsFromAllowed(allowed), until)
		} else {
			verb = "Banned"
			err = a.eng.BanMemberUntil(d.chat.AccountID, d.chat.ChatID, d.member.UserID, banUntilDate(time.Now(), dur))
		}
		a.mu.Lock()
		a.restrictDlg = nil
		a.mu.Unlock()
		a.invalidate()
		if err != nil {
			a.setToast(verb + " failed: " + err.Error())
			return
		}
		a.setToast(verb + " " + memberDisplayName(d.member))
		a.mu.Lock()
		k := a.panelChat
		a.mu.Unlock()
		if k.AccountID != "" {
			go a.loadPanel(k) // refresh the member list
		}
	}()
}

// layoutRestrictDialog renders the box centered over the window.
func (a *App) layoutRestrictDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.restrictDlg
	if a.wid.restrictDlgCancel.Clicked(gtx) {
		a.closeRestrictDialog()
	}
	if a.wid.restrictDlgApply.Clicked(gtx) {
		a.submitRestrictDialog()
	}

	// Scrim.
	paint.FillShape(gtx.Ops, color.NRGBA{R: 0, G: 0, B: 0, A: 0x66},
		clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Op())

	name := memberDisplayName(d.member)
	title := fmt.Sprintf("Restrict %s", name)
	applyLabel := "Restrict"
	if d.mode == "ban" {
		title = fmt.Sprintf("Ban %s?", name)
		applyLabel = "Ban"
	}
	if d.busy {
		applyLabel += "…"
	}

	rows := restrictPermissionRows()
	durs := restrictDurations
	growClickables(&a.wid.restrictDlgDurBtns, len(durs))
	growBools(&a.wid.restrictDlgSw, len(rows))

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(380))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				children := make([]layout.FlexChild, 0, 4+len(rows)+len(durs))
				children = append(children,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.H3(title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Duration")
							return lbl.Layout(gtx)
						})
					}),
				)
				// Duration chips.
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Spacing: layout.SpaceStart}.Layout(gtx,
						flexChildrenOf(len(durs), func(gtx layout.Context, i int) layout.Dimensions {
							btn := &a.wid.restrictDlgDurBtns[i]
							if btn.Clicked(gtx) {
								a.mu.Lock()
								if a.restrictDlg != nil && !a.restrictDlg.busy {
									a.restrictDlg.durIdx = i
								}
								a.mu.Unlock()
							}
							mb := material.Button(a.ui.Theme, btn, durs[i].label)
							mb.CornerRadius = 8
							mb.TextSize = unit.Sp(12)
							if d.durIdx == i {
								mb.Background = a.ui.p.Accent
							} else {
								mb.Background = a.ui.p.Surface
								mb.Color = a.ui.p.Text
							}
							return mb.Layout(gtx)
						})...)
				}))
				if d.mode == "restrict" {
					children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(12), "Permissions")
							return lbl.Layout(gtx)
						})
					}))
					for i := range rows {
						i := i
						children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							sw := material.Switch(a.ui.Theme, &a.wid.restrictDlgSw[i], "")
							sw.Color.Enabled = a.ui.p.Accent
							sw.Color.Disabled = a.ui.p.SurfaceHi
							sw.Color.Track = a.ui.p.SurfaceHi
							gtx.Constraints.Min.Y = gtx.Dp(unit.Dp(30))
							return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), rows[i].label)
									return layout.Inset{Top: unit.Dp(4)}.Layout(gtx, lbl.Layout)
								}),
								layout.Rigid(sw.Layout),
							)
						}))
					}
				}
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.TextButton(&a.wid.restrictDlgCancel, "Cancel")
								if d.busy {
									btn.Color = a.ui.p.TextFaint
								}
								return btn.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.TextButton(&a.wid.restrictDlgApply, applyLabel)
								btn.Color = a.ui.p.Error
								return btn.Layout(gtx)
							}),
						)
					})
				}))
				layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
				return layout.Dimensions{Size: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Min.Y)}
			})
		})
	})
}
