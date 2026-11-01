package gui

import (
	"errors"
	"image"
	"image/color"
	"os"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/x/explorer"

	"uniclient/qrscan"
)

var ErrNotInvite = errors.New("QR code is not an invite link")

var inviteScanBtn widget.Clickable

var inviteScanExts = []string{".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp"}

func inviteHashFromQRImage(data []byte) (string, error) {
	payload, err := qrscan.DecodeBytes(data)
	if err != nil {
		return "", err
	}
	hash, ok := extractInviteHash(payload)
	if !ok {
		return "", ErrNotInvite
	}
	return hash, nil
}

func qrScanErrorText(err error) string {
	switch {
	case errors.Is(err, qrscan.ErrNotImage):
		return "That file is not an image"
	case errors.Is(err, qrscan.ErrNoQR):
		return "No QR code found in that image"
	case errors.Is(err, ErrNotInvite):
		return "QR code is not an invite link"
	default:
		return "Scan failed: " + err.Error()
	}
}

func (a *App) pickAndScanInviteQR() {
	go func() {
		if a.expl == nil {
			return
		}
		rcs, err := a.expl.ChooseFiles(inviteScanExts...)
		if err != nil {
			if !errors.Is(err, explorer.ErrUserDecline) && !errors.Is(err, explorer.ErrNotAvailable) {
				a.setToast("Scan QR: " + err.Error())
			}
			return
		}
		paths, temps := resolveUploadPaths(rcs)
		defer func() {
			for _, t := range temps {
				os.Remove(t)
			}
		}()
		if len(paths) == 0 {
			return
		}
		data, err := os.ReadFile(paths[0])
		if err != nil {
			a.setToast("Scan QR: " + err.Error())
			return
		}
		hash, err := inviteHashFromQRImage(data)
		if err != nil {
			a.setToast(qrScanErrorText(err))
			return
		}
		a.openInviteJoin(hash)
	}()
}

func (a *App) inviteScanField(gtx layout.Context) layout.Dimensions {
	if inviteScanBtn.Clicked(gtx) {
		a.pickAndScanInviteQR()
	}
	return inviteScanBtn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		sz := gtx.Dp(unit.Dp(30))
		if inviteScanBtn.Hovered() {
			r := sz / 3
			stack := clip.RRect{Rect: image.Rect(0, 0, sz, sz), NE: r, NW: r, SE: r, SW: r}.Push(gtx.Ops)
			paint.Fill(gtx.Ops, withAlpha(a.ui.p.Accent, 0x26))
			stack.Pop()
		}
		g := gtx.Dp(unit.Dp(16))
		paintQRGlyph(gtx, (sz-g)/2, (sz-g)/2, g, a.ui.p.TextFaint)
		return layout.Dimensions{Size: image.Pt(sz, sz)}
	})
}

func paintQRGlyph(gtx layout.Context, x, y, side int, col color.NRGBA) {
	t := side / 7
	if t < 1 {
		t = 1
	}
	sq := side * 45 / 100
	if sq < 3*t {
		sq = 3 * t
	}
	if sq > side {
		sq = side
	}
	fill := func(rx, ry, rw, rh int) {
		paint.FillShape(gtx.Ops, col,
			clip.Rect{Min: image.Pt(x+rx, y+ry), Max: image.Pt(x+rx+rw, y+ry+rh)}.Op())
	}
	hollow := func(rx, ry int) {
		fill(rx, ry, t, sq)
		fill(rx+sq-t, ry, t, sq)
		fill(rx, ry, sq, t)
		fill(rx, ry+sq-t, sq, t)
	}
	hollow(0, 0)
	hollow(side-sq, 0)
	hollow(0, side-sq)
	d := t
	ox, oy := side-3*d-1, side-3*d-1
	if ox > sq+1 {
		fill(ox, oy, d, d)
		fill(ox+2*d, oy, d, d)
		fill(ox, oy+2*d, d, d)
		fill(ox+2*d, oy+2*d, d, d)
	}
}
