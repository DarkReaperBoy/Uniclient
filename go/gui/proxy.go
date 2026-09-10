package gui

import (
	"strconv"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
	"uniclient/utils"
)

// Connection settings (AyuGram Data & Storage "Proxy", slice 85): proxy
// mode (disabled / system / custom), custom fields for SOCKS5 / HTTP /
// MTProto, Apply pushes engine.SetProxy (immediate — every live core
// redials through it) and persists the AppConfig.ProxyConfig so Init
// restores it. The download-path row switches the engine's downloads
// directory.

var (
	proxyModeBtns     [3]widget.Clickable // disabled / system / custom
	proxyTypeBtns     [3]widget.Clickable // socks5 / http / mtproto
	proxyHostEd       widget.Editor
	proxyPortEd       widget.Editor
	proxyUserEd       widget.Editor
	proxyPassEd       widget.Editor
	proxyApplyBtn     widget.Clickable
	downloadPathEd    widget.Editor
	downloadApplyBtn  widget.Clickable
	proxyEditorsReady bool
)

func init() {
	for _, ed := range []*widget.Editor{&proxyHostEd, &proxyPortEd, &proxyUserEd, &proxyPassEd, &downloadPathEd} {
		ed.SingleLine = true
	}
}

// proxyModeLabels names the three proxy modes.
var proxyModeLabels = []string{"Disabled", "System", "Custom"}

// proxyTypeTokens are the engine's lowercase proxy type tokens.
var proxyTypeTokens = []string{"socks5", "http", "mtproto"}

// proxyModeIndex maps a config mode int to the segment index. Pure.
func proxyModeIndex(mode int) int {
	if mode < 0 || mode > 2 {
		return 0
	}
	return mode
}

// proxyTypeIndex maps a type token to the segment index. Pure.
func proxyTypeIndex(ptype string) int {
	for i, t := range proxyTypeTokens {
		if t == strings.ToLower(strings.TrimSpace(ptype)) {
			return i
		}
	}
	return 0
}

// normalizeProxyPort parses the port editor's text (0 on junk). Pure.
func normalizeProxyPort(s string) int {
	p, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || p < 0 || p > 65535 {
		return 0
	}
	return p
}

// ── state transitions ─────────────────────────────────────────────────────

// applyProxySettings pushes the form to the engine and persists it.
func (a *App) applyProxySettings(mode int, ptype, host, port, user, pass string) {
	portN := normalizeProxyPort(port)
	ptype = strings.ToLower(strings.TrimSpace(ptype))
	go func() {
		a.eng.SetProxy(mode, host, portN, ptype, user, pass, "", false, false, false, 0)
		pc := utils.ProxyConfig{Mode: mode, Type: ptype, Host: host, Port: port, Username: user, Password: pass}
		if err := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{ProxyConfig: &pc}); err != nil {
			a.setToast("Proxy: " + err.Error())
			return
		}
		if mode == 2 && (host == "" || portN == 0) {
			a.setToast("Proxy saved (inactive — host/port incomplete)")
			return
		}
		a.setToast("Proxy applied")
	}()
}

// applyDownloadPath switches the engine downloads directory and persists.
func (a *App) applyDownloadPath(path string) {
	path = strings.TrimSpace(path)
	go func() {
		if err := a.eng.SetDownloadDir(path); err != nil {
			a.setToast("Download path: " + err.Error())
			return
		}
		if err := a.eng.UpdateConfigFromBridge(&engine.ConfigChanges{DownloadDir: path}); err != nil {
			a.setToast("Download path: " + err.Error())
			return
		}
		a.setToast("Downloads will land in " + path)
	}()
}

// ── layout ────────────────────────────────────────────────────────────────

