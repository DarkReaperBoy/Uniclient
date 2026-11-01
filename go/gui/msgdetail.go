package gui

import (
	"fmt"
	"image/color"
	"strconv"
	"time"

	"gioui.org/font"
	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/io/pointer"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

type detailRow struct {
	label  string
	value  string
	action string
}

func detailStamp(ts int64, now time.Time) string {
	if ts <= 0 {
		return ""
	}
	t := time.Unix(ts, 0)
	if t.Format("2006-01-02") == now.Format("2006-01-02") {
		return t.Format("15:04:05")
	}
	return t.Format("2 Jan 2006 · 15:04")
}

func detailStatusText(status int) string {
	switch status {
	case engine.MsgStatusSending:
		return "sending"
	case engine.MsgStatusSent:
		return "sent"
	case engine.MsgStatusRead:
		return "read"
	case engine.MsgStatusFailed:
		return "failed to send"
	}
	return ""
}

func dcNameLabel(dc int) string {
	if dc < 1 {
		return ""
	}
	place := "UNKNOWN"
	switch dc {
	case 1, 3:
		place = "Miami FL, USA"
	case 2, 4:
		place = "Amsterdam, NL"
	case 5:
		place = "Singapore, SG"
	}
	return fmt.Sprintf("DC%d, %s", dc, place)
}

func msgDetailRows(m engine.CachedMessage, now time.Time, stickerAuthor string) []detailRow {
	var rows []detailRow
	add := func(label, value string) {
		if value != "" {
			rows = append(rows, detailRow{label: label, value: value})
		}
	}
	add("Message ID", m.MsgID)
	if !m.IsService {
		switch {
		case m.SenderName != "" && m.SenderID != "":
			add("Sender", m.SenderName+" ("+m.SenderID+")")
		case m.SenderName != "":
			add("Sender", m.SenderName)
		case m.SenderID != "":
			add("Sender", "user "+m.SenderID)
		}
	}
	add("Sent", detailStamp(m.Timestamp, now))
	add("Edited", detailStamp(m.EditedAt, now))
	if m.IsDeleted {
		add("Deleted", detailStamp(m.DeletedAt, now))
	}
	add("Status", detailStatusText(m.Status))
	add("Forwarded from", m.ForwardFrom)
	add("Reply to", m.ReplyToID)
	if m.Views > 0 {
		add("Views", viewsCountLabel(m.Views))
	}
	if m.Forwards > 0 {
		add("Forwards", viewsCountLabel(m.Forwards))
	}
	if m.HasMedia || m.MediaFileName != "" || m.MediaFileSize > 0 {
		add("File", m.MediaFileName)
		add("Type", m.MediaMimeType)
		if m.MediaFileSize > 0 {
			add("Size", fmtBytes(m.MediaFileSize))
		}
		if m.MediaWidth > 0 && m.MediaHeight > 0 {
			add("Dimensions", fmt.Sprintf("%d × %d", m.MediaWidth, m.MediaHeight))
		}
		if m.MediaDuration > 0 {
			add("Duration", fmtDur(m.MediaDuration))
		}
		add("Datacenter", dcNameLabel(m.MediaDC))
		add("Saved at", m.MediaLocalPath)
	}
	if m.IsPinned {
		add("Pinned", "yes")
	}
	if m.IsSilent {
		add("Silent", "yes")
	}
	if m.NoForwards {
		add("Forwarding restricted", "yes")
	}
	if authorID := engine.StickerPackAuthorID(m.StickerSetID()); authorID != 0 {
		value := stickerAuthor
		if value == "" {
			value = fmt.Sprintf("user %d", authorID)
		}
		rows = append(rows, detailRow{label: "Sticker author", value: value, action: "author"})
	}
	return rows
}

func msgDetailMenuGate(m engine.CachedMessage) bool { return !m.IsService }

type msgDetailState struct {
	msg        engine.CachedMessage
	authorID   int64
	authorName string
}

var (
	detailKeyTag = new(struct{})
)

func (a *App) openMsgDetailDialog(m *engine.CachedMessage) {
	if m == nil || !msgDetailMenuGate(*m) {
		return
	}
	msg := *m
	authorID := engine.StickerPackAuthorID(msg.StickerSetID())
	a.mu.Lock()
	a.msgDetailDlg = &msgDetailState{msg: msg, authorID: authorID}
	a.mu.Unlock()
	a.invalidate()
	if authorID == 0 {
		return
	}
	go func() {
		if prof, err := a.eng.GetUserProfile(msg.AccountID, strconv.FormatInt(authorID, 10)); err == nil && prof != nil {
			a.mu.Lock()
			if a.msgDetailDlg != nil && a.msgDetailDlg.msg.MsgID == msg.MsgID {
				a.msgDetailDlg.authorName = prof.DisplayName
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}()
}

func (a *App) openMsgDetailAuthor(d *msgDetailState) {
	if d == nil || d.authorID == 0 {
		return
	}
	title := d.authorName
	if title == "" {
		title = fmt.Sprintf("user %d", d.authorID)
	}
	a.closeMsgDetailDialog()
	a.openChat(chatKey{AccountID: d.msg.AccountID, ChatID: strconv.FormatInt(d.authorID, 10)}, title)
}

func (a *App) closeMsgDetailDialog() {
	a.mu.Lock()
	a.msgDetailDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) layoutMsgDetail(gtx layout.Context, f frame) layout.Dimensions {
	d := f.msgDetailDlg
	rows := msgDetailRows(d.msg, f.now, d.authorName)

	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, detailKeyTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{Name: key.NameEscape})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			a.closeMsgDetailDialog()
		}
	}

	for {
		ev, ok := gtx.Source.Event(pointer.Filter{Target: detailBgTag, Kinds: pointer.Press})
		if !ok {
			break
		}
		if _, is := ev.(pointer.Event); is {
			a.closeMsgDetailDialog()
		}
	}
	{
		stack := clip.Rect{Max: gtx.Constraints.Max}.Push(gtx.Ops)
		event.Op(gtx.Ops, detailBgTag)
		stack.Pop()
	}
	paintFill(gtx.Ops, scrimColor(), gtx.Constraints.Max)

	if a.wid.detailCloseBtn.Clicked(gtx) {
		a.closeMsgDetailDialog()
	}
	growClickables(&a.wid.detailRowBtns, len(rows))
	for i := range rows {
		if btn := &a.wid.detailRowBtns[i]; btn.Clicked(gtx) {
			if rows[i].action == "author" {
				a.openMsgDetailAuthor(d)
			} else {
				a.copyTextSoon(rows[i].value)
				a.setToast("Copied")
			}
		}
	}

	cardW := gtx.Dp(unit.Dp(340))
	if cardW > gtx.Constraints.Max.X-gtx.Dp(unit.Dp(32)) {
		cardW = gtx.Constraints.Max.X - gtx.Dp(unit.Dp(32))
	}
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = cardW
		gtx.Constraints.Min.X = cardW
		return roundedFill(gtx, a.ui.p.Surface, 14, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(16), "Message details")
								lbl.Font.Weight = font.SemiBold
								return lbl.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.IconButton(&a.wid.detailCloseBtn, iconContentClear, "Close")
								btn.Color = a.ui.p.TextDim
								return btn.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Dim(unit.Sp(11), "Tap a row to copy its value")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if len(rows) == 0 {
							lbl := a.ui.Dim(unit.Sp(13), "No details")
							lbl.Color = a.ui.p.TextFaint
							return lbl.Layout(gtx)
						}
						list := material.List(a.ui.Theme, &a.wid.detailList)
						maxH := gtx.Constraints.Max.Y - gtx.Dp(unit.Dp(180))
						if maxH < gtx.Dp(unit.Dp(120)) {
							maxH = gtx.Dp(unit.Dp(120))
						}
						gtx.Constraints.Max.Y = maxH
						return list.Layout(gtx, len(rows), func(gtx layout.Context, i int) layout.Dimensions {
							return a.detailRowWidget(gtx, rows[i], &a.wid.detailRowBtns[i])
						})
					}),
				)
			})
		})
	})
}

func (a *App) detailRowWidget(gtx layout.Context, r detailRow, btn *widget.Clickable) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		bl := material.ButtonLayout(a.ui.Theme, btn)
		bl.Background = a.ui.p.Surface
		bl.CornerRadius = 8
		return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						gtx.Constraints.Max.X = gtx.Dp(unit.Dp(110))
						lbl := a.ui.Dim(unit.Sp(12), r.label)
						lbl.Color = a.ui.p.TextDim
						return lbl.Layout(gtx)
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), r.value)
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

var detailBgTag = new(struct{})

func scrimColor() color.NRGBA {
	return color.NRGBA{R: 0x00, G: 0x00, B: 0x00, A: 0xB0}
}
