package gui

import (
	"log"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Bot commands menu (AyuGram parity slice 76): a "/" button in the
// composer (only for chats that have bot commands — engine
// GetChatBotCommands, loaded lazily per chat) opens a panel listing every
// command with its description; tapping a row inserts the command into
// the composer. No commands → no button, never a dead control (§1.10).

var (
	botCmdBtn   widget.Clickable
	botCmdBtns  []widget.Clickable
	botCmdClose widget.Clickable
	botCmdList  widget.List
)

func init() {
	botCmdList.Axis = layout.Vertical
}

// botCmdTitle renders the command chip (slash prefixed, never doubled).
func botCmdTitle(c engine.BotCommandInfo) string {
	cmd := strings.TrimSpace(c.Command)
	if cmd == "" {
		return ""
	}
	if !strings.HasPrefix(cmd, "/") {
		cmd = "/" + cmd
	}
	return cmd
}

// botCmdSub renders the description line: "Bot — description".
func botCmdSub(c engine.BotCommandInfo) string {
	sub := strings.TrimSpace(c.Description)
	name := strings.TrimSpace(c.BotName)
	switch {
	case sub == "":
		return ""
	case name == "":
		return sub
	default:
		return name + " — " + sub
	}
}

// botCmdPanelNeeded reports whether the "/" button should render.
func botCmdPanelNeeded(cmds []engine.BotCommandInfo) bool {
	return len(cmds) > 0
}

// botCmdInsertText merges a tapped command into the composer's current
// text (the editor keeps the cursor; this is the fallback merge).
func botCmdInsertText(current, cmd string) string {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return current
	}
	if !strings.HasPrefix(cmd, "/") {
		cmd = "/" + cmd
	}
	if current == "" {
		return cmd + " "
	}
	if !strings.HasSuffix(current, " ") {
		current += " "
	}
	return current + cmd + " "
}

// toggleBotCmds opens/closes the commands panel.
func (a *App) toggleBotCmds() {
	a.mu.Lock()
	a.botCmdsOn = !a.botCmdsOn
	a.attachMenuOpen = false
	a.emojiOpen = false
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) closeBotCmds() {
	a.mu.Lock()
	a.botCmdsOn = false
	a.mu.Unlock()
	a.invalidate()
}

// loadBotCmds fetches the chat's bot commands (async, selected-guarded).
func (a *App) loadBotCmds(k chatKey) {
	go func() {
		cmds, err := a.eng.GetChatBotCommands(k.AccountID, k.ChatID)
		if err != nil {
			log.Printf("gui: bot commands: %v", err)
			cmds = nil
		}
		// Keep only rows with a real command string.
		kept := cmds[:0]
		for _, c := range cmds {
			if strings.TrimSpace(c.Command) != "" {
				kept = append(kept, c)
			}
		}
		a.mu.Lock()
		if cur := a.selected; cur != nil && *cur == k {
			a.botCmds = kept
			a.botCmdsFor = &k
			a.botCmdsLoaded = true
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// layoutBotCmdsPanel: the popup above the composer listing the commands.
func (a *App) layoutBotCmdsPanel(gtx layout.Context, f frame) layout.Dimensions {
	cmds := f.botCmds
	growClickables(&botCmdBtns, len(cmds))
	for i := range cmds {
		if botCmdBtns[i].Clicked(gtx) {
			cmd := botCmdTitle(cmds[i])
			a.insertBotCommand(cmd)
			break
		}
	}
	if botCmdClose.Clicked(gtx) {
		a.closeBotCmds()
	}
	if len(cmds) == 0 {
		return layout.Dimensions{}
	}

	// Panel anchored above the composer, right-aligned like the emoji
	// picker; height capped so long command lists scroll.
	maxH := gtx.Dp(unit.Dp(240))
	if maxH > gtx.Constraints.Max.Y/2 {
		maxH = gtx.Constraints.Max.Y / 2
	}
	gtx.Constraints.Max.Y = maxH
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				list := material.List(a.ui.Theme, &botCmdList)
				return list.Layout(gtx, len(cmds), func(gtx layout.Context, i int) layout.Dimensions {
					c := cmds[i]
					return material.ButtonLayout(a.ui.Theme, &botCmdBtns[i]).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Label(unit.Sp(14), botCmdTitle(c))
										lbl.Color = a.ui.p.Accent
										return lbl.Layout(gtx)
									})
								}),
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									sub := botCmdSub(c)
									if sub == "" {
										return layout.Dimensions{}
									}
									lbl := a.ui.Dim(unit.Sp(12), sub)
									lbl.MaxLines = 1
									return lbl.Layout(gtx)
								}),
							)
						})
					})
				})
			})
		})
	})
}

// insertBotCommand puts the tapped command into the composer (GUI thread).
func (a *App) insertBotCommand(cmd string) {
	if cmd == "" {
		return
	}
	composer.Insert(cmd + " ")
	a.closeBotCmds()
}
