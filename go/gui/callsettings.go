package gui

// Calls settings (AyuGram parity slice 103): a Calls section in the
// settings rail with mic/speaker/camera pickers backed by the engine's real
// OS device enumeration (GetAudioDevices — pactl/ALSA on Linux) and the
// persisted per-device config (SetCallAudioDevice). The group-call screen
// gains a per-call noise-suppression toggle (SetNoiseSuppression). Honest
// everywhere: an empty enumeration shows only the Default sentinel; picking
// a device writes it and applies live.

import (
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/utils"
)

// devPickerState is one device type's picker (slice 103).
type devPickerState struct {
	typ     string // "input" | "output" | "camera"
	devices []string
	loaded  bool
}

// deviceType returns the picker's engine device-type key.
func (d *devPickerState) deviceType() string { return d.typ }

// devRow is one selectable device row.
type devRow struct {
	label    string
	value    string // "" = Default (system)
	selected bool
}

// devPickerRows builds the selectable rows: the Default sentinel first,
// then the enumerated devices; the current device marks its row. A stale
// current (device unplugged since last run) selects nothing — never lies.
func devPickerRows(devices []string, current string) []devRow {
	rows := make([]devRow, 0, len(devices)+1)
	rows = append(rows, devRow{label: "Default", value: ""})
	for _, d := range devices {
		rows = append(rows, devRow{label: d, value: d})
	}
	for i := range rows {
		rows[i].selected = rows[i].value == current && (current != "" || i == 0)
	}
	return rows
}

// devPickerLabel renders the current device for the picker's header row.
func devPickerLabel(current string) string {
	if current == "" {
		return "Default"
	}
	return current
}

// gcNoiseLabel renders the in-call noise-suppression toggle label.
func gcNoiseLabel(on bool) string {
	if on {
		return "NOISE SUPPRESSION: ON"
	}
	return "NOISE SUPPRESSION: OFF"
}

// devPickerBtns pools the device row clickables per picker type.
var devPickerBtns = map[string][]widget.Clickable{}

// devPickerBtn returns the i-th row clickable for the picker type.
func devPickerBtn(typ string, i int) *widget.Clickable {
	btns := devPickerBtns[typ]
	growClickables(&btns, i+1)
	devPickerBtns[typ] = btns
	return &btns[i]
}

// devPickerCfgField maps a device type to the snapshot field it reflects.
func devPickerCfgField(typ string) string {
	switch typ {
	case "input":
		return "call_input"
	case "output":
		return "call_output"
	case "camera":
		return "call_camera"
	}
	return ""
}

// cfgFromAppConfig is the pure config → snapshot mapping (extracted from
// refreshConfig for testability).
// effectiveSwipeAction normalizes the stored swipe-action config: unknown
// or empty values mean "disabled" (the tdesktop default).
func effectiveSwipeAction(v string) string {
	switch v {
	case "mute", "pin", "read", "archive", "delete":
		return v
	}
	return "disabled"
}

func cfgFromAppConfig(c *utils.AppConfig) cfgSnapshot {
	ard, arh, arb := antiRecallFromConfig(c)
	return cfgSnapshot{
		Theme:                  c.Theme,
		Accent:                 c.AccentColor,
		FontScale:              c.FontScale,
		FontPath:               c.FontPath,
		MonoFontPath:           c.MonoFontPath,
		ComposerSubmit:         c.ComposerSubmit,
		SwipeAction:            effectiveSwipeAction(c.SwipeAction),
		CornerReply:            effectiveCornerReply(c.CornerReply),
		CornerReaction:         effectiveCornerReaction(c.CornerReaction),
		LocalPremium:           c.LocalPremium,
		AyuImproveLinkPreviews: c.AyuImproveLinkPreviews,
		SendReadReceipts:       c.SendReadReceipts,
		LocalReadMark:          c.LocalReadMark,
		SendTyping:             c.SendTyping,
		SendUploadProgress:     c.SendUploadProgress,
		SendReadStories:        c.SendReadStories,
		SendOnlinePackets:      c.SendOnlinePackets,
		SendOfflineAfterOnline: c.SendOfflineAfterOnline,
		MarkReadAfterAction:    c.MarkReadAfterAction,
		UseScheduledMessages:   c.UseScheduledMessages,
		SendWithoutSound:       c.SendWithoutSound,
		NotifyDMs:              c.NotifyDMs,
		NotifyGroups:           c.NotifyGroups,
		NotifyMentionsOnly:     c.NotifyMentionsOnly,
		NotifyPreviews:         c.NotifyPreviewsEnabled(),
		NotifySound:            c.NotifySound,
		AyuDeletedMark:         c.AyuDeletedMark,
		AyuEditedMark:          c.AyuEditedMark,
		AyuSaveDeleted:         ard,
		AyuSaveHistory:         arh,
		AyuSaveForBots:         arb,
		BubbleCorners:          c.BubbleCorners == nil || *c.BubbleCorners,
		BubbleRadius:           utils.EffectiveBubbleRadius(*c),
		WideMult:               utils.EffectiveWideMultiplier(*c),
		DownloadDir:            c.DownloadDir,
		HideAllChats:           c.HideAllChats,
		RecentSearches:         c.RecentSearches,
		DrawerHidden:           c.DrawerHiddenItems,
		Streamer:               c.StreamerMode,
		SystemTray:             utils.EffectiveSystemTray(*c),
		CallInputDevice:        c.CallInputDevice,
		CallOutputDevice:       c.CallOutputDevice,
		CallCameraDevice:       c.CallCameraDevice,
	}
}

