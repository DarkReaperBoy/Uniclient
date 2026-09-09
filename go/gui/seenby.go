package gui

// "Seen by" read receipts (AyuGram read receipts in small groups, matrix
// row 97, slice 98): the context menu on an own message in a DM or group
// gains "Seen by" — a dialog with the chat's last-read date (engine
// GetOutboxReadDate) and the per-user read list (engine
// GetMessageReadParticipantsDetailed: name + date). Privacy errors are
// honest sentences, never dead rows.

import (
	"image"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// seenDlgState is the open seen-by dialog (nil when closed).
type seenDlgState struct {
	msg        engine.CachedMessage
	parts      []map[string]interface{}
	readDate   int64
	readDateOK bool // the outbox read date resolved
	loaded     bool
	privacy    string // non-empty: the engine's privacy marker
}

var (
	seenDlgClose  widget.Clickable
	seenDlgKeyTag = new(struct{})
)

// seenByRowName (pure, testable): display name for one participant row.
func seenByRowName(entry map[string]interface{}) string {
	if n, ok := entry["name"].(string); ok && n != "" {
		return n
	}
	if id, ok := entry["user_id"].(int64); ok {
		return "user " + itoa(int(id))
	}
	return "someone"
}

// seenByPrivacyNote (pure, testable): the honest sentence for the
// engine's privacy error markers ("" = not a privacy error).
func seenByPrivacyNote(err string) string {
	switch err {
	case "privacy:my_hidden":
		return "Your privacy settings hide read participants."
	case "privacy:his_hidden":
		return "Their privacy settings hide read participants."
	case "privacy:too_old":
		return "This message is too old to list readers."
	}
	return ""
}

// seenByMenuGate (pure): own, non-service messages in chats Telegram
// gives read receipts for (DMs and groups — channels are broadcast,
// no per-reader receipts).
func seenByMenuGate(m engine.CachedMessage, chatType int) bool {
	if !m.IsOutgoing || m.IsService {
		return false
	}
	return chatType == engine.ChatTypeDMVal || chatType == engine.ChatTypeGroupVal || chatType == engine.ChatTypeTopicVal
}

// openSeenByDialog shows the read receipt for a message and loads it.
func (a *App) openSeenByDialog(m *engine.CachedMessage) {
	if m == nil {
		return
	}
	msg := *m
	a.mu.Lock()
	a.seenDlg = &seenDlgState{msg: msg}
	a.mu.Unlock()
	a.invalidate()
	a.loadSeenBy()
}

// closeSeenByDialog dismisses the dialog.
func (a *App) closeSeenByDialog() {
	a.mu.Lock()
	a.seenDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// loadSeenBy fetches the read date + participants.
func (a *App) loadSeenBy() {
	a.mu.Lock()
	d := a.seenDlg
	if d == nil {
		a.mu.Unlock()
		return
	}
	acc, chat, msgID := d.msg.AccountID, d.msg.ChatID, d.msg.MsgID
	a.mu.Unlock()

	go func() {
		parts, err := a.eng.GetMessageReadParticipantsDetailed(acc, chat, msgID)
		privacy := ""
		if err != nil {
			privacy = err.Error()
		}
		date, dateErr := a.eng.GetOutboxReadDate(acc, chat, msgID)
		a.mu.Lock()
		if a.seenDlg == nil {
			a.mu.Unlock()
			return
		}
		d := a.seenDlg
		d.loaded = true
		d.privacy = privacy
		if err == nil {
			d.parts = parts
		}
		if dateErr == nil {
			d.readDate = int64(date)
			d.readDateOK = true
		}
		a.mu.Unlock()
		if err != nil && seenByPrivacyNote(privacy) == "" {
			a.setToast("Seen by: " + err.Error())
		}
		a.invalidate()
	}()
}

// layoutSeenByDialog renders the read-receipt card over the chat pane.
func (a *App) layoutSeenByDialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.seenDlg
	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, seenDlgKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeSeenByDialog()
		}
	}
	if seenDlgClose.Clicked(gtx) {
		a.closeSeenByDialog()
	}

	paintScrimRect(gtx)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(340))
		gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(420))
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(14)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.H3("Seen by")
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&seenDlgClose, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							when := "Not read yet"
							if d.readDateOK && d.readDate > 0 {
								when = "Last read " + fmtTime(d.readDate)
							} else if d.readDateOK {
								when = "Not read yet"
							}
							lbl := a.ui.Dim(unit.Sp(12), when)
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						if !d.loaded {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return a.loadingNote(gtx)
							})
						}
						if note := seenByPrivacyNote(d.privacy); note != "" {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), note)
								return lbl.Layout(gtx)
							})
						}
						if len(d.parts) == 0 {
							return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(13), "Nobody has read this yet")
								lbl.Color = a.ui.p.TextFaint
								return lbl.Layout(gtx)
							})
						}
						rows := make([]layout.FlexChild, 0, len(d.parts))
						for _, p := range d.parts {
							rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return a.seenByRow(gtx, p)
							}))
						}
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.Spacing(4)}.Layout(gtx, rows...)
					}),
				)
			})
		})
	})
}

// seenByRow: name + read time.
func (a *App) seenByRow(gtx layout.Context, entry map[string]interface{}) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), seenByRowName(entry))
					lbl.MaxLines = 1
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					when := ""
					if date, ok := entry["date"].(int); ok && date > 0 {
						when = fmtTime(int64(date))
					}
					lbl := a.ui.Dim(unit.Sp(11), when)
					return lbl.Layout(gtx)
				}),
			)
		})
	})
}
