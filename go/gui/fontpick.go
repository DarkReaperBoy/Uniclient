package gui

// fontpick.go — slice 146: custom fonts (tdesktop's font box, honest
// scope): pick a .ttf/.otf for the UI and optionally a mono variant —
// parsed at runtime (pure Go opentype), applied by swapping the face
// objects inside the default collection (descriptors untouched, so
// matching behaves exactly as before), persisted in AppConfig, restored
// at boot. Parse failures fall back to the defaults with a toast.

import (
	"os"
	"path/filepath"
	"strings"

	"gioui.org/font"
	"gioui.org/font/gofont"
	"gioui.org/font/opentype"
	"gioui.org/layout"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// isFontPath: accepted font file extensions. Pure.
func isFontPath(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".ttf", ".otf":
		return true
	}
	return false
}

// fontFileName: display name for a picked path ("Default" when unset).
// Pure.
func fontFileName(path string) string {
	if path == "" {
		return "Default"
	}
	return filepath.Base(path)
}

// swapCollectionFaces returns a copy of the base collection with the
// default family's (and optionally the Go Mono family's) face objects
// replaced. Descriptors stay untouched — font matching then behaves
// exactly as with the stock collection, only the glyphs differ. Pure.
func swapCollectionFaces(base []font.FontFace, userFace, monoFace font.Face) []font.FontFace {
	if userFace == nil && monoFace == nil {
		return base
	}
	var defaultFamily font.Typeface
	if len(base) > 0 {
		defaultFamily = base[0].Font.Typeface
	}
	out := make([]font.FontFace, len(base))
	for i, ff := range base {
		switch ff.Font.Typeface {
		case defaultFamily:
			if userFace != nil {
				ff.Face = userFace
			}
		case "Go Mono":
			if monoFace != nil {
				ff.Face = monoFace
			}
		}
		out[i] = ff
	}
	return out
}

// parseFontFace loads one font file (nil when the path is empty).
func parseFontFace(path string) (font.Face, error) {
	if path == "" {
		return nil, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return opentype.Parse(data)
}

// applyUserFonts rebuilds the theme's shaper with the picked fonts.
// Empty paths restore the stock collection. The caller invalidates.
func (u *UI) applyUserFonts(userPath, monoPath string) error {
	userFace, err := parseFontFace(userPath)
	if err != nil {
		return err
	}
	monoFace, err := parseFontFace(monoPath)
	if err != nil {
		return err
	}
	if userFace == nil && monoFace == nil {
		u.Theme.Shaper = text.NewShaper(text.WithCollection(baseFontCollection()))
		return nil
	}
	collection := swapCollectionFaces(baseFontCollection(), userFace, monoFace)
	u.Theme.Shaper = text.NewShaper(text.WithCollection(collection))
	return nil
}

// baseFontCollection is the stock collection (Go fonts + NotoEmoji) —
// the same set NewUI installs.
func baseFontCollection() []font.FontFace {
	collection := gofont.Collection()
	if face, err := opentype.Parse(notoEmoji); err == nil {
		collection = append(collection, font.FontFace{
			Font: font.Font{Typeface: "NotoEmoji"},
			Face: face,
		})
	}
	return collection
}

// ── picking + persistence ──────────────────────────────────────────────────

var (
	fontPickBtn  widget.Clickable
	fontResetBtn widget.Clickable
	monoPickBtn  widget.Clickable
	monoResetBtn widget.Clickable
)

// pickUserFont opens the OS file picker for the main UI font (async;
// applies + persists on success).
func (a *App) pickUserFont(mono bool) {
	go func() {
		if a.expl == nil {
			a.setToast("Font picker unavailable on this platform")
			return
		}
		rcs, err := a.expl.ChooseFiles(".ttf", ".otf")
		if err != nil {
			if !strings.Contains(err.Error(), "declined") {
				a.setToast("Font: " + err.Error())
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
			a.setToast("Font: could not read the selected file")
			return
		}
		a.applyUserFontPath(paths[0], mono)
	}()
}

// applyUserFontPath parses, applies and persists one picked font.
func (a *App) applyUserFontPath(path string, mono bool) {
	if !isFontPath(path) {
		a.setToast("Font: pick a .ttf or .otf file")
		return
	}
	var userPath, monoPath string
	a.mu.Lock()
	userPath, monoPath = a.cfg.FontPath, a.cfg.MonoFontPath
	a.mu.Unlock()
	if mono {
		monoPath = path
	} else {
		userPath = path
	}
	if err := a.ui.applyUserFonts(userPath, monoPath); err != nil {
		a.setToast("Font: " + err.Error()) // honest fallback: defaults stay
		return
	}
	k, m := userPath, monoPath
	go func() {
		c := &engine.ConfigChanges{FontPath: &k, MonoFontPath: &m}
		if err := a.eng.UpdateConfigFromBridge(c); err != nil {
			a.setToast("Font: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
	a.setToast("Font applied: " + fontFileName(path))
	a.invalidate()
}

// resetUserFont clears one font pick (mono or main) back to default.
func (a *App) resetUserFont(mono bool) {
	var userPath, monoPath string
	a.mu.Lock()
	userPath, monoPath = a.cfg.FontPath, a.cfg.MonoFontPath
	a.mu.Unlock()
	if mono {
		monoPath = ""
	} else {
		userPath = ""
	}
	if err := a.ui.applyUserFonts(userPath, monoPath); err != nil {
		a.setToast("Font: " + err.Error())
		return
	}
	k, m := userPath, monoPath
	go func() {
		c := &engine.ConfigChanges{FontPath: &k, MonoFontPath: &m}
		if err := a.eng.UpdateConfigFromBridge(c); err != nil {
			a.setToast("Font: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
	a.setToast("Font reset to default")
	a.invalidate()
}

// ── settings row ───────────────────────────────────────────────────────────

// fontSettingsRows renders the Appearance font rows (main + mono).
func (a *App) fontSettingsRows(gtx layout.Context, f frame) []layout.FlexChild {
	if fontPickBtn.Clicked(gtx) {
		a.pickUserFont(false)
	}
	if fontResetBtn.Clicked(gtx) {
		a.resetUserFont(false)
	}
	if monoPickBtn.Clicked(gtx) {
		a.pickUserFont(true)
	}
	if monoResetBtn.Clicked(gtx) {
		a.resetUserFont(true)
	}
	row := func(pick, reset *widget.Clickable, label, value string) layout.FlexChild {
		return layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), label)
										return lbl.Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(11), fontFileName(value))
										return lbl.Layout(gtx)
									}),
								)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := a.ui.SurfaceButton(pick, "Pick")
								return btn.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								if value == "" {
									return layout.Dimensions{}
								}
								return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									btn := a.ui.SurfaceButton(reset, "Reset")
									return btn.Layout(gtx)
								})
							}),
						)
					})
				})
			})
		})
	}
	return []layout.FlexChild{
		row(&fontPickBtn, &fontResetBtn, "Interface font", f.cfg.FontPath),
		row(&monoPickBtn, &monoResetBtn, "Monospace font", f.cfg.MonoFontPath),
	}
}