// layoutProxySection renders the proxy + download-path settings block.
// Called from the Data & Storage page.
func (a *App) layoutProxySection(gtx layout.Context, f frame) layout.Dimensions {
	// Seed the editors once from the live engine settings (frame thread;
	// the engine getter is a cheap RLock read).
	if !proxyEditorsReady {
		mode, host, port, ptype, user, pass := a.eng.GetProxySettings()
		proxyHostEd.SetText(host)
		proxyPortEd.SetText(strconv.Itoa(port))
		proxyUserEd.SetText(user)
		proxyPassEd.SetText(pass)
		downloadPathEd.SetText(f.cfg.DownloadDir)
		proxyFormMode = proxyModeIndex(mode)
		proxyFormType = proxyTypeIndex(ptype)
		proxyEditorsReady = true
	}

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Proxy")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Connection", "Route every backend through a proxy (SOCKS5 / HTTP / MTProto)")
	}))

	// Mode segments.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		cells := make([]layout.FlexChild, 0, 3)
		for i, label := range proxyModeLabels {
			i := i
			cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if proxyModeBtns[i].Clicked(gtx) {
					proxyFormMode = i
					a.invalidate()
				}
				return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return segmentChip(gtx, a, &proxyModeBtns[i], label, proxyFormMode == i)
				})
			}))
		}
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
		})
	}))

	if proxyFormMode == 2 {
		// Type segments.
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			cells := make([]layout.FlexChild, 0, 3)
			for i, tok := range proxyTypeTokens {
				i := i
				cells = append(cells, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if proxyTypeBtns[i].Clicked(gtx) {
						proxyFormType = i
						a.invalidate()
					}
					return layout.Inset{Right: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return segmentChip(gtx, a, &proxyTypeBtns[i], strings.ToUpper(tok), proxyFormType == i)
					})
				}))
			}
			return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, cells...)
			})
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.proxyEditorRow(gtx, &proxyHostEd, "Host", "proxy.example.org")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.proxyEditorRow(gtx, &proxyPortEd, "Port", "1080")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.proxyEditorRow(gtx, &proxyUserEd, "Username", "optional")
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.proxyEditorRow(gtx, &proxyPassEd, "Password", "optional")
		}))
	}

	// Apply.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if proxyApplyBtn.Clicked(gtx) {
			a.applyProxySettings(proxyFormMode, proxyTypeTokens[proxyFormType],
				proxyHostEd.Text(), proxyPortEd.Text(), proxyUserEd.Text(), proxyPassEd.Text())
		}
		btn := a.ui.TextButton(&proxyApplyBtn, "Apply proxy")
		btn.Color = a.ui.p.Accent
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(8)}.Layout(gtx, btn.Layout)
	}))

	// Download path.
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.sectionTitle(gtx, "Download path")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Downloads", "Where media and files land after a download")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.proxyEditorRow(gtx, &downloadPathEd, "Path", "empty = the app's downloads dir")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if downloadApplyBtn.Clicked(gtx) {
			a.applyDownloadPath(downloadPathEd.Text())
		}
		btn := a.ui.TextButton(&downloadApplyBtn, "Apply path")
		btn.Color = a.ui.p.Accent
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12)}.Layout(gtx, btn.Layout)
	}))
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

// proxyFormMode/Type are the segment selections (frame thread).
var (
	proxyFormMode int
	proxyFormType int
)

// proxyEditorRow renders a labeled single-line editor.
func (a *App) proxyEditorRow(gtx layout.Context, ed *widget.Editor, label, hint string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(11), label)
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					for {
						ev, ok := ed.Update(gtx)
						if !ok {
							break
						}
						if _, is := ev.(widget.ChangeEvent); is {
							a.invalidate()
						}
					}
					e := a.ui.Editor(ed, hint)
					return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, e.Layout)
					})
				})
			}),
		)
	})
}

// segmentChip renders one selectable segment (accent when active).
func segmentChip(gtx layout.Context, a *App, btn *widget.Clickable, label string, active bool) layout.Dimensions {
	b := material.Button(a.ui.Theme, btn, label)
	b.Background = a.ui.p.SurfaceHi
	b.Color = a.ui.p.TextDim
	b.TextSize = unit.Sp(12)
	b.CornerRadius = 10
	b.Inset = layout.Inset{Top: unit.Dp(5), Bottom: unit.Dp(5), Left: unit.Dp(10), Right: unit.Dp(10)}
	if active {
		b.Background = a.ui.p.AccentDim
		b.Color = a.ui.p.Text
	}
	return b.Layout(gtx)
}
