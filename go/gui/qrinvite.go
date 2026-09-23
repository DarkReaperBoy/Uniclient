// Invite QR scan (AyuGram parity, matrix row 306): the row's stated gap
// was "QR scan remains" next to the invite-link join that shipped in
// slice 24. Desktop has no camera surface (tdesktop ships no camera scan
// either — see research/qr_decoder.md), so the scan is file-based: the
// user picks a QR image, we decode it, and the hash rejoins the existing
// link → preview → confirm flow untouched. The materialdesign icon set
// has no QR glyph, so the button's glyph is drawn here — on the one
// control that actually performs a scan (§1.10: drawn only because it is
// real).
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

// ErrNotInvite: the QR decoded fine, but its payload is not a t.me
// invite link (a foreign URL, a public username, ...). extractInviteHash
// already knows the grammar; this sentinel just names the mismatch for
// the toast.
var ErrNotInvite = errors.New("QR code is not an invite link")

// inviteScanBtn is the scan affordance in the sidebar search field.
var inviteScanBtn widget.Clickable

// inviteScanExts is exactly the set qrscan can decode (png/jpg via std,
// gif via std, webp + bmp via x/image registrations in that package).
// Offering a format we cannot read would make the failure copy a lie.
var inviteScanExts = []string{".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp"}

// inviteHashFromQRImage decodes a picked QR image and returns the invite
// hash it carries. Errors pass through as qrscan.ErrNotImage /
// qrscan.ErrNoQR, or ErrNotInvite when the payload is not an invite.
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

// qrScanErrorText maps a scan failure to the exact copy the toast shows:
// each failure class gets its own real message, never a generic one.
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

// pickAndScanInviteQR opens the OS file picker for an image, decodes the
// first QR symbol in it, and routes the invite hash into the same
// preview-and-confirm flow a pasted link takes. Runs async (the picker
// and the decode both block); user-declined picks stay quiet, real
// failures toast (§1.10).
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

// inviteScanField renders the search field's trailing scan affordance:
// a clickable QR glyph with a faint accent tint on hover.
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

// paintQRGlyph draws the three finder squares plus a data-dot cluster —
// the silhouette that says "QR" without an icon font — at (x,y) with the
// given side length. Pure clip/paint, no text, no assets.
func paintQRGlyph(gtx layout.Context, x, y, side int, col color.NRGBA) {
	t := side / 7 // one module of stroke
	if t < 1 {
		t = 1
	}
	sq := side * 45 / 100 // finder square side
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
		fill(rx, ry, t, sq)      // left edge
		fill(rx+sq-t, ry, t, sq) // right edge
		fill(rx, ry, sq, t)      // top edge
		fill(rx, ry+sq-t, sq, t) // bottom edge
	}
	// three finder patterns: top-left, top-right, bottom-left
	hollow(0, 0)
	hollow(side-sq, 0)
	hollow(0, side-sq)
	// data-dot cluster in the free quadrant (bottom-right)
	d := t
	ox, oy := side-3*d-1, side-3*d-1
	if ox > sq+1 { // keep clear of the finder squares
		fill(ox, oy, d, d)
		fill(ox+2*d, oy, d, d)
		fill(ox, oy+2*d, d, d)
		fill(ox+2*d, oy+2*d, d, d)
	}
}