// loadCallDevices enumerates the OS audio/video devices once (slice 103).
// The engine call ignores the account parameter (devices are global); the
// first account ID is passed for API symmetry.
func (a *App) loadCallDevices() {
	a.mu.Lock()
	if a.devPickers != nil {
		a.mu.Unlock()
		return
	}
	acc := ""
	if len(a.accounts) > 0 {
		acc = a.accounts[0].ID
	}
	a.mu.Unlock()
	go func() {
		input, _ := a.eng.GetAudioDevices(acc, "input")
		output, _ := a.eng.GetAudioDevices(acc, "output")
		camera, _ := a.eng.GetAudioDevices(acc, "camera")
		a.mu.Lock()
		if a.devPickers == nil {
			a.devPickers = map[string]*devPickerState{
				"input":  {typ: "input", devices: input, loaded: true},
				"output": {typ: "output", devices: output, loaded: true},
				"camera": {typ: "camera", devices: camera, loaded: true},
			}
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// pickCallDevice applies a device selection (slice 103).
func (a *App) pickCallDevice(typ, device string) {
	go func() {
		// The engine persists the device; account is unused by the engine.
		acc := ""
		a.mu.Lock()
		if len(a.accounts) > 0 {
			acc = a.accounts[0].ID
		}
		a.mu.Unlock()
		if err := a.eng.SetCallAudioDevice(acc, typ, device); err != nil {
			a.setToast("Device failed: " + err.Error())
			return
		}
		a.refreshConfig()
	}()
}

// setPageCalls: the Calls settings page (slice 103) — device pickers.
func (a *App) setPageCalls(gtx layout.Context, f frame) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.sectionTitle(gtx, "Calls")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := a.ui.Dim(unit.Sp(13), "Microphone, speaker, and camera used by voice and video calls.")
			lbl.Color = a.ui.p.TextDim
			return lbl.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.devPickerSection(gtx, f, "input", "Microphone", f.cfg.CallInputDevice)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.devPickerSection(gtx, f, "output", "Speaker", f.cfg.CallOutputDevice)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.devPickerSection(gtx, f, "camera", "Camera", f.cfg.CallCameraDevice)
		}),
	)
}

// devPickerSection renders one device picker: title + current value + rows.
func (a *App) devPickerSection(gtx layout.Context, f frame, typ, title, current string) layout.Dimensions {
	var rows []devRow
	loaded := false
	if f.devPickers != nil {
		if st, ok := f.devPickers[typ]; ok {
			rows = devPickerRows(st.devices, current)
			loaded = st.loaded
		}
	}
	if !loaded {
		return layout.Inset{Top: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, title, "Detecting devices…")
		})
	}
	return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									icon := iconAVMic
									switch typ {
									case "output":
										icon = iconHardwareHeadset
									case "camera":
										icon = iconAVVideocam
									}
									gtx.Constraints.Max.X = gtx.Dp(unit.Dp(18))
									gtx.Constraints.Max.Y = gtx.Dp(unit.Dp(18))
									return icon.Layout(gtx, a.ui.p.TextDim)
								})
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Label(unit.Sp(14), title)
								return lbl.Layout(gtx)
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								lbl := a.ui.Dim(unit.Sp(12), devPickerLabel(current))
								lbl.Color = a.ui.p.Accent
								return lbl.Layout(gtx)
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						var children []layout.FlexChild
						for i, r := range rows {
							i, r := i, r
							children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := devPickerBtn(typ, i)
								if btn.Clicked(gtx) {
									a.pickCallDevice(typ, r.value)
								}
								return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									bl := material.ButtonLayout(a.ui.Theme, btn)
									bl.Background = a.ui.p.SurfaceHi
									if r.selected {
										bl.Background = a.ui.p.Accent
									}
									bl.CornerRadius = 8
									return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(13), r.label)
											if r.selected {
												lbl.Color = a.ui.p.Background
											}
											return lbl.Layout(gtx)
										})
									})
								})
							}))
						}
						return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
					}),
				)
			})
		})
	})
}
