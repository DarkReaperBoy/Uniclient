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

type restrictDuration struct {
	label string
	secs  int
}

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

type restrictPermissionRow struct {
	label string
	field string
}

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

func banUntilDate(now time.Time, secs int) int {
	if secs <= 0 {
		return 0
	}
	return int(now.Unix()) + secs
}

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

func initialRestrictRights(m engine.MemberInfo) *engine.DefaultBannedRights {
	if m.BannedRights != nil {
		br := *m.BannedRights
		return &br
	}
	return &engine.DefaultBannedRights{}
}

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

type restrictDlgState struct {
	chat   engine.ChatInfo
	member engine.MemberInfo
	mode   string
	durIdx int
	busy   bool
}

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

func (a *App) openBanDialog(chat engine.ChatInfo, m engine.MemberInfo) {
	a.mu.Lock()
	a.restrictDlg = &restrictDlgState{chat: chat, member: m, mode: "ban"}
	a.memberMenu = nil
	a.mu.Unlock()
	a.invalidate()
}

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
			go a.loadPanel(k)
		}
	}()
}

func (a *App) layoutRestrictDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.restrictDlg
	if a.wid.restrictDlgCancel.Clicked(gtx) {
		a.closeRestrictDialog()
	}
	if a.wid.restrictDlgApply.Clicked(gtx) {
		a.submitRestrictDialog()
	}

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
